from datetime import datetime, timedelta

from sqlalchemy.orm import Session

from app.cell_cache import (
    lookup_cached_cell,
    remember_cell_tower,
    touch_machine_cell,
)
from app.cell_locate import locate_cell
from app.config import settings
from app.geo import apply_machine_gps
from app.live_telemetry import apply_sensor_live
from app.models import (
    Device,
    Event,
    IngestDedup,
    Machine,
    MachineGpsPoint,
    NotificationSettings,
    Organization,
    Reading,
    RefreshToken,
    Sensor,
    User,
)
from app.org_types import ORG_TYPE_CLIENT, ORG_TYPE_MANUFACTURER, ORG_TYPE_PLATFORM
from app.roles import ROLE_ORG_ADMIN
from app.runtime_accumulator import accumulate_runtime
from app.security import (
    create_refresh_token,
    evaluate_status,
    hash_device_key,
    hash_password,
    hash_token,
    headline_for_status,
    verify_password,
    worst_status,
)

# Демо-учётки (development). В production для новых юзеров — случайный пароль.
DEMO_ADMIN_EMAIL = "admin@hydrowin.ru"
DEMO_ADMIN_PASSWORD = "HydroWin2026!"

MAKER_EMAIL = "maker@hydrowin.ru"
MAKER_PASSWORD = "HydroMaker2026!"
CLIENT1_ADMIN_EMAIL = "client1@hydrowin.ru"
CLIENT1_ADMIN_PASSWORD = "Client12026!"
CLIENT2_ADMIN_EMAIL = "client2@hydrowin.ru"
CLIENT2_ADMIN_PASSWORD = "Client22026!"

# Известные plaintext из старых seed — ротируем, если всё ещё стоят в production.
_KNOWN_DEMO_CREDENTIALS: tuple[tuple[str, str], ...] = (
    (DEMO_ADMIN_EMAIL, DEMO_ADMIN_PASSWORD),
    (MAKER_EMAIL, MAKER_PASSWORD),
    (CLIENT1_ADMIN_EMAIL, CLIENT1_ADMIN_PASSWORD),
    (CLIENT2_ADMIN_EMAIL, CLIENT2_ADMIN_PASSWORD),
)


def _demo_password_or_random(default: str) -> str:
    if settings.is_production:
        import secrets

        return secrets.token_urlsafe(18)
    return default


def rotate_known_demo_passwords_if_production(db: Session) -> int:
    """Если в production остались известные demo-пароли — сменить и отозвать refresh.

    Типичный сценарий: учётки создали в development, затем ENVIRONMENT=production.
    _ensure_user не трогает существующих — без этой ротации HydroWin2026! остаётся.
    Возвращает число ротированных учёток.
    """
    if not settings.is_production:
        return 0

    import secrets

    rotated = 0
    for email, known_plain in _KNOWN_DEMO_CREDENTIALS:
        user = db.query(User).filter(User.email == email.lower()).first()
        if user is None:
            continue
        try:
            still_demo = verify_password(known_plain, user.password_hash)
        except Exception:
            still_demo = False
        if not still_demo:
            continue
        new_password = secrets.token_urlsafe(18)
        user.password_hash = hash_password(new_password)
        db.query(RefreshToken).filter(
            RefreshToken.user_id == user.id,
            RefreshToken.revoked.is_(False),
        ).update({"revoked": True})
        rotated += 1
        print(
            f"⚠️  PRODUCTION: ротирован demo-пароль {email} → "
            f"временный (сохраните сейчас): {new_password}"
        )
    if rotated:
        db.commit()
    return rotated

def ensure_platform_org(db: Session) -> Organization:
    """Организация-платформа ГидроВин; admin@ — её админ (видит все машины)."""
    platform = (
        db.query(Organization)
        .filter(Organization.org_type == ORG_TYPE_PLATFORM)
        .order_by(Organization.created_at)
        .first()
    )
    if platform is None:
        # Переиспользуем первую org с admin@, иначе создаём
        admin = db.query(User).filter(User.email == DEMO_ADMIN_EMAIL).first()
        if admin is not None:
            platform = db.get(Organization, admin.organization_id)
        if platform is None:
            platform = Organization(name="ГидроВин (платформа)")
            db.add(platform)
            db.flush()
        platform.name = platform.name or "ГидроВин (платформа)"
        if "карьер" in platform.name.lower() or platform.name == "Демо-карьер ГидроВин":
            platform.name = "ГидроВин (платформа)"
        platform.org_type = ORG_TYPE_PLATFORM
        platform.manufacturer_id = None
        db.flush()
        print(f"✅ Org платформы: {platform.name} ({platform.id})")

    admin = _ensure_user(
        db,
        org_id=platform.id,
        name="Администратор платформы",
        email=DEMO_ADMIN_EMAIL,
        password=_demo_password_or_random(DEMO_ADMIN_PASSWORD),
        role=ROLE_ORG_ADMIN,
    )
    if admin.organization_id != platform.id:
        admin.organization_id = platform.id
        admin.name = "Администратор платформы"
        db.flush()

    db.commit()
    return platform


def _ensure_user(
    db: Session,
    *,
    org_id: str,
    name: str,
    email: str,
    password: str,
    role: str,
) -> User:
    user = db.query(User).filter(User.email == email.lower()).first()
    if user is not None:
        return user
    user = User(
        organization_id=org_id,
        name=name,
        email=email.lower(),
        password_hash=hash_password(password),
        role=role,
    )
    db.add(user)
    db.flush()
    db.add(NotificationSettings(user_id=user.id))
    if settings.is_production:
        print(
            f"✅ Создан пользователь {email} ({role}); "
            f"временный пароль (сохраните сейчас): {password}"
        )
    else:
        print(f"✅ Создан пользователь {email} ({role})")
    return user


def _demo_machine(
    db: Session,
    *,
    org_id: str,
    manufacturer_id: str,
    code: str,
    name: str,
    location: str,
    sold: bool,
) -> Machine:
    existing = (
        db.query(Machine)
        .filter(Machine.code == code, Machine.organization_id == org_id)
        .first()
    )
    if existing is not None:
        existing.manufacturer_id = manufacturer_id
        if sold and existing.sold_at is None:
            existing.sold_at = datetime.utcnow() - timedelta(days=30)
        return existing

    machine = Machine(
        organization_id=org_id,
        manufacturer_id=manufacturer_id,
        code=code,
        name=name,
        model="HydroWin Station",
        status="ok",
        location_label=location,
        operator_name="—",
        last_seen_at=datetime.utcnow() - timedelta(minutes=5),
        sold_at=datetime.utcnow() - timedelta(days=30) if sold else None,
    )
    db.add(machine)
    db.flush()
    for ch, sname, stype in (
        (0, "Давление", "pressure"),
        (1, "Температура", "temperature"),
    ):
        db.add(
            Sensor(
                machine_id=machine.id,
                name=sname,
                type=stype,
                unit="бар" if stype == "pressure" else "°C",
                scale_min=0,
                scale_max=400 if stype == "pressure" else 120,
                norm_min=100 if stype == "pressure" else 40,
                norm_max=250 if stype == "pressure" else 85,
                warn_high=280 if stype == "pressure" else 90,
                critical_high=300 if stype == "pressure" else 95,
                channel_index=ch,
            )
        )
    return machine


def ensure_multi_org_demo(db: Session) -> None:
    """HydroMaker + Client1/Client2 и машины 001/002 vs 010/011."""
    if db.query(User).filter(User.email == MAKER_EMAIL).first() is not None:
        return

    maker = Organization(
        name="HydroMaker",
        org_type=ORG_TYPE_MANUFACTURER,
    )
    db.add(maker)
    db.flush()

    client1 = Organization(
        name="Завод №1 (Client1)",
        org_type=ORG_TYPE_CLIENT,
        manufacturer_id=maker.id,
    )
    client2 = Organization(
        name="Завод №2 (Client2)",
        org_type=ORG_TYPE_CLIENT,
        manufacturer_id=maker.id,
    )
    db.add_all([client1, client2])
    db.flush()

    _ensure_user(
        db,
        org_id=maker.id,
        name="Админ производителя",
        email=MAKER_EMAIL,
        password=_demo_password_or_random(MAKER_PASSWORD),
        role=ROLE_ORG_ADMIN,
    )
    _ensure_user(
        db,
        org_id=client1.id,
        name="Админ завода №1",
        email=CLIENT1_ADMIN_EMAIL,
        password=_demo_password_or_random(CLIENT1_ADMIN_PASSWORD),
        role=ROLE_ORG_ADMIN,
    )
    _ensure_user(
        db,
        org_id=client2.id,
        name="Админ завода №2",
        email=CLIENT2_ADMIN_EMAIL,
        password=_demo_password_or_random(CLIENT2_ADMIN_PASSWORD),
        role=ROLE_ORG_ADMIN,
    )

    sold_at = datetime.utcnow() - timedelta(days=14)
    _demo_machine(
        db,
        org_id=client1.id,
        manufacturer_id=maker.id,
        code="001",
        name="Станция 001",
        location="Цех А",
        sold=True,
    )
    _demo_machine(
        db,
        org_id=client1.id,
        manufacturer_id=maker.id,
        code="002",
        name="Станция 002",
        location="Цех Б",
        sold=True,
    )
    _demo_machine(
        db,
        org_id=client2.id,
        manufacturer_id=maker.id,
        code="010",
        name="Станция 010",
        location="Линия 1",
        sold=True,
    )
    _demo_machine(
        db,
        org_id=client2.id,
        manufacturer_id=maker.id,
        code="011",
        name="Станция 011",
        location="Линия 2",
        sold=True,
    )
    # Склад производителя (ещё не продана)
    _demo_machine(
        db,
        org_id=maker.id,
        manufacturer_id=maker.id,
        code="STOCK-099",
        name="Складская станция 099",
        location="Склад HydroMaker",
        sold=False,
    )

    db.commit()
    print("✅ Multi-org демо: HydroMaker, Client1, Client2 и станции созданы")


def ensure_default_users(db: Session) -> None:
    """Создаёт платформу и администратора, если их ещё нет."""
    ensure_platform_org(db)
    platform = (
        db.query(Organization)
        .filter(Organization.org_type == ORG_TYPE_PLATFORM)
        .first()
    )
    if platform is None:
        return

    _ensure_user(
        db,
        org_id=platform.id,
        name="Администратор платформы",
        email=DEMO_ADMIN_EMAIL,
        password=_demo_password_or_random(DEMO_ADMIN_PASSWORD),
        role=ROLE_ORG_ADMIN,
    )
    db.commit()


def seed_if_empty(db: Session) -> None:
    if db.query(User).first() is not None:
        ensure_default_users(db)
        return

    platform = Organization(
        name="ГидроВин (платформа)",
        org_type=ORG_TYPE_PLATFORM,
    )
    db.add(platform)
    db.flush()

    admin_password = _demo_password_or_random(DEMO_ADMIN_PASSWORD)
    admin = User(
        organization_id=platform.id,
        name="Администратор платформы",
        email=DEMO_ADMIN_EMAIL,
        password_hash=hash_password(admin_password),
        role=ROLE_ORG_ADMIN,
    )
    db.add(admin)
    db.flush()

    db.add(
        NotificationSettings(user_id=admin.id)
    )
    if settings.is_production:
        print(f"⚠️  BOOTSTRAP admin пароль: {admin_password}")

    machines_data = [
        {
            "code": "#001",
            "name": "Экскаватор #001",
            "model": "CAT 320",
            "status": "warning",
            "location_label": "Карьер, смена А",
            "operator_name": "Иванов И.И.",
            "headline_alert": "Давление ГС — предупреждение",
            "engine_hours": 4820.5,
            "sensors": [
                ("Давление ГС", "pressure", "bar", 0, 400, 180, 280, 300, 320, None, 0),
                ("Температура масла", "temperature", "°C", -20, 120, 40, 85, 90, 95, None, 1),
                ("Расход", "flow", "л/мин", 0, 50, 5, 25, 30, 35, 2, 2),
            ],
        },
        {
            "code": "#002",
            "name": "Погрузчик #002",
            "model": "Komatsu WA380",
            "status": "ok",
            "location_label": "Склад №2",
            "operator_name": "Петров П.П.",
            "headline_alert": None,
            "engine_hours": 2100.0,
            "sensors": [
                ("Давление ГС", "pressure", "bar", 0, 350, 160, 260, 280, 300, None, 0),
                ("Температура масла", "temperature", "°C", -20, 120, 40, 85, 90, 95, None, 1),
            ],
        },
        {
            "code": "#003",
            "name": "Самосвал #003",
            "model": "BelAZ 7558",
            "status": "offline",
            "location_label": "Разрез север",
            "operator_name": "—",
            "headline_alert": None,
            "engine_hours": None,
            "sensors": [
                ("Давление ГС", "pressure", "bar", 0, 400, 180, 280, 300, 320, None, 0),
            ],
        },
    ]

    now = datetime.utcnow()
    device_key = settings.default_device_key

    for idx, mdata in enumerate(machines_data):
        machine = Machine(
            organization_id=platform.id,
            code=mdata["code"],
            name=mdata["name"],
            model=mdata["model"],
            status=mdata["status"],
            location_label=mdata["location_label"],
            operator_name=mdata["operator_name"],
            headline_alert=mdata["headline_alert"],
            engine_hours=mdata["engine_hours"],
            last_seen_at=now - timedelta(minutes=2 if idx < 2 else 120),
            gps_lat=55.75 + idx * 0.01 if idx < 2 else None,
            gps_lon=37.62 + idx * 0.01 if idx < 2 else None,
            gps_accuracy_m=12.0 if idx < 2 else None,
            bluetooth_status="connected" if idx == 0 else "disconnected",
        )
        db.add(machine)
        db.flush()

        if idx == 0:
            db.add(
                Device(
                    device_id="HYDRO-001",
                    machine_id=machine.id,
                    api_key_hash=hash_device_key(device_key),
                )
            )

        for s in mdata["sensors"]:
            sensor = Sensor(
                machine_id=machine.id,
                name=s[0],
                type=s[1],
                unit=s[2],
                scale_min=s[3],
                scale_max=s[4],
                norm_min=s[5],
                norm_max=s[6],
                warn_high=s[7],
                critical_high=s[8],
                critical_low=s[9],
                channel_index=s[10],
            )
            db.add(sensor)
            db.flush()

            if idx < 2:
                for hours_ago in range(24, 0, -1):
                    ts = now - timedelta(hours=hours_ago)
                    base = (s[5] + s[6]) / 2
                    value = base + (hours_ago % 5) - 2
                    if idx == 0 and s[1] == "pressure" and hours_ago < 3:
                        value = 305.0
                    status = evaluate_status(value, sensor)
                    db.add(
                        Reading(
                            machine_id=machine.id,
                            sensor_id=sensor.id,
                            ts=ts,
                            value=round(value, 2),
                            status=status,
                        )
                    )

        if mdata["status"] == "warning":
            db.add(
                Event(
                    machine_id=machine.id,
                    type="threshold_warning",
                    severity="warning",
                    message="Давление ГС выше порога предупреждения",
                    ts=now - timedelta(minutes=5),
                )
            )

    db.commit()


def store_refresh_token(db: Session, user_id: str) -> str:
    token = create_refresh_token()
    db.add(
        RefreshToken(
            user_id=user_id,
            token_hash=hash_token(token),
            expires_at=datetime.utcnow() + timedelta(days=settings.jwt_refresh_days),
        )
    )
    db.commit()
    return token


def revoke_refresh_token(db: Session, refresh_token: str) -> None:
    token_hash = hash_token(refresh_token)
    row = db.query(RefreshToken).filter(RefreshToken.token_hash == token_hash).first()
    if row:
        row.revoked = True
        db.commit()


def ingest_telemetry(db: Session, device: Device, payload: dict) -> None:
    message_id = payload["message_id"]
    if db.query(IngestDedup).filter(IngestDedup.message_id == message_id).first():
        return

    machine = db.get(Machine, payload["machine_id"])
    if machine is None or machine.id != device.machine_id:
        raise ValueError("machine mismatch")

    body_device_id = str(payload.get("device_id") or "").strip()
    if body_device_id and body_device_id != device.device_id:
        raise ValueError("device mismatch")

    ts = datetime.fromisoformat(payload["ts"].replace("Z", ""))
    sensors_by_channel = {
        s.channel_index: s for s in db.query(Sensor).filter(Sensor.machine_id == machine.id).all()
    }

    statuses: list[str] = []
    alert_headlines: list[tuple[str, str]] = []
    pressure_value: float | None = None
    temperature_value: float | None = None
    pressure_sensor = None
    temperature_sensor = None
    pressure_ok = True
    new_critical_ids: list[str] = []

    for item in payload["sensors"]:
        channel = item["channel"]
        value = float(item["value"])
        sensor = sensors_by_channel.get(channel)
        if sensor is None:
            continue
        is_pressure = sensor.type == "pressure" or channel == 0
        is_temperature = sensor.type == "temperature" or channel == 1
        if is_pressure:
            pressure_value = value
            pressure_sensor = sensor
        elif is_temperature:
            temperature_value = value
            temperature_sensor = sensor

        fault = (item.get("fault") or "").strip().lower()
        current_ma = item.get("current_ma")
        if current_ma is not None:
            try:
                current_ma = float(current_ma)
            except (TypeError, ValueError):
                current_ma = None
        # Явный ток петли с платы / после expand_industrial.
        if not fault and current_ma is not None:
            if current_ma < 3.2:
                fault = "open"
            elif current_ma > 21.0:
                fault = "short"
        # Старые verbose-пакеты без fault/current_ma: value < 3.2 ≈ ток обрыва.
        # Не применять, если fault уже задан (в т.ч. "" после маски = OK)
        # или есть current_ma — иначе давление 1–3 бар станет «обрывом».
        if (
            not fault
            and current_ma is None
            and "fault" not in item
            and 0 < value < 3.2
        ):
            current_ma = value
            fault = "open"
        ma_txt = (
            f" ({float(current_ma):.1f} мА)"
            if current_ma is not None
            else ""
        )

        def _emit_event(
            event_type: str,
            severity: str,
            msg: str,
            *,
            notify: bool,
            _sensor=sensor,
        ) -> None:
            """warning → только журнал; critical → журнал + оповещение."""
            alert_headlines.append((severity, msg))
            recent = (
                db.query(Event)
                .filter(
                    Event.machine_id == machine.id,
                    Event.sensor_id == _sensor.id,
                    Event.type == event_type,
                    Event.ts >= ts - timedelta(minutes=5),
                )
                .first()
            )
            if recent is not None:
                return
            row = Event(
                machine_id=machine.id,
                sensor_id=_sensor.id,
                type=event_type,
                severity=severity,
                message=msg,
                ts=ts,
                # Мелкие скачки только записываем — без «активных» уведомлений.
                acknowledged=(severity != "critical"),
            )
            db.add(row)
            db.flush()
            if notify and severity == "critical":
                new_critical_ids.append(row.id)

        if fault == "open":
            status = "critical"
            # Не использовать 0 как «рабочее» давление/температуру.
            if is_pressure:
                pressure_value = None
                pressure_ok = False
            if is_temperature:
                temperature_value = None
            _emit_event(
                "loop_open",
                "critical",
                f"{sensor.name}: обрыв линии или датчик неисправен{ma_txt}",
                notify=True,
            )
        elif fault == "short":
            status = "critical"
            if is_pressure:
                pressure_value = None
                pressure_ok = False
            if is_temperature:
                temperature_value = None
            _emit_event(
                "loop_short",
                "critical",
                f"{sensor.name}: короткое замыкание петли 4–20 мА{ma_txt}",
                notify=True,
            )
        else:
            status = evaluate_status(value, sensor)
            if status == "critical":
                _emit_event(
                    "threshold_critical",
                    "critical",
                    f"{sensor.name}: критическое значение {value} {sensor.unit}{ma_txt}",
                    notify=True,
                )
            elif status == "warning":
                _emit_event(
                    "threshold_warning",
                    "warning",
                    f"{sensor.name}: предупреждение {value} {sensor.unit}{ma_txt}",
                    notify=False,
                )

        statuses.append(status)
        db.add(
            Reading(
                machine_id=machine.id,
                sensor_id=sensor.id,
                ts=ts,
                value=value,
                status=status,
            )
        )
        apply_sensor_live(
            sensor,
            value=value,
            ts=ts,
            status=status,
            fault=fault or None,
            current_ma=current_ma,
        )

    accumulate_runtime(
        machine,
        ts,
        pressure=pressure_value,
        temperature=temperature_value,
        pressure_ok=pressure_ok,
        pressure_sensor=pressure_sensor,
        temperature_sensor=temperature_sensor,
    )
    machine.status = worst_status(statuses) if statuses else "ok"
    machine.last_seen_at = ts
    machine.headline_alert = headline_for_status(machine.status, alert_headlines)
    gps = payload.get("gps") if isinstance(payload.get("gps"), dict) else None
    cell = payload.get("cell") if isinstance(payload.get("cell"), dict) else None
    if cell:
        touch_machine_cell(machine, cell)
    gps_lat = gps.get("lat") if gps else None
    gps_lon = gps.get("lon") if gps else None
    gps_acc = None
    if gps is not None and gps.get("accuracy_m") is not None:
        try:
            gps_acc = float(gps["accuracy_m"])
        except (TypeError, ValueError):
            gps_acc = None
    # LBS модема (часто acc сотни метров) путает карту — берём соту.
    gps_is_gnss = (
        gps_lat is not None
        and gps_lon is not None
        and (gps_acc is None or gps_acc < 200.0)
    )
    if gps_is_gnss:
        new_critical_ids.extend(
            apply_machine_gps(
                db,
                machine,
                lat=float(gps_lat),
                lon=float(gps_lon),
                accuracy_m=gps_acc,
                ts=ts,
                source="ingest",
            )
        )
        if cell:
            remember_cell_tower(
                db,
                cell,
                lat=float(gps_lat),
                lon=float(gps_lon),
                accuracy_m=gps_acc,
                source="gnss",
            )
    elif cell:
        if gps_acc is not None and gps_acc >= 200.0:
            print(
                f"GPS пропуск: грубая точка acc={gps_acc:.0f} м, пробуем соту"
            )
        located = lookup_cached_cell(db, cell) or locate_cell(cell)
        if located:
            new_critical_ids.extend(
                apply_machine_gps(
                    db,
                    machine,
                    lat=float(located["lat"]),
                    lon=float(located["lon"]),
                    accuracy_m=float(located["accuracy_m"]),
                    ts=ts,
                    source="cell",
                )
            )

    db.add(IngestDedup(message_id=message_id))
    if new_critical_ids:
        from app.alert_dispatch import dispatch_new_critical_events

        dispatch_new_critical_events(db, new_critical_ids)
    db.commit()
