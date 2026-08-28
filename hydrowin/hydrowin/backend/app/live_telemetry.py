"""Кэш последних показаний на sensors + сборка live-ответов API."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from sqlalchemy.orm import Session

from app.deps import iso_z
from app.models import Machine, Sensor, User
from app.org_access import machine_access_for_user, machines_visible_query
from app.security import effective_machine_status


def apply_sensor_live(
    sensor: Sensor,
    *,
    value: float,
    ts: datetime,
    status: str,
    fault: str | None = None,
    current_ma: float | None = None,
) -> None:
    sensor.last_value = value
    sensor.last_ts = ts
    sensor.last_status = status
    sensor.last_fault = fault
    sensor.last_current_ma = current_ma


def sensor_live_json(sensor: Sensor) -> dict[str, Any]:
    return {
        "id": sensor.id,
        "channel": sensor.channel_index,
        "name": sensor.name,
        "type": sensor.type,
        "unit": sensor.unit,
        "value": sensor.last_value,
        "ts": iso_z(sensor.last_ts) if sensor.last_ts else None,
        "status": sensor.last_status or "offline",
        "fault": sensor.last_fault,
        "current_ma": sensor.last_current_ma,
    }


def machine_live_json(machine: Machine, sensors: list[Sensor]) -> dict[str, Any]:
    ordered = sorted(sensors, key=lambda s: s.channel_index)
    return {
        "machine_id": machine.id,
        "code": machine.code,
        "status": effective_machine_status(machine),
        "last_seen_at": (
            iso_z(machine.last_seen_at) if machine.last_seen_at else None
        ),
        "sensors": [sensor_live_json(s) for s in ordered],
    }


def fleet_live_for_user(db: Session, user: User) -> dict[str, Any]:
    machines = machines_visible_query(db, user).order_by(Machine.code).all()
    machine_ids = [m.id for m in machines]
    sensors_by_machine: dict[str, list[Sensor]] = {mid: [] for mid in machine_ids}
    if machine_ids:
        for sensor in (
            db.query(Sensor).filter(Sensor.machine_id.in_(machine_ids)).all()
        ):
            sensors_by_machine.setdefault(sensor.machine_id, []).append(sensor)

    items: list[dict[str, Any]] = []
    for machine in machines:
        if machine_access_for_user(db, user, machine) is None:
            continue
        items.append(
            machine_live_json(machine, sensors_by_machine.get(machine.id, []))
        )

    return {
        "machines": items,
        "at": iso_z(datetime.utcnow()),
    }
