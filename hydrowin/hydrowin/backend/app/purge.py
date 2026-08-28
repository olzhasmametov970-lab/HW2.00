"""Каскадное удаление машин, пользователей и организаций."""

from __future__ import annotations

from sqlalchemy.orm import Session

from app.models import (
    AuditLog,
    Device,
    Event,
    Machine,
    MachineGeofence,
    MachineGpsPoint,
    NotificationSettings,
    Organization,
    Reading,
    ReadingDaily,
    ReadingHourly,
    RefreshToken,
    Sensor,
    User,
)
from app.org_types import ORG_TYPE_MANUFACTURER


def purge_machine(db: Session, machine: Machine) -> None:
    """Жёстко удаляет машину и всю связанную историю (иначе FK → 500)."""
    mid = machine.id
    db.query(User).filter(User.assigned_machine_id == mid).update(
        {User.assigned_machine_id: None},
        synchronize_session=False,
    )
    sensor_ids = [
        row[0]
        for row in db.query(Sensor.id).filter(Sensor.machine_id == mid).all()
    ]
    if sensor_ids:
        db.query(Reading).filter(Reading.sensor_id.in_(sensor_ids)).delete(
            synchronize_session=False
        )
        db.query(ReadingHourly).filter(ReadingHourly.sensor_id.in_(sensor_ids)).delete(
            synchronize_session=False
        )
        db.query(ReadingDaily).filter(ReadingDaily.sensor_id.in_(sensor_ids)).delete(
            synchronize_session=False
        )
    db.query(Reading).filter(Reading.machine_id == mid).delete(
        synchronize_session=False
    )
    db.query(ReadingHourly).filter(ReadingHourly.machine_id == mid).delete(
        synchronize_session=False
    )
    db.query(ReadingDaily).filter(ReadingDaily.machine_id == mid).delete(
        synchronize_session=False
    )
    db.query(Event).filter(Event.machine_id == mid).delete(synchronize_session=False)
    db.query(Device).filter(Device.machine_id == mid).delete(synchronize_session=False)
    db.query(MachineGpsPoint).filter(MachineGpsPoint.machine_id == mid).delete(
        synchronize_session=False
    )
    db.query(MachineGeofence).filter(MachineGeofence.machine_id == mid).delete(
        synchronize_session=False
    )
    db.query(Sensor).filter(Sensor.machine_id == mid).delete(synchronize_session=False)
    db.delete(machine)
    db.flush()


def purge_user(db: Session, target: User) -> None:
    """Удаляет пользователя вместе с токенами и настройками уведомлений."""
    db.query(RefreshToken).filter(RefreshToken.user_id == target.id).delete(
        synchronize_session=False
    )
    db.query(NotificationSettings).filter(
        NotificationSettings.user_id == target.id
    ).delete(synchronize_session=False)
    # Журнал аудита сохраняем, ссылку на пользователя обнуляем.
    db.query(AuditLog).filter(AuditLog.user_id == target.id).update(
        {AuditLog.user_id: None},
        synchronize_session=False,
    )
    db.delete(target)
    db.flush()


def purge_organization(db: Session, org: Organization) -> dict[str, int]:
    """
    Каскад: клиенты производителя → пользователи → машины → организация.
    Возвращает счётчики удалённого.
    """
    deleted_orgs = 0
    deleted_users = 0
    deleted_machines = 0

    if org.org_type == ORG_TYPE_MANUFACTURER:
        clients = (
            db.query(Organization)
            .filter(Organization.manufacturer_id == org.id)
            .all()
        )
        for client in clients:
            stats = purge_organization(db, client)
            deleted_orgs += stats["organizations"]
            deleted_users += stats["users"]
            deleted_machines += stats["machines"]

    users = db.query(User).filter(User.organization_id == org.id).all()
    for u in users:
        purge_user(db, u)
        deleted_users += 1

    machines = db.query(Machine).filter(Machine.organization_id == org.id).all()
    for m in machines:
        purge_machine(db, m)
        deleted_machines += 1

    # На случай остаточных ссылок (склад уже пуст, но manufacturer_id где-то остался).
    db.query(Machine).filter(Machine.manufacturer_id == org.id).update(
        {Machine.manufacturer_id: None},
        synchronize_session=False,
    )
    db.query(Organization).filter(Organization.manufacturer_id == org.id).update(
        {Organization.manufacturer_id: None},
        synchronize_session=False,
    )
    # audit_logs.organization_id — FK, журнал оставляем, ссылку обнуляем.
    db.query(AuditLog).filter(AuditLog.organization_id == org.id).update(
        {AuditLog.organization_id: None},
        synchronize_session=False,
    )

    db.delete(org)
    db.flush()
    deleted_orgs += 1

    return {
        "organizations": deleted_orgs,
        "users": deleted_users,
        "machines": deleted_machines,
    }
