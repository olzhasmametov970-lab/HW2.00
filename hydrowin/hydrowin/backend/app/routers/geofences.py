from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.database import get_db
from app.geo import gps_point_to_json
from app.models import Machine, MachineGeofence, MachineGpsPoint, User
from app.org_access import is_driver, load_machine_for_user
from app.routers.machines import _require_view
from app.deps import get_current_user

router = APIRouter(tags=["geofences", "telemetry"])


class GeofenceBody(BaseModel):
    name: str = Field(default="", max_length=255)
    center_lat: float = Field(ge=-90, le=90)
    center_lon: float = Field(ge=-180, le=180)
    radius_m: float = Field(gt=1, le=1_000_000)
    enabled: bool = True


def _fence_json(machine: Machine, fence: MachineGeofence | None) -> dict:
    if fence is None:
        return {
            "machine_id": machine.id,
            "name": getattr(machine, "geo_region_name", None) or "",
            "center_lat": getattr(machine, "geo_center_lat", None),
            "center_lon": getattr(machine, "geo_center_lon", None),
            "radius_m": getattr(machine, "geo_radius_m", None),
            "enabled": bool(getattr(machine, "geo_fence_enabled", False)),
            "inside": getattr(machine, "geo_last_inside", None),
        }
    return {
        "id": fence.id,
        "machine_id": machine.id,
        "name": fence.name,
        "center_lat": fence.center_lat,
        "center_lon": fence.center_lon,
        "radius_m": fence.radius_m,
        "enabled": fence.enabled,
        "inside": getattr(machine, "geo_last_inside", None),
        "created_at": fence.created_at.isoformat() + "Z" if fence.created_at else None,
        "updated_at": fence.updated_at.isoformat() + "Z" if fence.updated_at else None,
    }


@router.get("/machines/id/{machine_id}/geofence")
def get_machine_geofence(
    machine_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    machine, _ = load_machine_for_user(db, user, machine_id)
    machine, _ = _require_view(db, user, machine)
    fence = (
        db.query(MachineGeofence)
        .filter(MachineGeofence.machine_id == machine.id)
        .first()
    )
    return _fence_json(machine, fence)


@router.put("/machines/id/{machine_id}/geofence")
def put_machine_geofence(
    machine_id: str,
    body: GeofenceBody,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    machine, _ = load_machine_for_user(db, user, machine_id)
    machine, _ = _require_view(db, user, machine)
    if is_driver(user):
        raise HTTPException(
            status_code=403,
            detail={"code": "forbidden", "message": "Нет прав менять геозону"},
        )
    fence = (
        db.query(MachineGeofence)
        .filter(MachineGeofence.machine_id == machine.id)
        .first()
    )
    if fence is None:
        fence = MachineGeofence(machine_id=machine.id)
        db.add(fence)
    fence.name = body.name.strip() or f"Регион {machine.code}"
    fence.center_lat = body.center_lat
    fence.center_lon = body.center_lon
    fence.radius_m = body.radius_m
    fence.enabled = body.enabled

    machine.geo_region_name = fence.name
    machine.geo_center_lat = fence.center_lat
    machine.geo_center_lon = fence.center_lon
    machine.geo_radius_m = fence.radius_m
    machine.geo_fence_enabled = fence.enabled
    machine.geo_last_inside = None

    db.commit()
    db.refresh(machine)
    db.refresh(fence)
    return _fence_json(machine, fence)


@router.get("/machines/id/{machine_id}/track")
def get_machine_track(
    machine_id: str,
    from_: str | None = Query(None, alias="from"),
    to: str | None = Query(None),
    limit: int = Query(500, ge=1, le=5000),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    machine, _ = load_machine_for_user(db, user, machine_id)
    machine, _ = _require_view(db, user, machine)
    query = db.query(MachineGpsPoint).filter(MachineGpsPoint.machine_id == machine.id)
    if from_:
        query = query.filter(
            MachineGpsPoint.ts >= datetime.fromisoformat(from_.replace("Z", ""))
        )
    if to:
        query = query.filter(
            MachineGpsPoint.ts <= datetime.fromisoformat(to.replace("Z", ""))
        )
    items = query.order_by(MachineGpsPoint.ts.desc()).limit(limit).all()
    items.reverse()
    return {"items": [gps_point_to_json(p) for p in items]}
