from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.audit import write_audit
from app.database import get_db
from app.deps import get_current_user, iso_z
from app.models import Event, Machine, User
from app.org_access import can_view_machine, machines_visible_query

router = APIRouter(tags=["events"])


def _event_json(e: Event, machine: Machine | None = None) -> dict:
    data = {
        "id": e.id,
        "machine_id": e.machine_id,
        "sensor_id": e.sensor_id,
        "type": e.type,
        "severity": e.severity,
        "message": e.message,
        "ts": iso_z(e.ts),
        "acknowledged": e.acknowledged,
        "kind": "event",
    }
    if machine is not None:
        data["machine_code"] = machine.code
        data["machine_name"] = machine.name
    return data


@router.get("/events")
def list_events(
    machine_id: str | None = Query(None),
    from_: str | None = Query(None, alias="from"),
    to: str | None = Query(None),
    severity: str | None = Query(None),
    acknowledged: bool | None = Query(None),
    q: str | None = Query(None, description="Поиск по тексту / типу события"),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    visible = {m.id: m for m in machines_visible_query(db, user).all()}
    query = db.query(Event).filter(Event.machine_id.in_(visible.keys() or {"__none__"}))
    if machine_id:
        if machine_id not in visible:
            raise HTTPException(
                status_code=404, detail={"code": "not_found", "message": "machine not found"}
            )
        query = query.filter(Event.machine_id == machine_id)
    if severity:
        query = query.filter(Event.severity == severity)
    if acknowledged is not None:
        query = query.filter(Event.acknowledged.is_(acknowledged))
    if from_:
        query = query.filter(Event.ts >= datetime.fromisoformat(from_.replace("Z", "")))
    if to:
        query = query.filter(Event.ts <= datetime.fromisoformat(to.replace("Z", "")))
    if q:
        like = f"%{q.strip()}%"
        query = query.filter(
            (Event.message.ilike(like)) | (Event.type.ilike(like))
        )
    events = query.order_by(Event.ts.desc()).limit(200).all()
    return [_event_json(e, visible.get(e.machine_id)) for e in events]


@router.post("/events/{event_id}/acknowledge")
def acknowledge_event(
    event_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    event = db.get(Event, event_id)
    if event is None:
        raise HTTPException(
            status_code=404, detail={"code": "not_found", "message": "event not found"}
        )
    machine = db.get(Machine, event.machine_id)
    if machine is None or not can_view_machine(db, user, machine):
        raise HTTPException(
            status_code=404, detail={"code": "not_found", "message": "event not found"}
        )
    event.acknowledged = True
    write_audit(
        db,
        action="event.acknowledge",
        message=f"Подтверждена авария «{machine.code}»: {event.message}",
        user=user,
        severity="info",
    )
    db.commit()
    db.refresh(event)
    return _event_json(event, machine)
