from datetime import datetime
from typing import Annotated, Any

from fastapi import Depends, Header, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Device, Organization, User
from app.org_types import ACCESS_OWNER, ACCESS_PLATFORM
from app.roles import ADMIN_ROLES, ROLE_ORG_ADMIN, STAFF_ROLES
from app.security import decode_access_token, effective_machine_status, hash_device_key

bearer_scheme = HTTPBearer(auto_error=False)


def get_current_user(
    creds: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    if creds is None or not creds.credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "unauthorized", "message": "Требуется авторизация"},
        )
    try:
        payload = decode_access_token(creds.credentials)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "unauthorized", "message": "Недействительный токен"},
        ) from None

    user = db.get(User, payload["sub"])
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "unauthorized", "message": "Пользователь не найден"},
        )
    return user


def require_roles(*allowed: str):
    """Dependency factory: пользователь должен иметь одну из ролей."""

    allowed_set = set(allowed) if allowed else set(STAFF_ROLES)

    def _checker(user: User = Depends(get_current_user)) -> User:
        if user.role not in allowed_set:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail={
                    "code": "forbidden",
                    "message": "Недостаточно прав для этого действия",
                },
            )
        return user

    return _checker


require_staff = require_roles(*STAFF_ROLES)
require_admin = require_roles(*ADMIN_ROLES)


def is_admin(user: User) -> bool:
    return user.role == ROLE_ORG_ADMIN or user.role in ADMIN_ROLES


def get_device_by_key(
    x_device_key: Annotated[str | None, Header(alias="X-Device-Key")] = None,
    db: Session = Depends(get_db),
) -> Device:
    if not x_device_key:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "unauthorized", "message": "X-Device-Key обязателен"},
        )
    key_hash = hash_device_key(x_device_key)
    device = db.query(Device).filter(Device.api_key_hash == key_hash).first()
    if device is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "unauthorized", "message": "Неверный ключ устройства"},
        )
    return device


def org_to_json(org: Organization) -> dict[str, Any]:
    return {
        "id": org.id,
        "name": org.name,
        "org_type": getattr(org, "org_type", None) or "client",
        "manufacturer_id": getattr(org, "manufacturer_id", None),
    }


def machine_to_summary(
    machine,
    *,
    access: str = ACCESS_OWNER,
    owner_org_name: str | None = None,
    can_reassign: bool = False,
    can_configure: bool | None = None,
) -> dict[str, Any]:
    return {
        "id": machine.id,
        "code": machine.code,
        "name": machine.name,
        "model": machine.model,
        "status": effective_machine_status(machine),
        "location_label": machine.location_label,
        "operator_name": machine.operator_name,
        "headline_alert": machine.headline_alert,
        "engine_hours": machine.engine_hours,
        "uptime_hours": getattr(machine, "uptime_hours", None) or 0,
        "pump_hours": getattr(machine, "pump_hours", None) or 0,
        "pump_starts": int(getattr(machine, "pump_starts", None) or 0),
        "pump_on_pressure_bar": float(
            getattr(machine, "pump_on_pressure_bar", None) or 20.0
        ),
        "pump_on_temperature_c": float(
            getattr(machine, "pump_on_temperature_c", None) or 35.0
        ),
        "last_seen_at": machine.last_seen_at.isoformat() + "Z"
        if machine.last_seen_at
        else None,
        "organization_id": machine.organization_id,
        "manufacturer_id": getattr(machine, "manufacturer_id", None),
        "sold_at": (
            machine.sold_at.isoformat() + "Z"
            if getattr(machine, "sold_at", None)
            else None
        ),
        "access": access,
        "owner_org_name": owner_org_name,
        "can_configure": (
            can_configure
            if can_configure is not None
            else access in (ACCESS_OWNER, ACCESS_PLATFORM)
        ),
        "can_reassign": can_reassign,
        "gps": (
            {
                "lat": machine.gps_lat,
                "lon": machine.gps_lon,
                "accuracy_m": machine.gps_accuracy_m or 0,
            }
            if machine.gps_lat is not None and machine.gps_lon is not None
            else None
        ),
        "geofence": (
            {
                "name": getattr(machine, "geo_region_name", None) or "",
                "center_lat": getattr(machine, "geo_center_lat", None),
                "center_lon": getattr(machine, "geo_center_lon", None),
                "radius_m": getattr(machine, "geo_radius_m", None),
                "enabled": bool(getattr(machine, "geo_fence_enabled", False)),
                "inside": getattr(machine, "geo_last_inside", None),
            }
            if getattr(machine, "geo_center_lat", None) is not None
            and getattr(machine, "geo_center_lon", None) is not None
            and getattr(machine, "geo_radius_m", None) is not None
            else None
        ),
        "description": getattr(machine, "description", None) or "",
        "photo_url": (
            f"/v1/media/machines/{machine.id}.{getattr(machine, 'photo_ext', None)}"
            if getattr(machine, "photo_ext", None)
            else None
        ),
    }


def machine_to_detail(
    machine,
    *,
    access: str = ACCESS_OWNER,
    owner_org_name: str | None = None,
    can_reassign: bool = False,
    can_configure: bool | None = None,
) -> dict[str, Any]:
    data = machine_to_summary(
        machine,
        access=access,
        owner_org_name=owner_org_name,
        can_reassign=can_reassign,
        can_configure=can_configure,
    )
    data["bluetooth_status"] = machine.bluetooth_status
    return data


def sensor_to_json(sensor) -> dict[str, Any]:
    return {
        "id": sensor.id,
        "name": sensor.name,
        "type": sensor.type,
        "unit": sensor.unit,
        "scale_min": sensor.scale_min,
        "scale_max": sensor.scale_max,
        "norm_min": sensor.norm_min,
        "norm_max": sensor.norm_max,
        "warn_high": sensor.warn_high,
        "critical_high": sensor.critical_high,
        "critical_low": sensor.critical_low,
        "channel_index": sensor.channel_index,
        "enabled": bool(getattr(sensor, "enabled", True)),
    }


def user_to_json(
    user: User,
    org: Organization | None = None,
    *,
    machine=None,
) -> dict[str, Any]:
    avatar_ext = getattr(user, "avatar_ext", None)
    birth = getattr(user, "birth_date", None)
    data = {
        "id": user.id,
        "name": user.name,
        "email": user.email,
        "role": user.role,
        "organization_id": user.organization_id,
        "assigned_machine_id": getattr(user, "assigned_machine_id", None),
        "first_name": getattr(user, "first_name", None) or "",
        "last_name": getattr(user, "last_name", None) or "",
        "birth_date": birth.date().isoformat() if birth is not None else None,
        "gender": getattr(user, "gender", None) or "",
        "phone": getattr(user, "phone", None) or "",
        "about": getattr(user, "about", None) or "",
        "avatar_url": (
            f"/v1/media/avatars/{user.id}.{avatar_ext}"
            if avatar_ext
            else None
        ),
    }
    if org is not None:
        data["organization"] = org_to_json(org)
    if machine is not None:
        data["assigned_machine_code"] = getattr(machine, "code", None)
        data["assigned_machine_name"] = getattr(machine, "name", None)
    return data


def iso_z(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%dT%H:%M:%S") + "Z"
