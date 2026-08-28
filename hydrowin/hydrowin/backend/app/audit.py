"""Запись действий в журнал безопасности (audit_logs)."""

from __future__ import annotations

from sqlalchemy.orm import Session

from app.models import AuditLog, User


def write_audit(
    db: Session,
    *,
    action: str,
    message: str,
    user: User | None = None,
    organization_id: str | None = None,
    actor_email: str | None = None,
    severity: str = "info",
    commit: bool = False,
) -> AuditLog:
    row = AuditLog(
        organization_id=organization_id
        or (user.organization_id if user is not None else None),
        user_id=user.id if user is not None else None,
        actor_email=(
            actor_email
            or (user.email if user is not None else None)
        ),
        action=action,
        severity=severity,
        message=message,
    )
    db.add(row)
    if commit:
        db.commit()
        db.refresh(row)
    return row
