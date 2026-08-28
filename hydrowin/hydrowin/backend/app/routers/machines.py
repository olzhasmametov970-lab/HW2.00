from datetime import datetime
import logging
import secrets
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.database import get_db
from app.deps import (
    is_admin,
    machine_to_detail,
    machine_to_summary,
    require_admin,
    require_staff,
    sensor_to_json,
)
from app.geo import apply_machine_gps
from app.cell_cache import remember_cell_from_machine
from app.machine_photo_storage import (
    delete_machine_photo,
    save_machine_photo_base64,
)
from app.models import Device, Event, Machine, Organization, Reading, Sensor, User
from app.org_access import (
    can_reassign_machine,
    can_write_machine,
    get_user_org,
    is_manufacturer_org,
    is_platform_org,
    machine_access_for_user,
    machines_visible_query,
)
from app.org_types import ORG_TYPE_CLIENT, ORG_TYPE_MANUFACTURER
from app.live_telemetry import fleet_live_for_user, machine_live_json
from app.purge import purge_machine
from app.readings_archive import parse_api_datetime, query_history_points

logger = logging.getLogger(__name__)
from app.security import effective_machine_status, hash_device_key
from app.sensor_catalog import list_catalog
from app.sensor_service import (
    BLOCK_ip,
    MACHINE_CODE,
    add_sensor_to_machine,
    ensure_BLOCK_machine,
    ensure_machine_sensors,
    resolve_machine_by_location,
)
router = APIRouter(tags=["machines", "telemetry"])


def _org_name(db: Session, org_id: str | None, cache: dict[str, str]) -> str | None:
    if not org_id:
        return None
    if org_id in cache:
        return cache[org_id]
    org = db.get(Organization, org_id)
    name = org.name if org else None
    if name:
        cache[org_id] = name
    return name


def _looks_like_uuid(value: str) -> bool:
    return len(value) == 36 and value.count("-") == 4


def _resolve_machine(
    db: Session,
    key: str,
    *,
    allow_ensure: bool,
) -> Machine | None:
    """Находит машину по UUID, IP/location_label или code."""
    machine: Machine | None = None
    if _looks_like_uuid(key):
        machine = db.get(Machine, key)
    if machine is None:
        machine = resolve_machine_by_location(db, key)
    if machine is None:
        machine = db.query(Machine).filter(Machine.code == key).first()
    if (machine is None and allow_ensure and (
        key == BLOCK_ip() or key == MACHINE_CODE
    )):
        machine = ensure_BLOCK_machine(db)
        db.commit()
    return machine


def _require_view(db: Session, user: User, machine: Machine | None) -> tuple[Machine, str]:
    if machine is None:
        raise HTTPException(
            status_code=404,
            detail={"code": "not_found", "message": "Машина не найдена"},
        )
    access = machine_access_for_user(db, user, machine)
    if access is None:
        raise HTTPException(
            status_code=404,
            detail={"code": "not_found", "message": "Машина не найдена"},
        )
    return machine, access


def _require_write(db: Session, user: User, machine: Machine | None) -> Machine:
    machine, access = _require_view(db, user, machine)
    if not can_write_machine(db, user, machine):
        raise HTTPException(
            status_code=403,
            detail={
                "code": "forbidden",
                "message": "Машина принадлежит другому клиенту — только просмотр",
            },
        )
    return machine


class TransferMachineRequest(BaseModel):
    client_organization_id: str = Field(min_length=36, max_length=36)


class AssignManufacturerRequest(BaseModel):
    manufacturer_organization_id: str = Field(min_length=36, max_length=36)


class AddSensorRequest(BaseModel):
    type: str = Field(min_length=1, max_length=32)
    name: str | None = Field(default=None, max_length=128)
    channel_index: int | None = Field(default=None, ge=0, le=5)


class CreateDeviceRequest(BaseModel):
    """Новый ключ ingest для отдельной платы на этой машине."""
    device_id: str | None = Field(
        default=None,
        max_length=64,
        description="Метка платы, напр. HW-HYDRO-02. Если пусто — сгенерируется.",
    )


class CreateMachineRequest(BaseModel):
    """Новая машина в парке (+ опционально плата с ключом)."""
    code: str = Field(min_length=1, max_length=32)
    name: str = Field(min_length=1, max_length=255)
    model: str = Field(default="", max_length=128)
    location_label: str = Field(default="", max_length=255)
    device_id: str | None = Field(
        default=None,
        max_length=64,
        description="Если задан — сразу создаётся Device и возвращается device_key.",
    )
    manufacturer_organization_id: str | None = Field(
        default=None,
        min_length=36,
        max_length=36,
        description="Админ платформы: закрепить за производителем (склад).",
    )


@router.get("/sensor-catalog")
def get_sensor_catalog(user: User = Depends(require_staff)):
    """Список поддерживаемых типов датчиков (для UI «добавить датчик»)."""
    return {"items": list_catalog()}


@router.post("/machines", status_code=201)
def create_machine(
    body: CreateMachineRequest,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """
    Админ платформы регистрирует машину (+ опционально Device).
    Можно сразу закрепить за производителем.
    """
    org = get_user_org(db, user)
    if org is None:
        raise HTTPException(
            status_code=404,
            detail={"code": "not_found", "message": "Организация не найдена"},
        )
    if not is_platform_org(org):
        raise HTTPException(
            status_code=403,
            detail={
                "code": "forbidden",
                "message": "Регистрировать платы может только админ платформы",
            },
        )

    maker_id = body.manufacturer_organization_id
    if maker_id:
        maker = db.get(Organization, maker_id)
        if maker is None or maker.org_type != ORG_TYPE_MANUFACTURER:
            raise HTTPException(
                status_code=400,
                detail={
                    "code": "bad_request",
                    "message": "Укажите организацию-производителя",
                },
            )
        owner_id = maker.id
        manufacturer_id = maker.id
    else:
        owner_id = org.id
        manufacturer_id = None

    code = body.code.strip()
    if not code:
        raise HTTPException(
            status_code=400,
            detail={"code": "bad_request", "message": "Укажите код машины"},
        )
    existing = (
        db.query(Machine)
        .filter(Machine.organization_id == owner_id, Machine.code == code)
        .first()
    )
    if existing is not None:
        raise HTTPException(
            status_code=400,
            detail={"code": "bad_request", "message": f"Код уже занят: {code}"},
        )

    machine = Machine(
        organization_id=owner_id,
        manufacturer_id=manufacturer_id,
        code=code,
        name=body.name.strip() or f"Машина {code}",
        model=(body.model or "").strip(),
        status="offline",
        location_label=(body.location_label or "").strip(),
    )
    db.add(machine)
    db.flush()
    ensure_machine_sensors(db, machine)

    device_payload: dict | None = None
    label = (body.device_id or "").strip()
    if label:
        if db.query(Device).filter(Device.device_id == label).first():
            raise HTTPException(
                status_code=400,
                detail={
                    "code": "bad_request",
                    "message": f"device_id уже занят: {label}",
                },
            )
        plain_key = secrets.token_urlsafe(32)
        device = Device(
            device_id=label,
            machine_id=machine.id,
            api_key_hash=hash_device_key(plain_key),
        )
        db.add(device)
        db.flush()
        device_payload = {
            "id": device.id,
            "device_id": device.device_id,
            "device_key": plain_key,
            "use_header": "X-Device-Key",
            "mqtt_topic": f"hydrowin/telemetry/{device.device_id}",
            "note": "Ключ показывается один раз. Впиши DEVICE_KEY и DEVICE_ID в Serial.",
        }

    db.commit()
    db.refresh(machine)
    access = machine_access_for_user(db, user, machine) or "owner"
    result = machine_to_detail(
        machine,
        access=access,
        owner_org_name=_org_name(db, machine.organization_id, {}),
        can_reassign=can_reassign_machine(db, user, machine),
    )
    if device_payload is not None:
        result["device"] = device_payload
    return result


@router.post("/machines/{ip_address}/sensors", status_code=201)
def create_sensor(
    ip_address: str,
    body: AddSensorRequest,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Админ добавляет датчик на машину (любой тип из каталога или custom)."""
    machine = _resolve_machine(db, ip_address, allow_ensure=True)
    machine = _require_write(db, user, machine)
    try:
        sensor = add_sensor_to_machine(
            db,
            machine,
            sensor_type=body.type.strip().lower(),
            name=body.name.strip() if body.name else None,
            channel_index=body.channel_index,
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=400,
            detail={"code": "bad_request", "message": str(exc)},
        ) from exc
    db.commit()
    db.refresh(sensor)
    return sensor_to_json(sensor)


@router.delete("/machines/{ip_address}/sensors/{sensor_id}")
def delete_sensor(
    ip_address: str,
    sensor_id: str,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Удаляет датчик с машины и его историю показаний."""
    machine = _resolve_machine(db, ip_address, allow_ensure=False)
    machine = _require_write(db, user, machine)
    sensor = db.get(Sensor, sensor_id)
    if sensor is None or sensor.machine_id != machine.id:
        raise HTTPException(
            status_code=404,
            detail={"code": "not_found", "message": "Датчик не найден"},
        )

    channel = sensor.channel_index
    db.query(Reading).filter(Reading.sensor_id == sensor.id).delete(
        synchronize_session=False
    )
    db.delete(sensor)
    db.commit()
    return {
        "deleted": True,
        "id": sensor_id,
        "channel_index": channel,
        "hint": f"На плате: DISABLE {channel}",
    }


@router.get("/machines")
def list_machines(
    status: str | None = Query(None),
    q: str | None = Query(None),
    user: User = Depends(require_staff),
    db: Session = Depends(get_db),
):
    query = machines_visible_query(db, user)
    if q:
        like = f"%{q}%"
        query = query.filter(
            (Machine.code.ilike(like))
            | (Machine.name.ilike(like))
            | (Machine.model.ilike(like))
            | (Machine.location_label.ilike(like))
        )
    machines = query.order_by(Machine.code).all()

    totals = {"total": 0, "ok": 0, "warning": 0, "critical": 0, "offline": 0}
    items = []
    name_cache: dict[str, str] = {}
    for m in machines:
        access = machine_access_for_user(db, user, m)
        if access is None:
            continue
        eff = effective_machine_status(m)
        totals["total"] += 1
        if eff in totals:
            totals[eff] += 1
        if status and eff != status:
            continue
        items.append(
            machine_to_summary(
                m,
                access=access,
                owner_org_name=_org_name(db, m.organization_id, name_cache),
                can_reassign=can_reassign_machine(db, user, m),
                can_configure=can_write_machine(db, user, m),
            )
        )

    return {"items": items, "totals": totals}


@router.get("/fleet/live")
def get_fleet_live(
    user: User = Depends(require_staff),
    db: Session = Depends(get_db),
):
    """Последние показания всех видимых машин — один запрос для парка."""
    return fleet_live_for_user(db, user)


@router.get("/machines/{ip_address}/live")
def get_machine_live(
    ip_address: str,
    user: User = Depends(require_staff),
    db: Session = Depends(get_db),
):
    """Последние показания всех датчиков машины (без скана readings)."""
    machine = _resolve_machine(db, ip_address, allow_ensure=False)
    machine, _access = _require_view(db, user, machine)
    sensors = (
        db.query(Sensor)
        .filter(Sensor.machine_id == machine.id)
        .order_by(Sensor.channel_index)
        .all()
    )
    return machine_live_json(machine, sensors)


@router.get("/machines/{ip_address}")
def get_machine(
    ip_address: str,
    user: User = Depends(require_staff),
    db: Session = Depends(get_db),
):
    # Автосоздание только если админ и пишет в свою org (склад)
    allow_ensure = is_admin(user) and True
    machine = _resolve_machine(db, ip_address, allow_ensure=allow_ensure)
    machine, access = _require_view(db, user, machine)
    return machine_to_detail(
        machine,
        access=access,
        owner_org_name=_org_name(db, machine.organization_id, {}),
        can_reassign=can_reassign_machine(db, user, machine),
        can_configure=can_write_machine(db, user, machine),
    )


@router.put("/machines/{ip_address}")
def update_machine(
    ip_address: str,
    body: dict,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Обновляет имя, оператора, локацию и GPS. Создаёт машину только если ключ = IP."""
    org = get_user_org(db, user)
    manufacturer_id = (
        org.id if is_manufacturer_org(org) else getattr(org, "manufacturer_id", None)
    )

    machine = _resolve_machine(db, ip_address, allow_ensure=False)

    if machine is not None:
        machine = _require_write(db, user, machine)
    elif not _looks_like_uuid(ip_address):
        # Не создаём второй станок на тот же IP — обновляем существующий
        existing = resolve_machine_by_location(db, ip_address)
        if existing is None and ip_address == BLOCK_ip():
            existing = db.query(Machine).filter(Machine.code == MACHINE_CODE).first()
        if existing is not None:
            machine = _require_write(db, user, existing)
        else:
            machine = Machine(
                organization_id=user.organization_id,
                manufacturer_id=manufacturer_id,
                code=str(body.get("code", "000")),
                name=body.get("name", f"Машина {ip_address}"),
                status="ok",
                location_label=body.get("location_label", ip_address) or ip_address,
                operator_name=body.get("operator_name", "") or "",
            )
            if "model" in body:
                machine.model = body["model"]
            db.add(machine)
            db.flush()
    else:
        raise HTTPException(
            status_code=404,
            detail={"code": "not_found", "message": "Машина не найдена"},
        )

    if "code" in body and body["code"] is not None:
        machine.code = str(body["code"])
    if "name" in body and body["name"] is not None:
        machine.name = str(body["name"]).strip() or machine.name
    if "model" in body and body["model"] is not None:
        machine.model = str(body["model"])
    if "operator_name" in body and body["operator_name"] is not None:
        machine.operator_name = str(body["operator_name"]).strip()
    if "location_label" in body and body["location_label"] is not None:
        machine.location_label = str(body["location_label"]).strip()
    if "pump_on_pressure_bar" in body and body["pump_on_pressure_bar"] is not None:
        machine.pump_on_pressure_bar = float(body["pump_on_pressure_bar"])
    if "pump_on_temperature_c" in body and body["pump_on_temperature_c"] is not None:
        machine.pump_on_temperature_c = float(body["pump_on_temperature_c"])
    if "description" in body and body["description"] is not None:
        machine.description = str(body["description"]).strip() or None
    if body.get("clear_photo"):
        delete_machine_photo(machine.id)
        machine.photo_ext = None
    elif body.get("photo_base64"):
        try:
            machine.photo_ext = save_machine_photo_base64(
                machine.id, str(body["photo_base64"])
            )
        except ValueError as exc:
            raise HTTPException(
                status_code=400,
                detail={"code": "invalid_photo", "message": str(exc)},
            ) from exc

    gps = body.get("gps")
    if isinstance(gps, dict):
        if gps.get("lat") is not None and gps.get("lon") is not None:
            lat = float(gps["lat"])
            lon = float(gps["lon"])
            acc = (
                float(gps["accuracy_m"])
                if gps.get("accuracy_m") is not None
                else None
            )
            apply_machine_gps(
                db,
                machine,
                lat=lat,
                lon=lon,
                accuracy_m=acc,
                source="manual",
            )
            remember_cell_from_machine(
                db, machine, lat=lat, lon=lon, accuracy_m=acc
            )
    else:
        if (
            "gps_lat" in body
            and body["gps_lat"] is not None
            and "gps_lon" in body
            and body["gps_lon"] is not None
        ):
            lat = float(body["gps_lat"])
            lon = float(body["gps_lon"])
            apply_machine_gps(
                db,
                machine,
                lat=lat,
                lon=lon,
                source="manual",
            )
            remember_cell_from_machine(db, machine, lat=lat, lon=lon, accuracy_m=30.0)

    db.commit()
    db.refresh(machine)
    return machine_to_detail(machine, access="owner")


@router.delete("/machines/id/{machine_id}")
def delete_machine(
    machine_id: str,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Удаление машины с сервера — только админ платформы."""
    org = get_user_org(db, user)
    if not is_platform_org(org):
        raise HTTPException(
            status_code=403,
            detail={
                "code": "forbidden",
                "message": "Удалять платы может только админ платформы",
            },
        )
    machine = db.get(Machine, machine_id)
    if machine is None:
        raise HTTPException(
            status_code=404,
            detail={"code": "not_found", "message": "Машина не найдена"},
        )
    purge_machine(db, machine)
    db.commit()
    return {"deleted": True, "id": machine_id}


@router.post("/machines/id/{machine_id}/transfer")
def transfer_machine(
    machine_id: str,
    body: TransferMachineRequest,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Передача / перепродажа завода-клиента. Только производитель."""
    org = get_user_org(db, user)
    if not is_manufacturer_org(org):
        raise HTTPException(
            status_code=403,
            detail={
                "code": "forbidden",
                "message": "Заводы назначает только производитель",
            },
        )

    machine = db.get(Machine, machine_id)
    if machine is None or not can_reassign_machine(db, user, machine):
        raise HTTPException(
            status_code=404,
            detail={"code": "not_found", "message": "Машина не найдена"},
        )

    client = db.get(Organization, body.client_organization_id)
    if (
        client is None
        or client.org_type != ORG_TYPE_CLIENT
        or client.manufacturer_id != org.id
    ):
        raise HTTPException(
            status_code=400,
            detail={"code": "bad_request", "message": "Укажите завод этого производителя"},
        )

    machine.organization_id = client.id
    machine.manufacturer_id = org.id
    machine.sold_at = datetime.utcnow()
    db.commit()
    access = machine_access_for_user(db, user, machine) or "manufacturer_readonly"
    return machine_to_detail(
        machine,
        access=access,
        owner_org_name=client.name,
        can_reassign=True,
    )


@router.post("/machines/id/{machine_id}/assign-manufacturer")
def assign_manufacturer(
    machine_id: str,
    body: AssignManufacturerRequest,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Админ платформы закрепляет машину за производителем (склад)."""
    org = get_user_org(db, user)
    if not is_platform_org(org):
        raise HTTPException(
            status_code=403,
            detail={
                "code": "forbidden",
                "message": "Назначать производителя может только админ платформы",
            },
        )

    machine = db.get(Machine, machine_id)
    if machine is None:
        raise HTTPException(
            status_code=404,
            detail={"code": "not_found", "message": "Машина не найдена"},
        )

    maker = db.get(Organization, body.manufacturer_organization_id)
    if maker is None or maker.org_type != ORG_TYPE_MANUFACTURER:
        raise HTTPException(
            status_code=400,
            detail={"code": "bad_request", "message": "Укажите организацию-производителя"},
        )

    machine.manufacturer_id = maker.id
    machine.organization_id = maker.id
    machine.sold_at = None
    db.commit()
    return machine_to_detail(
        machine,
        access="platform",
        owner_org_name=maker.name,
        can_reassign=True,
    )


@router.get("/machines/id/{machine_id}/devices")
def list_machine_devices(
    machine_id: str,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Список плат (устройств), привязанных к машине. Ключи не показываются."""
    machine = db.get(Machine, machine_id)
    machine = _require_view(db, user, machine)[0]
    devices = (
        db.query(Device)
        .filter(Device.machine_id == machine.id)
        .order_by(Device.device_id)
        .all()
    )
    return {
        "machine_id": machine.id,
        "machine_code": machine.code,
        "items": [
            {"id": d.id, "device_id": d.device_id, "machine_id": d.machine_id}
            for d in devices
        ],
    }


@router.post("/machines/id/{machine_id}/devices", status_code=201)
def create_machine_device(
    machine_id: str,
    body: CreateDeviceRequest,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """
    Создаёт отдельный X-Device-Key для новой платы на этой станции.
    Ключ возвращается один раз — сохрани в config.h платы.
    Несколько плат → один MACHINE_ID, разные DEVICE_KEY и каналы датчиков.
    """
    machine = db.get(Machine, machine_id)
    machine = _require_write(db, user, machine)

    label = (body.device_id or "").strip()
    if not label:
        label = f"HW-{uuid.uuid4().hex[:8].upper()}"

    if db.query(Device).filter(Device.device_id == label).first():
        raise HTTPException(
            status_code=400,
            detail={"code": "bad_request", "message": f"device_id уже занят: {label}"},
        )

    plain_key = secrets.token_urlsafe(32)
    device = Device(
        device_id=label,
        machine_id=machine.id,
        api_key_hash=hash_device_key(plain_key),
    )
    db.add(device)
    db.commit()
    db.refresh(device)

    return {
        "id": device.id,
        "device_id": device.device_id,
        "machine_id": machine.id,
        "machine_code": machine.code,
        "device_key": plain_key,
        "use_header": "X-Device-Key",
        "mqtt_topic": f"hydrowin/telemetry/{device.device_id}",
        "mqtt_note": "Продакшен: HTTPS POST /v1/ingest/telemetry + X-Device-Key. MQTT — только LAN (опционально).",
        "note": "Ключ показывается один раз. Serial: KEY <value> (не коммитьте в config.h).",
    }


@router.delete("/machines/id/{machine_id}/devices/{device_row_id}")
def delete_machine_device(
    machine_id: str,
    device_row_id: str,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Отвязать / удалить ключ платы."""
    machine = db.get(Machine, machine_id)
    machine = _require_write(db, user, machine)
    device = db.get(Device, device_row_id)
    if device is None or device.machine_id != machine.id:
        raise HTTPException(
            status_code=404,
            detail={"code": "not_found", "message": "Устройство не найдено"},
        )
    db.delete(device)
    db.commit()
    return {"deleted": True, "id": device_row_id}


@router.get("/machines/{ip_address}/sensors")
def list_sensors(
    ip_address: str,
    user: User = Depends(require_staff),
    db: Session = Depends(get_db),
):
    machine = _resolve_machine(
        db, ip_address, allow_ensure=is_admin(user) and True
    )
    machine, access = _require_view(db, user, machine)

    # Только создать стартовый набор, если датчиков ещё нет.
    # Тяжёлый dedupe здесь НЕ вызываем — на машинах с большой историей
    # он блокировал GET /sensors на минуты (бесконечный спиннер в приложении).
    if is_admin(user) and can_write_machine(db, user, machine):
        sensors = ensure_machine_sensors(db, machine)
        db.commit()
    else:
        sensors = (
            db.query(Sensor)
            .filter(Sensor.machine_id == machine.id)
            .order_by(Sensor.channel_index)
            .all()
        )

    return [sensor_to_json(s) for s in sensors]


@router.put("/machines/{ip_address}/sensors")
def update_sensors(
    ip_address: str,
    body: list[dict],
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    machine = _resolve_machine(db, ip_address, allow_ensure=True)
    machine = _require_write(db, user, machine)

    for item in body:
        sensor = db.get(Sensor, item.get("id"))
        if sensor and sensor.machine_id == machine.id:
            for key in (
                "name",
                "type",
                "unit",
                "scale_min",
                "scale_max",
                "norm_min",
                "norm_max",
                "warn_high",
                "critical_high",
                "critical_low",
                "channel_index",
                "enabled",
            ):
                if key in item:
                    setattr(sensor, key, item[key])

    db.commit()
    sensors = db.query(Sensor).filter(Sensor.machine_id == machine.id).all()
    return [sensor_to_json(s) for s in sensors]


@router.get("/machines/{ip_address}/readings")
def get_readings(
    ip_address: str,
    sensor_id: str = Query(...),
    from_: str | None = Query(None, alias="from"),
    to: str | None = Query(None),
    user: User = Depends(require_staff),
    db: Session = Depends(get_db),
):
    machine = _resolve_machine(db, ip_address, allow_ensure=False)
    machine, _access = _require_view(db, user, machine)

    sensor = db.get(Sensor, sensor_id)
    if sensor is None or sensor.machine_id != machine.id:
        raise HTTPException(
            status_code=404,
            detail={"code": "not_found", "message": "Датчик не найден"},
        )

    try:
        dt_from = (
            parse_api_datetime(from_)
            if from_
            else datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
        )
        dt_to = parse_api_datetime(to) if to else datetime.utcnow()
    except ValueError as exc:
        raise HTTPException(
            status_code=400,
            detail={"code": "bad_time", "message": "Некорректный интервал графика"},
        ) from exc

    try:
        points, meta = query_history_points(
            db,
            machine_id=machine.id,
            sensor_id=sensor_id,
            dt_from=dt_from,
            dt_to=dt_to,
        )
    except Exception as exc:
        logger.exception(
            "readings query failed machine=%s sensor=%s from=%s to=%s",
            machine.id,
            sensor_id,
            from_,
            to,
        )
        raise HTTPException(
            status_code=500,
            detail={
                "code": "readings_query_failed",
                "message": "Не удалось построить график. Повторите попытку.",
            },
        ) from exc

    return {
        "sensor_id": sensor_id,
        "unit": sensor.unit,
        "points": points,
        "meta": meta,
    }
