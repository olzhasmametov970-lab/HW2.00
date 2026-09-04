"""GPS-трек, геозоны и проверка выхода техники за регион."""

from __future__ import annotations

import math
from datetime import datetime, timedelta

from sqlalchemy.orm import Session

from app.models import Event, Machine, MachineGeofence, MachineGpsPoint

EARTH_R_M = 6_371_000.0
# Не чаще одной точки трека / не спамить алерты
TRACK_MIN_INTERVAL_S = 20
TRACK_MIN_MOVE_M = 15.0
GEOFENCE_ALERT_COOLDOWN = timedelta(minutes=5)
GEOFENCE_MIN_BUFFER_M = 50.0
# «Null Island» и прочий мусор до фикса GPS
GPS_NULL_EPS = 0.05
# Не рисуем/не пишем скачок >500 км между соседними точками трека
TRACK_MAX_JUMP_M = 500_000.0


def is_valid_gps_coordinate(lat: float, lon: float) -> bool:
    if lat < -90 or lat > 90 or lon < -180 or lon > 180:
        return False
    if abs(lat) < GPS_NULL_EPS and abs(lon) < GPS_NULL_EPS:
        return False
    return True


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlmb = math.radians(lon2 - lon1)
    a = (
        math.sin(dphi / 2) ** 2
        + math.cos(p1) * math.cos(p2) * math.sin(dlmb / 2) ** 2
    )
    return 2 * EARTH_R_M * math.asin(min(1.0, math.sqrt(a)))


def point_in_geofence(lat: float, lon: float, fence: MachineGeofence) -> bool:
    dist = haversine_m(lat, lon, fence.center_lat, fence.center_lon)
    return dist <= float(fence.radius_m)


def geofence_to_json(fence: MachineGeofence) -> dict:
    return {
        "id": fence.id,
        "machine_id": fence.machine_id,
        "name": fence.name,
        "center_lat": fence.center_lat,
        "center_lon": fence.center_lon,
        "radius_m": fence.radius_m,
        "enabled": fence.enabled,
        "created_at": fence.created_at.isoformat() + "Z"
        if fence.created_at
        else None,
    }


def gps_point_to_json(p: MachineGpsPoint) -> dict:
    return {
        "lat": p.lat,
        "lon": p.lon,
        "accuracy_m": p.accuracy_m,
        "ts": p.ts.isoformat() + "Z" if p.ts else None,
        "source": p.source,
    }


def _should_store_track(
    db: Session, machine_id: str, lat: float, lon: float, ts: datetime
) -> bool:
    if not is_valid_gps_coordinate(lat, lon):
        return False
    last = (
        db.query(MachineGpsPoint)
        .filter(MachineGpsPoint.machine_id == machine_id)
        .order_by(MachineGpsPoint.ts.desc())
        .first()
    )
    if last is None:
        return True
    if not is_valid_gps_coordinate(last.lat, last.lon):
        return True
    jump = haversine_m(lat, lon, last.lat, last.lon)
    if jump > TRACK_MAX_JUMP_M:
        return False
    dt = abs((ts - last.ts).total_seconds())
    if dt < TRACK_MIN_INTERVAL_S:
        move = haversine_m(lat, lon, last.lat, last.lon)
        if move < TRACK_MIN_MOVE_M:
            return False
    return True


def filter_track_points(points: list[MachineGpsPoint]) -> list[MachineGpsPoint]:
    """Убрать (0,0) и разорвать «телепорты» для карты."""
    out: list[MachineGpsPoint] = []
    prev: MachineGpsPoint | None = None
    for p in points:
        if not is_valid_gps_coordinate(p.lat, p.lon):
            continue
        if prev is not None:
            if haversine_m(p.lat, p.lon, prev.lat, prev.lon) > TRACK_MAX_JUMP_M:
                continue
        out.append(p)
        prev = p
    return out


def _emit_geofence_exit(
    db: Session,
    machine: Machine,
    fence: MachineGeofence,
    lat: float,
    lon: float,
    ts: datetime,
    critical_ids: list[str],
) -> None:
    recent = (
        db.query(Event)
        .filter(
            Event.machine_id == machine.id,
            Event.type == "geofence_exit",
            Event.ts >= ts - GEOFENCE_ALERT_COOLDOWN,
            Event.message.contains(fence.name),
        )
        .first()
    )
    if recent is not None:
        return

    dist = haversine_m(lat, lon, fence.center_lat, fence.center_lon)
    msg = (
        f"Техника вышла за геозону «{fence.name}»: "
        f"{dist:.0f} м от центра (лимит {fence.radius_m:.0f} м)"
    )
    row = Event(
        machine_id=machine.id,
        sensor_id=None,
        type="geofence_exit",
        severity="critical",
        message=msg,
        ts=ts,
        acknowledged=False,
    )
    db.add(row)
    db.flush()
    critical_ids.append(row.id)
    machine.headline_alert = msg
    if machine.status not in ("critical",):
        machine.status = "critical"


def _emit_geofence_enter(
    db: Session,
    machine: Machine,
    fence: MachineGeofence,
    lat: float,
    lon: float,
    ts: datetime,
) -> None:
    recent = (
        db.query(Event)
        .filter(
            Event.machine_id == machine.id,
            Event.type == "geofence_enter",
            Event.ts >= ts - GEOFENCE_ALERT_COOLDOWN,
            Event.message.contains(fence.name),
        )
        .first()
    )
    if recent is not None:
        return
    dist = haversine_m(lat, lon, fence.center_lat, fence.center_lon)
    db.add(
        Event(
            machine_id=machine.id,
            sensor_id=None,
            type="geofence_enter",
            severity="info",
            message=(
                f"Техника вернулась в геозону «{fence.name}»: "
                f"{dist:.0f} м от центра"
            ),
            ts=ts,
            acknowledged=True,
        )
    )


def _outside_geofence(
    lat: float,
    lon: float,
    fence: MachineGeofence,
    accuracy_m: float | None,
) -> bool:
    dist = haversine_m(lat, lon, fence.center_lat, fence.center_lon)
    buffer_m = max(float(accuracy_m or 0.0), GEOFENCE_MIN_BUFFER_M)
    return dist > float(fence.radius_m) + buffer_m


def apply_machine_gps(
    db: Session,
    machine: Machine,
    *,
    lat: float,
    lon: float,
    accuracy_m: float | None = None,
    ts: datetime | None = None,
    source: str = "manual",
) -> list[str]:
    """Обновить позицию, записать трек, проверить геозоны.

    Возвращает id новых critical Event (geofence_exit).
    """
    if not is_valid_gps_coordinate(lat, lon):
        raise ValueError("invalid gps coordinates")

    ts = ts or datetime.utcnow()
    critical_ids: list[str] = []

    machine.gps_lat = float(lat)
    machine.gps_lon = float(lon)
    if accuracy_m is not None:
        machine.gps_accuracy_m = float(accuracy_m)

    if _should_store_track(db, machine.id, lat, lon, ts):
        db.add(
            MachineGpsPoint(
                machine_id=machine.id,
                lat=float(lat),
                lon=float(lon),
                accuracy_m=accuracy_m,
                ts=ts,
                source=source[:32],
            )
        )

    fences = (
        db.query(MachineGeofence)
        .filter(
            MachineGeofence.machine_id == machine.id,
            MachineGeofence.enabled.is_(True),
        )
        .all()
    )
    for fence in fences:
        outside = _outside_geofence(lat, lon, fence, accuracy_m)
        last_inside = machine.geo_last_inside
        machine.geo_region_name = fence.name
        machine.geo_center_lat = fence.center_lat
        machine.geo_center_lon = fence.center_lon
        machine.geo_radius_m = fence.radius_m
        machine.geo_fence_enabled = fence.enabled
        machine.geo_last_inside = not outside
        if outside and last_inside is not False:
            _emit_geofence_exit(db, machine, fence, lat, lon, ts, critical_ids)
        elif not outside and last_inside is False:
            _emit_geofence_enter(db, machine, fence, lat, lon, ts)

    return critical_ids
