"""
HydroWin backend — FastAPI entrypoint.

Lifespan: schema/indexes, seed, MQTT (optional), readings purge.
Telemetry: HTTPS POST /v1/ingest/telemetry (X-Device-Key).
"""

import asyncio
import contextlib
import os
from datetime import datetime, timedelta
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import case, desc, func
from sqlalchemy.exc import IntegrityError, OperationalError
from sqlalchemy.orm import Session

from app.time_bucket import bucket_for_span_minutes

from app.config import settings
from app.database import SessionLocal, engine, get_db
from app.db_indexes import apply_performance_indexes
from app.deps import require_admin, require_staff
from app.models import Base, Device, Machine, Reading, ReadingDaily, ReadingHourly, Sensor, User
from app.org_access import can_view_machine, can_write_machine
from app.routers import (
    audit,
    auth,
    events,
    geofences,
    ingest,
    machines,
    media,
    notifications,
    organizations,
)
from app.schema_migrate import apply_org_schema
from app.mqtt_worker import start_mqtt_worker, stop_mqtt_worker
from app.ops_metrics import ingest_metrics_snapshot, system_metrics_snapshot
from app.security import hash_device_key
from app.security_middleware import SecurityHeadersMiddleware
from app.seed import (
    ensure_default_users,
    ensure_multi_org_demo,
    ensure_platform_org,
    rotate_known_demo_passwords_if_production,
)
from app.sensor_service import (
    dedupe_sensors_for_machine,
    ensure_BLOCK_machine,
    ensure_machine_sensors,
)

MACHINE_CODE = os.environ.get("MACHINE_CODE", "1783422691603")


async def _readings_purge_loop() -> None:
    interval = max(1, settings.readings_purge_interval_hours) * 3600
    while True:
        await asyncio.sleep(interval)
        db = SessionLocal()
        try:
            from app.readings_archive import maintain_readings_storage

            stats = maintain_readings_storage(db)
            print(
                "Readings archive: "
                f"hourly+={stats.get('hourly_upserted')} "
                f"daily+={stats.get('daily_upserted')} "
                f"raw_del={stats.get('raw_deleted')} "
                f"arch_del={stats.get('archive_deleted')} "
                f"(raw {settings.readings_retention_days}d / "
                f"archive {settings.readings_archive_days}d)"
            )
        except Exception as exc:
            print(f"Readings purge error: {exc}")
        finally:
            db.close()


@asynccontextmanager
async def lifespan(app: FastAPI):
    purge_task: asyncio.Task | None = None
    settings.assert_secure_secrets()
    print("Синхронизация таблиц с PostgreSQL...")
    try:
        Base.metadata.create_all(bind=engine)
    except (IntegrityError, OperationalError) as ddl_err:
        print(f"⚠️  create_all (уже есть / гонка): {ddl_err.orig}")
    try:
        org_cols = apply_org_schema(engine)
        print(f"Схема multi-org: {org_cols}")
    except Exception as org_err:
        print(f"⚠️  Схема multi-org (частично): {org_err}")
    try:
        applied = apply_performance_indexes(engine)
        print(f"Индексы БД: {applied}")
    except Exception as idx_err:
        print(f"⚠️  Индексы (частично): {idx_err}")
    print("База данных готова!")

    db = SessionLocal()
    try:
        ensure_platform_org(db)
        if not settings.is_production:
            ensure_multi_org_demo(db)
        ensure_default_users(db)
        rotate_known_demo_passwords_if_production(db)

        if settings.is_production:
            print("====== PRODUCTION: демо-машины не создаются ======")
            machine = None
            sensors = []
            merged = []
        else:
            machine = ensure_BLOCK_machine(db)
            merged = dedupe_sensors_for_machine(db, machine.id)
            sensors = ensure_machine_sensors(db, machine)
        db.commit()

        if machine is not None:
            print("====== ДАТЧИКИ СИНХРОНИЗИРОВАНЫ (lab) ======")
            print(f"   Машина: {machine.id} / {machine.code} / {machine.location_label}")
            for s in sensors:
                print(f"   ch{s.channel_index}: {s.id} ({s.name}, {s.type})")
            if merged:
                print(f"   Объединены дубли: {merged}")
        else:
            print("====== ДАТЧИКИ: пропуск (production) ======")

        print("   Ingest: HTTPS POST /v1/ingest/telemetry + X-Device-Key")
        await start_mqtt_worker()

        purge_task = asyncio.create_task(_readings_purge_loop())
        print(
            f"   Readings purge: каждые {settings.readings_purge_interval_hours} ч, "
            f"хранить raw {settings.readings_retention_days} дн. / "
            f"архив {settings.readings_archive_days} дн."
        )

    except Exception as e:
        db.rollback()
        print(f"❌ Ошибка инициализации в lifespan: {e}")
        raise
    finally:
        db.close()

    yield
    if purge_task is not None:
        purge_task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await purge_task
    await stop_mqtt_worker()
    print("Приложение останавливается...")


# Инициализируем FastAPI ОДИН РАЗ, передавая lifespan конфигурацию
_docs = None if settings.is_production else "/docs"
_redoc = None if settings.is_production else "/redoc"
app = FastAPI(
    title="Hydrowin API",
    lifespan=lifespan,
    docs_url=_docs,
    redoc_url=_redoc,
    openapi_url=None if settings.is_production else "/openapi.json",
)

# Middleware: security headers; CORS без *+credentials.
_cors = settings.cors_origin_list
if "*" in _cors:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=False,
        allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "Accept", "X-Device-Key"],
    )
elif _cors:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=_cors,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "Accept", "X-Device-Key"],
    )
app.add_middleware(SecurityHeadersMiddleware)

# Подключаем роутеры
app.include_router(auth.router, prefix="/v1")
app.include_router(machines.router, prefix="/v1")
app.include_router(organizations.router, prefix="/v1")
app.include_router(ingest.router, prefix="/v1")
app.include_router(events.router, prefix="/v1")
app.include_router(audit.router, prefix="/v1")
app.include_router(notifications.router, prefix="/v1")
app.include_router(geofences.router, prefix="/v1")
app.include_router(media.router, prefix="/v1")


# =============================================================================
# Эндпойнты приложения
# =============================================================================

@app.get("/v1/sensors/{sensor_id}/readings")
async def get_sensor_readings(
    sensor_id: str,
    minutes: int = Query(default=10, ge=1, le=60 * 24 * 90),
    user: User = Depends(require_staff),
):
    db = SessionLocal()
    try:
        sensor = db.query(Sensor).filter(Sensor.id == sensor_id).first()
        if sensor is None:
            return {"sensor_id": sensor_id, "unit": "ед.", "points": []}
        machine = db.get(Machine, sensor.machine_id)
        if machine is None or not can_view_machine(db, user, machine):
            raise HTTPException(
                status_code=404,
                detail={"code": "not_found", "message": "Датчик не найден"},
            )
        unit = sensor.unit if sensor else "ед."

        time_threshold = datetime.utcnow() - timedelta(minutes=minutes)

        # ПРИМЕЧАНИЕ: фильтр Reading.status == "ok" был убран — он "выбрасывал"
        # warning/critical показания из ответа, из-за чего статистика
        # (мин/макс/среднее/% в норме/% warning/% critical) на клиенте
        # считалась некорректно (критичные скачки были не видны).
        if minutes <= 60:
            readings = (
                db.query(Reading)
                .filter(
                    Reading.sensor_id == sensor_id,
                    Reading.ts >= time_threshold,
                )
                .order_by(Reading.ts.asc())
                .all()
            )
            points = [
                {
                    "value": float(r.value),
                    "status": r.status or "ok",
                    "ts": r.ts.isoformat() + "Z",
                }
                for r in readings
            ]
            
        else:
            time_bucket = bucket_for_span_minutes(Reading.ts, minutes)

            severity_rank = case(
                (Reading.status == "critical", 2),
                (Reading.status == "warning", 1),
                else_=0,
            )

            aggregated_query = (
                db.query(
                    func.avg(Reading.value).label("avg_value"),
                    func.max(severity_rank).label("severity"),
                    time_bucket,
                )
                .filter(
                    Reading.sensor_id == sensor_id,
                    Reading.ts >= time_threshold,
                )
                .group_by(time_bucket)
                .order_by(time_bucket.asc())
                .all()
            )

            severity_to_status = {0: "ok", 1: "warning", 2: "critical"}
            points = [
                {
                    "value": round(float(row.avg_value), 2),
                    "status": severity_to_status.get(int(row.severity or 0), "ok"),
                    "ts": row.period.isoformat() + "Z",
                }
                for row in aggregated_query
            ]

        return {"sensor_id": sensor_id, "unit": unit, "points": points}

    except HTTPException:
        raise
    except Exception as e:
        print(f"Ошибка получения данных из Postgres: {type(e).__name__}")
        return {"sensor_id": sensor_id, "points": []}
    finally:
        db.close()


@app.get("/v1/admin/metrics")
async def admin_metrics(user: User = Depends(require_admin)):
    """Мониторинг: ingest latency, размер readings, CPU/load."""
    db = SessionLocal()
    try:
        total_readings = db.query(Reading).count()
        total_hourly = db.query(ReadingHourly).count()
        total_daily = db.query(ReadingDaily).count()
        total_sensors = db.query(Sensor).count()
        total_machines = db.query(Machine).count()
        oldest = db.query(func.min(Reading.ts)).scalar()
        newest = db.query(func.max(Reading.ts)).scalar()
        return {
            "database": {
                "readings_total": total_readings,
                "readings_hourly_total": total_hourly,
                "readings_daily_total": total_daily,
                "sensors_total": total_sensors,
                "machines_total": total_machines,
                "readings_oldest_ts": oldest.isoformat() + "Z" if oldest else None,
                "readings_newest_ts": newest.isoformat() + "Z" if newest else None,
                "retention_days": settings.readings_retention_days,
                "archive_days": settings.readings_archive_days,
            },
            "ingest": ingest_metrics_snapshot(),
            "system": system_metrics_snapshot(),
            "uvicorn_workers": settings.uvicorn_workers,
            "db_pool_size": settings.db_pool_size,
        }
    finally:
        db.close()


@app.get("/v1/admin/stats")
async def admin_stats(user: User = Depends(require_admin)):
    """Быстрая диагностика: сколько записей, датчики, последние показания."""
    db = SessionLocal()
    try:
        total_readings   = db.query(Reading).count()
        total_sensors    = db.query(Sensor).count()
        orphan_sensors   = db.query(Sensor).filter(Sensor.channel_index == 99).count()
        orphan_readings  = (
            db.query(Reading)
            .join(Sensor, Reading.sensor_id == Sensor.id)
            .filter(Sensor.channel_index == 99)
            .count()
        )

        last_readings = {}
        machine = db.query(Machine).filter(Machine.code == MACHINE_CODE).first()
        if machine:
            for ch in (0, 1):
                sensor = (
                    db.query(Sensor)
                    .filter(Sensor.machine_id == machine.id, Sensor.channel_index == ch)
                    .first()
                )
                if not sensor:
                    last_readings[f"ch{ch}"] = {"sensor_id": None, "value": None, "ts": None}
                    continue
                r = (
                    db.query(Reading)
                    .filter(Reading.sensor_id == sensor.id)
                    .order_by(desc(Reading.ts))
                    .first()
                )
                count = db.query(Reading).filter(Reading.sensor_id == sensor.id).count()
                last_readings[f"ch{ch}"] = {
                    "sensor_id": sensor.id,
                    "name": sensor.name,
                    "readings_count": count,
                    "value": float(r.value) if r else None,
                    "ts": r.ts.isoformat() + "Z" if r else None,
                }

        return {
            "total_readings":  total_readings,
            "total_sensors":   total_sensors,
            "orphan_sensors":  orphan_sensors,
            "orphan_readings": orphan_readings,
            "last_readings":   last_readings,
        }
    finally:
        db.close()


@app.delete("/v1/admin/fix-orphan-readings")
async def fix_orphan_readings(user: User = Depends(require_admin)):
    """Удаляет все Reading-записи, привязанные к датчикам с channel_index=99."""
    db = SessionLocal()
    try:
        orphan_sensor_ids = [
            r[0] for r in
            db.query(Sensor.id).filter(Sensor.channel_index == 99).all()
        ]
        if not orphan_sensor_ids:
            return {"deleted_readings": 0, "deleted_sensors": 0, "message": "Мусорных записей нет"}

        deleted_readings = (
            db.query(Reading)
            .filter(Reading.sensor_id.in_(orphan_sensor_ids))
            .delete(synchronize_session=False)
        )
        deleted_sensors = (
            db.query(Sensor)
            .filter(Sensor.channel_index == 99)
            .delete(synchronize_session=False)
        )
        db.commit()

        return {
            "deleted_readings": deleted_readings,
            "deleted_sensors":  deleted_sensors,
            "message":          "Очистка завершена",
        }
    except Exception as e:
        db.rollback()
        print(f"fix-orphan-readings error: {type(e).__name__}: {e}")
        raise HTTPException(
            status_code=500,
            detail={
                "code": "internal",
                "message": "Ошибка очистки orphan readings",
            },
        ) from e
    finally:
        db.close()


@app.post("/v1/admin/ensure-device")
@app.get("/v1/admin/ensure-device")
async def ensure_device(
    machine_id: str = Query(...),
    user: User = Depends(require_admin),
):
    """Привязывает DEFAULT_DEVICE_KEY к машине (только lab/development)."""
    if settings.is_production:
        raise HTTPException(
            status_code=403,
            detail={
                "code": "forbidden",
                "message": "ensure-device отключён в production — создавайте ключ через /devices",
            },
        )
    db = SessionLocal()
    try:
        machine = db.get(Machine, machine_id)
        if machine is None or not can_write_machine(db, user, machine):
            return {"error": "Машина не найдена или нет прав", "machine_id": machine_id}

        key_hash = hash_device_key(settings.default_device_key)
        device = db.query(Device).filter(Device.api_key_hash == key_hash).first()
        if device is None:
            device = Device(
                device_id="HYDRO-001",
                machine_id=machine.id,
                api_key_hash=key_hash,
            )
            db.add(device)
        else:
            device.machine_id = machine.id

        db.commit()
        return {
            "device_id": device.device_id,
            "machine_id": device.machine_id,
            "machine_code": machine.code,
            "use_header": "X-Device-Key",
            "key_configured": True,
        }
    finally:
        db.close()


@app.post("/v1/admin/fix-sensors")
@app.get("/v1/admin/fix-sensors")
async def fix_sensors(user: User = Depends(require_admin)):
    """Объединяет дубли датчиков и пересоздаёт каналы 0/1 для BLOCK-машины."""
    db = SessionLocal()
    try:
        machine = db.query(Machine).filter(Machine.code == MACHINE_CODE).first()
        if not machine:
            return {"error": "Машина не найдена"}

        merged = dedupe_sensors_for_machine(db, machine.id)
        sensors = ensure_machine_sensors(db, machine)
        db.commit()
        return {
            "fixed": merged or ["Дублей не было"],
            "sensors": [
                {"id": s.id, "channel_index": s.channel_index, "name": s.name, "type": s.type}
                for s in sensors
            ],
        }
    finally:
        db.close()


# =============================================================================
# Заглушки (оставлены для совместимости)
# =============================================================================
@app.get("/v1/health")
@app.get("/health")
async def health():
    return {"status": "ok"}