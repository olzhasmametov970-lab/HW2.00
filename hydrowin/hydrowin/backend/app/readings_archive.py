"""Двухуровневое хранение телеметрии.

Сырые readings → readings_retention_days (по умолчанию 30).
Агрегаты hourly/daily → readings_archive_days (по умолчанию 180 = полгода).

Перед удалением сырых — сворачиваем в readings_hourly / readings_daily.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

from sqlalchemy import case, func, text
from sqlalchemy.orm import Session

from app.config import settings
from app.models import Reading, ReadingDaily, ReadingHourly
from app.time_bucket import bucket_1min, bucket_5min, bucket_day, bucket_hour


_SEVERITY = case(
    (Reading.status == "critical", 2),
    (Reading.status == "warning", 1),
    else_=0,
)
_SEVERITY_HOURLY = case(
    (ReadingHourly.status == "critical", 2),
    (ReadingHourly.status == "warning", 1),
    else_=0,
)
_STATUS_FROM_RANK = {0: "ok", 1: "warning", 2: "critical"}


def as_naive_utc(dt: datetime) -> datetime:
    """Сравнения с datetime.utcnow() падают, если пришёл tz-aware ISO."""
    if dt.tzinfo is None:
        return dt
    return dt.astimezone(timezone.utc).replace(tzinfo=None)


def parse_api_datetime(value: str) -> datetime:
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    return as_naive_utc(datetime.fromisoformat(text))


def _iso_z(dt: Any) -> str | None:
    if dt is None:
        return None
    if isinstance(dt, (int, float)):
        dt = datetime.utcfromtimestamp(float(dt))
    elif not isinstance(dt, datetime):
        return None
    if dt.tzinfo is not None:
        dt = dt.astimezone(timezone.utc).replace(tzinfo=None)
    return dt.strftime("%Y-%m-%dT%H:%M:%S") + "Z"


def archive_horizon_days() -> int:
    return max(1, int(settings.readings_archive_days))


def raw_horizon_days() -> int:
    return max(1, int(settings.readings_retention_days))


def clamp_history_window(
    dt_from: datetime, dt_to: datetime
) -> tuple[datetime, datetime, bool]:
    """Ограничить окно максимумом archive_days. Возвращает (from, to, clamped)."""
    dt_from = as_naive_utc(dt_from)
    dt_to = as_naive_utc(dt_to)
    now = datetime.utcnow()
    if dt_to > now:
        dt_to = now
    oldest = now - timedelta(days=archive_horizon_days())
    clamped = False
    if dt_from < oldest:
        dt_from = oldest
        clamped = True
    if dt_from > dt_to:
        dt_from = dt_to
        clamped = True
    return dt_from, dt_to, clamped


def _purge_epoch_junk(db: Session) -> int:
    """Убрать битые ts (эпоха 1970 и т.п.) — в архив не сворачиваем."""
    deleted = db.execute(
        text("DELETE FROM readings WHERE ts < :cut"),
        {"cut": datetime(2020, 1, 1)},
    )
    db.commit()
    return int(deleted.rowcount or 0)


def rollup_raw_to_hourly(db: Session, *, until: datetime | None = None) -> int:
    """Свернуть сырые readings в часовые бакеты (закрытые часы), по суткам.

    Чанки нужны при миллионах строк: один огромный GROUP BY часто
    таймаутится / уходит в ORM-fallback и зависает.
    """
    until = until or (datetime.utcnow().replace(minute=0, second=0, microsecond=0))
    _purge_epoch_junk(db)

    oldest_keep = until - timedelta(days=archive_horizon_days())
    row = db.execute(
        text("SELECT min(ts) FROM readings WHERE ts >= :lo AND ts < :until"),
        {"lo": oldest_keep, "until": until},
    ).first()
    if not row or row[0] is None:
        return 0

    cursor = row[0].replace(hour=0, minute=0, second=0, microsecond=0)
    upserted = 0
    sql = text(
        """
        INSERT INTO readings_hourly (
            id, machine_id, sensor_id, period,
            avg_value, min_value, max_value, samples, status
        )
        SELECT
            gen_random_uuid()::text,
            machine_id,
            sensor_id,
            date_trunc('hour', ts) AS period,
            avg(value),
            min(value),
            max(value),
            count(*)::int,
            CASE
                WHEN bool_or(status = 'critical') THEN 'critical'
                WHEN bool_or(status = 'warning') THEN 'warning'
                ELSE 'ok'
            END
        FROM readings
        WHERE ts >= :day_from AND ts < :day_to AND ts < :until
        GROUP BY machine_id, sensor_id, date_trunc('hour', ts)
        ON CONFLICT (sensor_id, period) DO UPDATE SET
            avg_value = EXCLUDED.avg_value,
            min_value = EXCLUDED.min_value,
            max_value = EXCLUDED.max_value,
            samples = EXCLUDED.samples,
            status = EXCLUDED.status
        """
    )
    while cursor < until:
        day_to = min(cursor + timedelta(days=1), until)
        try:
            result = db.execute(
                sql,
                {"day_from": cursor, "day_to": day_to, "until": until},
            )
            db.commit()
            upserted += int(result.rowcount or 0)
        except Exception:
            db.rollback()
            upserted += _rollup_raw_to_hourly_orm_range(
                db, day_from=cursor, day_to=day_to, until=until
            )
        cursor = day_to
    return upserted


def _rollup_raw_to_hourly_orm_range(
    db: Session,
    *,
    day_from: datetime,
    day_to: datetime,
    until: datetime,
) -> int:
    period = func.date_trunc("hour", Reading.ts).label("period")
    rows = (
        db.query(
            Reading.machine_id,
            Reading.sensor_id,
            period,
            func.avg(Reading.value).label("avg_value"),
            func.min(Reading.value).label("min_value"),
            func.max(Reading.value).label("max_value"),
            func.count().label("samples"),
            func.max(_SEVERITY).label("severity"),
        )
        .filter(
            Reading.ts >= day_from,
            Reading.ts < day_to,
            Reading.ts < until,
        )
        .group_by(Reading.machine_id, Reading.sensor_id, period)
        .all()
    )
    upserted = 0
    for row in rows:
        existing = (
            db.query(ReadingHourly)
            .filter(
                ReadingHourly.sensor_id == row.sensor_id,
                ReadingHourly.period == row.period,
            )
            .first()
        )
        status = _STATUS_FROM_RANK.get(int(row.severity or 0), "ok")
        if existing is None:
            db.add(
                ReadingHourly(
                    id=str(uuid.uuid4()),
                    machine_id=row.machine_id,
                    sensor_id=row.sensor_id,
                    period=row.period,
                    avg_value=float(row.avg_value),
                    min_value=float(row.min_value),
                    max_value=float(row.max_value),
                    samples=int(row.samples or 0),
                    status=status,
                )
            )
        else:
            existing.avg_value = float(row.avg_value)
            existing.min_value = float(row.min_value)
            existing.max_value = float(row.max_value)
            existing.samples = int(row.samples or 0)
            existing.status = status
        upserted += 1
    db.commit()
    return upserted


def rollup_hourly_to_daily(db: Session, *, until: datetime | None = None) -> int:
    """Свернуть часовые в суточные (закрытые дни)."""
    until = until or datetime.utcnow().replace(
        hour=0, minute=0, second=0, microsecond=0
    )
    period = func.date_trunc("day", ReadingHourly.period).label("period")
    rows = (
        db.query(
            ReadingHourly.machine_id,
            ReadingHourly.sensor_id,
            period,
            func.avg(ReadingHourly.avg_value).label("avg_value"),
            func.min(ReadingHourly.min_value).label("min_value"),
            func.max(ReadingHourly.max_value).label("max_value"),
            func.sum(ReadingHourly.samples).label("samples"),
            func.max(_SEVERITY_HOURLY).label("severity"),
        )
        .filter(ReadingHourly.period < until)
        .group_by(ReadingHourly.machine_id, ReadingHourly.sensor_id, period)
        .all()
    )
    upserted = 0
    for row in rows:
        existing = (
            db.query(ReadingDaily)
            .filter(
                ReadingDaily.sensor_id == row.sensor_id,
                ReadingDaily.period == row.period,
            )
            .first()
        )
        status = _STATUS_FROM_RANK.get(int(row.severity or 0), "ok")
        if existing is None:
            db.add(
                ReadingDaily(
                    id=str(uuid.uuid4()),
                    machine_id=row.machine_id,
                    sensor_id=row.sensor_id,
                    period=row.period,
                    avg_value=float(row.avg_value),
                    min_value=float(row.min_value),
                    max_value=float(row.max_value),
                    samples=int(row.samples or 0),
                    status=status,
                )
            )
        else:
            existing.avg_value = float(row.avg_value)
            existing.min_value = float(row.min_value)
            existing.max_value = float(row.max_value)
            existing.samples = int(row.samples or 0)
            existing.status = status
        upserted += 1
    db.commit()
    return upserted


def purge_raw_readings(db: Session) -> int:
    cutoff = datetime.utcnow() - timedelta(days=raw_horizon_days())
    deleted = (
        db.query(Reading)
        .filter(Reading.ts < cutoff)
        .delete(synchronize_session=False)
    )
    db.commit()
    return int(deleted or 0)


def purge_archive(db: Session) -> dict[str, int]:
    cutoff = datetime.utcnow() - timedelta(days=archive_horizon_days())
    h = (
        db.query(ReadingHourly)
        .filter(ReadingHourly.period < cutoff)
        .delete(synchronize_session=False)
    )
    d = (
        db.query(ReadingDaily)
        .filter(ReadingDaily.period < cutoff)
        .delete(synchronize_session=False)
    )
    db.commit()
    return {"hourly": int(h or 0), "daily": int(d or 0)}


def maintain_readings_storage(db: Session) -> dict[str, Any]:
    """Полный цикл: rollup → purge raw → purge archive older than 6 months."""
    hourly = rollup_raw_to_hourly(db)
    daily = rollup_hourly_to_daily(db)
    raw_deleted = purge_raw_readings(db)
    archive_deleted = purge_archive(db)
    return {
        "hourly_upserted": hourly,
        "daily_upserted": daily,
        "raw_deleted": raw_deleted,
        "archive_deleted": archive_deleted,
        "raw_retention_days": raw_horizon_days(),
        "archive_retention_days": archive_horizon_days(),
    }


def _points_from_raw(
    db: Session,
    *,
    machine_id: str,
    sensor_id: str,
    dt_from: datetime,
    dt_to: datetime,
    span_minutes: int,
) -> list[dict[str, Any]]:
    if span_minutes <= 60:
        rows = (
            db.query(Reading)
            .filter(
                Reading.machine_id == machine_id,
                Reading.sensor_id == sensor_id,
                Reading.ts.isnot(None),
                Reading.ts >= dt_from,
                Reading.ts <= dt_to,
            )
            .order_by(Reading.ts)
            .all()
        )
        return [
            {
                "ts": _iso_z(r.ts),
                "value": r.value,
                "status": r.status or "ok",
            }
            for r in rows
            if r.ts is not None
        ]

    if span_minutes <= 1440:
        time_bucket = bucket_1min(Reading.ts)
    elif span_minutes <= 10080:
        time_bucket = bucket_hour(Reading.ts)
    else:
        time_bucket = bucket_day(Reading.ts)

    aggregated = (
        db.query(
            func.avg(Reading.value).label("avg_value"),
            func.max(_SEVERITY).label("severity"),
            time_bucket,
        )
        .filter(
            Reading.machine_id == machine_id,
            Reading.sensor_id == sensor_id,
            Reading.ts.isnot(None),
            Reading.ts >= dt_from,
            Reading.ts <= dt_to,
        )
        .group_by(time_bucket)
        .order_by(time_bucket)
        .all()
    )
    return [
        {
            "ts": _iso_z(row.period),
            "value": round(float(row.avg_value), 2),
            "status": _STATUS_FROM_RANK.get(int(row.severity or 0), "ok"),
        }
        for row in aggregated
        if row.period is not None and row.avg_value is not None
    ]


def _points_from_hourly(
    db: Session,
    *,
    machine_id: str,
    sensor_id: str,
    dt_from: datetime,
    dt_to: datetime,
) -> list[dict[str, Any]]:
    rows = (
        db.query(ReadingHourly)
        .filter(
            ReadingHourly.machine_id == machine_id,
            ReadingHourly.sensor_id == sensor_id,
            ReadingHourly.period >= dt_from,
            ReadingHourly.period <= dt_to,
        )
        .order_by(ReadingHourly.period)
        .all()
    )
    return [
        {
            "ts": _iso_z(r.period),
            "value": round(float(r.avg_value), 2),
            "status": r.status or "ok",
        }
        for r in rows
        if r.period is not None and r.avg_value is not None
    ]


def _points_from_daily(
    db: Session,
    *,
    machine_id: str,
    sensor_id: str,
    dt_from: datetime,
    dt_to: datetime,
) -> list[dict[str, Any]]:
    rows = (
        db.query(ReadingDaily)
        .filter(
            ReadingDaily.machine_id == machine_id,
            ReadingDaily.sensor_id == sensor_id,
            ReadingDaily.period >= dt_from,
            ReadingDaily.period <= dt_to,
        )
        .order_by(ReadingDaily.period)
        .all()
    )
    return [
        {
            "ts": _iso_z(r.period),
            "value": round(float(r.avg_value), 2),
            "status": r.status or "ok",
        }
        for r in rows
        if r.period is not None and r.avg_value is not None
    ]


def query_history_points(
    db: Session,
    *,
    machine_id: str,
    sensor_id: str,
    dt_from: datetime,
    dt_to: datetime,
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    """Точки для графика/экспорта с учётом raw + archive (макс. полгода)."""
    dt_from, dt_to, clamped = clamp_history_window(dt_from, dt_to)
    span_minutes = max(1, int((dt_to - dt_from).total_seconds() / 60))
    raw_cut = datetime.utcnow() - timedelta(days=raw_horizon_days())

    meta = {
        "clamped_to_archive_days": clamped,
        "archive_days": archive_horizon_days(),
        "raw_days": raw_horizon_days(),
        "source": "raw",
    }

    # Полностью в зоне сырых данных.
    if dt_from >= raw_cut:
        meta["source"] = "raw"
        return (
            _points_from_raw(
                db,
                machine_id=machine_id,
                sensor_id=sensor_id,
                dt_from=dt_from,
                dt_to=dt_to,
                span_minutes=span_minutes,
            ),
            meta,
        )

    # Полностью в архиве (старше raw).
    if dt_to < raw_cut:
        if span_minutes <= 45 * 24 * 60:  # до ~45 дней — часы
            meta["source"] = "hourly"
            return (
                _points_from_hourly(
                    db,
                    machine_id=machine_id,
                    sensor_id=sensor_id,
                    dt_from=dt_from,
                    dt_to=dt_to,
                ),
                meta,
            )
        meta["source"] = "daily"
        return (
            _points_from_daily(
                db,
                machine_id=machine_id,
                sensor_id=sensor_id,
                dt_from=dt_from,
                dt_to=dt_to,
            ),
            meta,
        )

    # Смешанное окно: архив + сырые.
    archive_points = _points_from_hourly(
        db,
        machine_id=machine_id,
        sensor_id=sensor_id,
        dt_from=dt_from,
        dt_to=raw_cut,
    )
    raw_span = max(1, int((dt_to - raw_cut).total_seconds() / 60))
    raw_points = _points_from_raw(
        db,
        machine_id=machine_id,
        sensor_id=sensor_id,
        dt_from=raw_cut,
        dt_to=dt_to,
        span_minutes=raw_span,
    )
    meta["source"] = "hourly+raw"
    # Склеить по времени, без дублей на стыке.
    merged = {p["ts"]: p for p in archive_points}
    for p in raw_points:
        merged[p["ts"]] = p
    points = [merged[k] for k in sorted(merged.keys())]
    return points, meta
