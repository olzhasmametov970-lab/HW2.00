"""Диспетчер каналов оповещений при реальных авариях (critical).

Мелкие warning в каналы не уходят — только запись в events (журнал).
Почта и Telegram отправляются по введенным пользователем контактам.
"""

from __future__ import annotations

import logging
from datetime import datetime, time

from sqlalchemy.orm import Session

from app.audit import write_audit
from app.models import Event, Machine, NotificationSettings, User
from app.org_access import can_view_machine
from app.roles import ROLE_ORG_ADMIN, ROLE_DRIVER, ROLE_DISPATCHER
from app.services.notification_delivery import safe_notify_channel
from app.telegram_resolve import resolve_telegram_chat_id

logger = logging.getLogger("hydrowin.alerts")

_STAFF = (ROLE_ORG_ADMIN, ROLE_DISPATCHER, ROLE_DRIVER)


def _parse_hhmm(value: str) -> time:
    parts = (value or "00:00").split(":")
    h = int(parts[0]) if parts and parts[0].isdigit() else 0
    m = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 0
    return time(hour=min(23, max(0, h)), minute=min(59, max(0, m)))


def _in_quiet_hours(ns: NotificationSettings, now: datetime | None = None) -> bool:
    if not ns.quiet_enabled:
        return False
    now = now or datetime.utcnow()
    start = _parse_hhmm(ns.quiet_from)
    end = _parse_hhmm(ns.quiet_to)
    t = now.time()
    if start <= end:
        return start <= t < end
    # через полночь: 22:00–08:00
    return t >= start or t < end


def _channels_for_critical(ns: NotificationSettings) -> list[str]:
    out: list[str] = []
    if ns.critical_push:
        out.append("push")
    if ns.critical_email and (ns.alert_email_to or "").strip():
        out.append("email")
    if ns.critical_telegram and (ns.alert_telegram_chat or "").strip():
        out.append("telegram")
    return out


def dispatch_critical_event(db: Session, event: Event) -> int:
    """Оповестить инженеров по каналам. Возвращает число адресатов с ≥1 каналом."""
    if event.severity != "critical":
        return 0
    machine = db.get(Machine, event.machine_id)
    if machine is None:
        return 0

    users = db.query(User).filter(User.role.in_(_STAFF)).all()
    notified = 0
    for user in users:
        if not can_view_machine(db, user, machine):
            continue
        ns = (
            db.query(NotificationSettings)
            .filter(NotificationSettings.user_id == user.id)
            .first()
        )
        if ns is None:
            ns = NotificationSettings(user_id=user.id)
            db.add(ns)
            db.flush()
        if _in_quiet_hours(ns):
            continue
        channels = _channels_for_critical(ns)
        if not channels:
            continue
        notified += 1
        for ch in channels:
            target = {
                "push": user.email,
                "email": (ns.alert_email_to or "").strip() or user.email,
                "telegram": (ns.alert_telegram_chat or "").strip() or user.email,
            }.get(ch, user.email)
            if ch == "push":
                logger.info(
                    "ALERT queue channel=%s target=%s machine=%s event=%s msg=%s",
                    ch,
                    target,
                    machine.code,
                    event.id,
                    event.message[:120],
                )
                continue
            if ch == "telegram":
                try:
                    target = resolve_telegram_chat_id(db, target)
                except RuntimeError as exc:
                    logger.warning(
                        "ALERT telegram resolve failed user=%s target=%s err=%s",
                        user.email,
                        ns.alert_telegram_chat,
                        exc,
                    )
                    continue
            ok = safe_notify_channel(ch, target, machine.code, event.message)
            logger.info(
                "ALERT deliver channel=%s target=%s machine=%s event=%s ok=%s",
                ch,
                target,
                machine.code,
                event.id,
                ok,
            )
        write_audit(
            db,
            action="notify.queued",
            message=(
                f"Авария «{machine.code}»: {event.message} "
                f"→ каналы {', '.join(channels)}"
            ),
            user=user,
            severity="critical",
        )
    return notified


def dispatch_new_critical_events(db: Session, event_ids: list[str]) -> None:
    for eid in event_ids:
        event = db.get(Event, eid)
        if event is not None:
            dispatch_critical_event(db, event)
