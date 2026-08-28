"""Журнал безопасности: входы, смена настроек, очередь оповещений."""

from datetime import datetime

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.deps import get_current_user, iso_z
from app.models import AuditLog, User
from app.org_access import get_user_org, is_platform_org

router = APIRouter(tags=["audit"])


def _audit_json(row: AuditLog) -> dict:
    return {
        "id": row.id,
        "organization_id": row.organization_id,
        "user_id": row.user_id,
        "actor_email": row.actor_email,
        "action": row.action,
        "severity": row.severity,
        "message": row.message,
        "ts": iso_z(row.ts),
        "kind": "audit",
    }


@router.get("/audit")
def list_audit(
    q: str | None = Query(None, description="Поиск по тексту / email / action"),
    action: str | None = Query(None),
    from_: str | None = Query(None, alias="from"),
    to: str | None = Query(None),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    org = get_user_org(db, user)
    query = db.query(AuditLog)
    if not is_platform_org(org):
        query = query.filter(AuditLog.organization_id == user.organization_id)

    if action:
        query = query.filter(AuditLog.action == action)
    if from_:
        query = query.filter(
            AuditLog.ts >= datetime.fromisoformat(from_.replace("Z", ""))
        )
    if to:
        query = query.filter(
            AuditLog.ts <= datetime.fromisoformat(to.replace("Z", ""))
        )
    if q:
        like = f"%{q.strip()}%"
        query = query.filter(
            (AuditLog.message.ilike(like))
            | (AuditLog.actor_email.ilike(like))
            | (AuditLog.action.ilike(like))
        )

    rows = query.order_by(AuditLog.ts.desc()).limit(200).all()
    return [_audit_json(r) for r in rows]
