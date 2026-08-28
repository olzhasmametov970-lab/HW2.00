"""Правила видимости и записи машин по организации.

Иерархия: platform (админ) → manufacturer (производитель) → client (завод).
Водитель (driver): только users.assigned_machine_id.
"""

from __future__ import annotations

from sqlalchemy.orm import Session
from sqlalchemy.sql import false

from app.models import Machine, Organization, User
from app.org_types import (
    ACCESS_MANUFACTURER_READONLY,
    ACCESS_OWNER,
    ACCESS_PLATFORM,
    ORG_TYPE_MANUFACTURER,
    ORG_TYPE_PLATFORM,
)
from app.roles import ROLE_DRIVER


def get_user_org(db: Session, user: User) -> Organization | None:
    return db.get(Organization, user.organization_id)


def is_platform_org(org: Organization | None) -> bool:
    return org is not None and org.org_type == ORG_TYPE_PLATFORM


def is_manufacturer_org(org: Organization | None) -> bool:
    return org is not None and org.org_type == ORG_TYPE_MANUFACTURER


def is_driver(user: User) -> bool:
    return user.role == ROLE_DRIVER


def machines_visible_query(db: Session, user: User):
    """Машины, которые пользователь может видеть в парке."""
    org = get_user_org(db, user)
    q = db.query(Machine)

    if is_driver(user):
        mid = getattr(user, "assigned_machine_id", None)
        if not mid:
            return q.filter(false())
        return q.filter(Machine.id == mid)

    if org is None:
        return q.filter(Machine.organization_id == user.organization_id)

    # Админ платформы — все машины
    if is_platform_org(org):
        return q

    if is_manufacturer_org(org):
        # Только блоки, которые админ платформы закрепил (manufacturer_id)
        return q.filter(Machine.manufacturer_id == org.id)

    # Завод: только свои
    return q.filter(Machine.organization_id == org.id)


def can_view_machine(db: Session, user: User, machine: Machine) -> bool:
    if is_driver(user):
        mid = getattr(user, "assigned_machine_id", None)
        return bool(mid) and machine.id == mid

    org = get_user_org(db, user)
    if org is None:
        return machine.organization_id == user.organization_id
    if is_platform_org(org):
        return True
    if is_manufacturer_org(org):
        return machine.manufacturer_id == org.id
    return machine.organization_id == org.id


def machine_access_for_user(db: Session, user: User, machine: Machine) -> str | None:
    """Возвращает уровень доступа или None, если машина недоступна."""
    if not can_view_machine(db, user, machine):
        return None
    if is_driver(user):
        # Чтение своей машины как «владелец», запись режется в can_write_machine.
        return ACCESS_OWNER
    org = get_user_org(db, user)
    if is_platform_org(org):
        return ACCESS_PLATFORM
    if is_manufacturer_org(org):
        # Склад производителя — полный доступ; у клиента — только просмотр
        if machine.organization_id == org.id:
            return ACCESS_OWNER
        return ACCESS_MANUFACTURER_READONLY
    if machine.organization_id == user.organization_id:
        return ACCESS_OWNER
    return None


def can_write_machine(db: Session, user: User, machine: Machine) -> bool:
    """Конфигурация датчиков/полей: владелец или платформенный админ (не водитель)."""
    if is_driver(user):
        return False
    org = get_user_org(db, user)
    if is_platform_org(org):
        return True
    return machine.organization_id == user.organization_id


def can_reassign_machine(db: Session, user: User, machine: Machine) -> bool:
    """Смена владельца / назначение производителю."""
    if is_driver(user):
        return False
    org = get_user_org(db, user)
    if org is None:
        return False
    if is_platform_org(org):
        return True
    if is_manufacturer_org(org) and machine.manufacturer_id == org.id:
        return True
    return False


def load_machine_for_user(
    db: Session, user: User, machine_id: str
) -> tuple[Machine | None, str | None]:
    machine = db.get(Machine, machine_id)
    if machine is None:
        return None, None
    access = machine_access_for_user(db, user, machine)
    if access is None:
        return None, None
    return machine, access
