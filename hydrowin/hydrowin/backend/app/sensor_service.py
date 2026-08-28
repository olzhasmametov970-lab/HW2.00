"""Синхронизация датчиков машины и разбор ключей BLOCK."""

from __future__ import annotations

import os
import uuid

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models import Machine, Organization, Reading, Sensor
from app.org_types import ORG_TYPE_MANUFACTURER, ORG_TYPE_PLATFORM
from app.sensor_catalog import (
    default_sensor_specs,
    resolve_type_from_key,
    spec_to_sensor_kwargs,
)

MACHINE_CODE = os.environ.get("MACHINE_CODE", "1783422691603")
BLOCK_WS_URL = os.environ.get("BLOCK_WS_URL", "ws://192.168.1.34:81")


def BLOCK_ip() -> str:
    """IP блока BLOCK из BLOCK_WS_URL (ws://192.168.1.34:81 → 192.168.1.34)."""
    host = BLOCK_WS_URL.split("://")[-1]
    return host.split(":")[0].split("/")[0]


def _first_organization(db: Session) -> Organization:
    org = (
        db.query(Organization)
        .filter(Organization.org_type == ORG_TYPE_MANUFACTURER)
        .order_by(Organization.created_at)
        .first()
    )
    if org is None:
        org = (
            db.query(Organization)
            .filter(Organization.org_type == ORG_TYPE_PLATFORM)
            .order_by(Organization.created_at)
            .first()
        )
    if org is None:
        org = db.query(Organization).order_by(Organization.created_at).first()
    if org is None:
        org = Organization(
            id=str(uuid.uuid4()),
            name="HydroMaker",
            org_type=ORG_TYPE_MANUFACTURER,
        )
        db.add(org)
        db.flush()
    return org


def ensure_BLOCK_machine(db: Session) -> Machine:
    """Гарантирует запись Machine для BLOCK."""
    ip = BLOCK_ip()
    machine = db.query(Machine).filter(Machine.code == MACHINE_CODE).first()
    if machine is None:
        machine = (
            db.query(Machine)
            .filter(Machine.location_label == ip)
            .order_by(Machine.last_seen_at.desc().nullslast())
            .first()
        )
    if machine is None:
        org = _first_organization(db)
        mfr_id = (
            org.id
            if org.org_type == ORG_TYPE_MANUFACTURER
            else getattr(org, "manufacturer_id", None) or org.id
        )
        machine = Machine(
            organization_id=org.id,
            manufacturer_id=mfr_id,
            code=MACHINE_CODE,
            name="Станок",
            status="ok",
            location_label=ip,
        )
        db.add(machine)
        db.flush()
        print(f"✅ Создана машина : code={MACHINE_CODE}, ip={ip}, id={machine.id}")

    dedupe_sensors_for_machine(db, machine.id)
    ensure_machine_sensors(db, machine)
    return machine


def resolve_machine_by_location(db: Session, location_label: str) -> Machine | None:
    if location_label == BLOCK_ip():
        by_block = db.query(Machine).filter(Machine.code == MACHINE_CODE).first()
        if by_block is not None:
            return by_block

    candidates = (
        db.query(Machine).filter(Machine.location_label == location_label).all()
    )
    if not candidates:
        by_code = db.query(Machine).filter(Machine.code == location_label).first()
        return by_code
    if len(candidates) == 1:
        return candidates[0]

    for machine in candidates:
        if machine.code == MACHINE_CODE:
            return machine

    def reading_count(machine_id: str) -> int:
        return (
            db.query(func.count(Reading.id))
            .filter(Reading.machine_id == machine_id)
            .scalar()
            or 0
        )

    candidates.sort(key=lambda m: reading_count(m.id), reverse=True)
    return candidates[0]


def channel_from_BLOCK_key(key: str) -> int | None:
    """Совместимость: возвращает номер канала по ключу телеметрии."""
    _stype, ch = resolve_type_from_key(key)
    return ch


def _next_free_channel(db: Session, machine_id: str) -> int:
    from app.sensor_catalog import MAX_ADC_CHANNELS

    used = {
        row[0]
        for row in db.query(Sensor.channel_index)
        .filter(Sensor.machine_id == machine_id)
        .all()
    }
    for ch in range(MAX_ADC_CHANNELS):
        if ch not in used:
            return ch
    raise ValueError(
        f"Все {MAX_ADC_CHANNELS} каналов ADC1 (CH0–CH5) заняты"
    )


def ensure_machine_sensors(db: Session, machine: Machine) -> list[Sensor]:
    """
    Если у машины ещё нет датчиков — создаёт стартовый набор
    (pressure + temperature). Уже настроенный список не трогает
    (удалённые вручную каналы не воскрешает).
    """
    all_sensors = (
        db.query(Sensor)
        .filter(Sensor.machine_id == machine.id)
        .order_by(Sensor.channel_index)
        .all()
    )
    if all_sensors:
        return all_sensors

    for spec in default_sensor_specs():
        sensor = Sensor(machine_id=machine.id, **spec)
        db.add(sensor)
        db.flush()

    return (
        db.query(Sensor)
        .filter(Sensor.machine_id == machine.id)
        .order_by(Sensor.channel_index)
        .all()
    )

def ensure_sensor_for_telemetry_key(
    db: Session,
    machine: Machine,
    key: str,
) -> Sensor | None:
    """
    Находит или создаёт датчик под ключ пакета телеметрии.
    Поддерживает pressure/temp/... aliases и явные chN.
    """
    stype, ch_hint = resolve_type_from_key(key)
    if ch_hint is None and stype is None:
        return None

    if ch_hint is not None:
        from app.sensor_catalog import MAX_ADC_CHANNELS

        if ch_hint < 0 or ch_hint >= MAX_ADC_CHANNELS:
            return None
        sensor = (
            db.query(Sensor)
            .filter(
                Sensor.machine_id == machine.id,
                Sensor.channel_index == ch_hint,
            )
            .first()
        )
        if sensor is not None:
            return sensor
        # Создаём на указанном канале
        kwargs = spec_to_sensor_kwargs(
            stype or "custom",
            channel_index=ch_hint,
        )
        sensor = Sensor(machine_id=machine.id, **kwargs)
        db.add(sensor)
        db.flush()
        print(
            f"✅ Авто-датчик: ch{ch_hint} type={kwargs['type']} "
            f"name={kwargs['name']} (ключ '{key}')"
        )
        return sensor

    # Тип известен, канал — preferred или свободный
    assert stype is not None
    preferred = spec_to_sensor_kwargs(stype, channel_index=0)  # temp
    from app.sensor_catalog import SENSOR_CATALOG

    preferred_ch = int(SENSOR_CATALOG[stype]["preferred_channel"])
    sensor = (
        db.query(Sensor)
        .filter(
            Sensor.machine_id == machine.id,
            Sensor.type == stype,
        )
        .first()
    )
    if sensor is not None:
        return sensor

    occupied = (
        db.query(Sensor)
        .filter(
            Sensor.machine_id == machine.id,
            Sensor.channel_index == preferred_ch,
        )
        .first()
    )
    ch = preferred_ch if occupied is None else _next_free_channel(db, machine.id)
    kwargs = spec_to_sensor_kwargs(stype, channel_index=ch)
    sensor = Sensor(machine_id=machine.id, **kwargs)
    db.add(sensor)
    db.flush()
    print(f"✅ Авто-датчик: ch{ch} type={stype} (ключ '{key}')")
    return sensor


def add_sensor_to_machine(
    db: Session,
    machine: Machine,
    *,
    sensor_type: str,
    name: str | None = None,
    channel_index: int | None = None,
) -> Sensor:
    """Явное добавление датчика админом."""
    from app.sensor_catalog import MAX_ADC_CHANNELS

    if channel_index is not None and (
        channel_index < 0 or channel_index >= MAX_ADC_CHANNELS
    ):
        raise ValueError(
            f"Канал должен быть 0…{MAX_ADC_CHANNELS - 1} (CH0–CH5, ADC1)"
        )
    ch = (
        channel_index
        if channel_index is not None
        else _next_free_channel(db, machine.id)
    )
    existing = (
        db.query(Sensor)
        .filter(Sensor.machine_id == machine.id, Sensor.channel_index == ch)
        .first()
    )
    if existing is not None:
        raise ValueError(f"Канал {ch} уже занят датчиком «{existing.name}»")

    kwargs = spec_to_sensor_kwargs(sensor_type, channel_index=ch, name=name)
    sensor = Sensor(machine_id=machine.id, **kwargs)
    db.add(sensor)
    db.flush()
    return sensor


def dedupe_sensors_for_machine(db: Session, machine_id: str) -> list[str]:
    """Дубли на одном channel_index → один keeper с наибольшим числом readings."""
    actions: list[str] = []
    channels = [
        row[0]
        for row in db.query(Sensor.channel_index)
        .filter(Sensor.machine_id == machine_id)
        .distinct()
        .all()
    ]
    for ch in channels:
        sensors = (
            db.query(Sensor)
            .filter(Sensor.machine_id == machine_id, Sensor.channel_index == ch)
            .all()
        )
        if len(sensors) <= 1:
            continue

        def reading_count(s: Sensor) -> int:
            return (
                db.query(func.count(Reading.id))
                .filter(Reading.sensor_id == s.id)
                .scalar()
                or 0
            )

        sensors.sort(key=reading_count, reverse=True)
        keeper, *duplicates = sensors
        for dup in duplicates:
            moved = (
                db.query(Reading)
                .filter(Reading.sensor_id == dup.id)
                .update({"sensor_id": keeper.id}, synchronize_session=False)
            )
            db.delete(dup)
            actions.append(
                f"ch{ch}: merged {dup.id} → {keeper.id} ({moved} readings)"
            )
    return actions
