from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from pydantic.config import ConfigDict
from sqlalchemy.orm import Session

from app.audit import write_audit
from app.config import settings
from app.database import get_db
from app.deps import get_current_user
from app.models import NotificationSettings, User
from app.services.notification_delivery import send_email, send_telegram
from app.email_templates import build_alert_html, build_alert_plain
from app.telegram_resolve import (
    is_valid_telegram_contact,
    normalize_telegram_contact,
    resolve_telegram_chat_id,
    sync_telegram_bindings,
)

router = APIRouter(prefix="/notifications", tags=["notifications"])


class ChannelPrefs(BaseModel):
    push: bool = True
    sound: bool = True
    vibration: bool = True
    email: bool = True
    telegram: bool = True


class QuietHours(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    enabled: bool = False
    from_: str = Field("22:00", alias="from")
    to: str = "08:00"


class AlertContacts(BaseModel):
    email: str = ""
    telegram: str = ""


class NotificationSettingsBody(BaseModel):
    critical: ChannelPrefs
    warning: ChannelPrefs
    quiet_hours: QuietHours
    contacts: AlertContacts = AlertContacts()


def _normalize_contacts(body: NotificationSettingsBody) -> AlertContacts:
    contacts = body.contacts
    email = (contacts.email or "").strip()
    telegram = normalize_telegram_contact(contacts.telegram or "")
    if email and ("@" not in email or "." not in email.split("@")[-1]):
        raise HTTPException(
            status_code=400,
            detail={"code": "bad_request", "message": "Некорректный email"},
        )
    if telegram and not is_valid_telegram_contact(telegram):
        raise HTTPException(
            status_code=400,
            detail={
                "code": "bad_request",
                "message": "Telegram: укажите @username (например @ivanov) или chat id",
            },
        )
    return AlertContacts(email=email, telegram=telegram)


def _to_json(ns: NotificationSettings) -> dict:
    return {
        "critical": {
            "push": ns.critical_push,
            "sound": ns.critical_sound,
            "vibration": ns.critical_vibration,
            "email": ns.critical_email,
            "telegram": ns.critical_telegram,
        },
        "warning": {
            "push": ns.warning_push,
            "sound": ns.warning_sound,
            "vibration": ns.warning_vibration,
            "email": ns.warning_email,
            "telegram": ns.warning_telegram,
        },
        "quiet_hours": {
            "enabled": ns.quiet_enabled,
            "from": ns.quiet_from,
            "to": ns.quiet_to,
        },
        "contacts": {
            "email": ns.alert_email_to or "",
            "telegram": ns.alert_telegram_chat or "",
        },
        "policy": {
            "alerts": "critical_only",
            "journal": "warnings_and_all_events",
            "description": (
                "Оповещения только при авариях (critical). "
                "Предупреждения пишутся в журнал без тревоги."
            ),
        },
    }


def _apply(ns: NotificationSettings, body: NotificationSettingsBody) -> None:
    contacts = _normalize_contacts(body)
    ns.critical_push = body.critical.push
    ns.critical_sound = body.critical.sound
    ns.critical_vibration = body.critical.vibration
    ns.critical_sms = False
    ns.critical_email = body.critical.email
    ns.critical_telegram = body.critical.telegram
    ns.critical_phone = False  # голосовой робот снят
    # Warning-каналы принудительно выключены: скачки только в журнал.
    ns.warning_push = False
    ns.warning_sound = False
    ns.warning_vibration = False
    ns.warning_sms = False
    ns.warning_email = False
    ns.warning_telegram = False
    ns.warning_phone = False
    ns.alert_sms_phone = ""
    ns.alert_email_to = contacts.email
    ns.alert_telegram_chat = contacts.telegram
    ns.quiet_enabled = body.quiet_hours.enabled
    ns.quiet_from = body.quiet_hours.from_
    ns.quiet_to = body.quiet_hours.to


@router.get("/settings")
def get_settings(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    ns = db.query(NotificationSettings).filter(NotificationSettings.user_id == user.id).first()
    if ns is None:
        ns = NotificationSettings(user_id=user.id)
        db.add(ns)
        db.commit()
        db.refresh(ns)
    return _to_json(ns)


@router.put("/settings")
def update_settings(
    body: NotificationSettingsBody,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    ns = db.query(NotificationSettings).filter(NotificationSettings.user_id == user.id).first()
    if ns is None:
        ns = NotificationSettings(user_id=user.id)
        db.add(ns)
    _apply(ns, body)
    channels = []
    if body.critical.push:
        channels.append("push")
    if body.critical.email:
        channels.append("email")
    if body.critical.telegram:
        channels.append("telegram")
    contacts = _normalize_contacts(body)
    write_audit(
        db,
        action="settings.notifications",
        message=(
            f"Изменены каналы аварийных оповещений: "
            f"{', '.join(channels) or 'нет'}; "
            f"email={contacts.email or '—'}; "
            f"telegram={contacts.telegram or '—'}; "
            f"тихие часы={'вкл' if body.quiet_hours.enabled else 'выкл'}"
        ),
        user=user,
        severity="info",
    )
    db.commit()
    db.refresh(ns)
    return _to_json(ns)


@router.post("/test-telegram")
def test_telegram(
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Проверка доставки в Telegram без аварии на машине."""
    if not settings.telegram_enabled or not settings.telegram_bot_token:
        raise HTTPException(
            status_code=503,
            detail={
                "code": "telegram_disabled",
                "message": "Telegram на сервере выключен (TELEGRAM_ENABLED / токен)",
            },
        )
    ns = (
        db.query(NotificationSettings)
        .filter(NotificationSettings.user_id == user.id)
        .first()
    )
    chat = ((ns.alert_telegram_chat if ns else None) or "").strip()
    if not chat:
        raise HTTPException(
            status_code=400,
            detail={
                "code": "bad_request",
                "message": "Сначала укажите Telegram @username в настройках и сохраните",
            },
        )
    try:
        # Подтянуть /start от пользователей и резолвить @username → chat_id.
        sync_telegram_bindings(db)
        chat_id = resolve_telegram_chat_id(db, chat)
        send_telegram(
            chat_id,
            f"HydroWin: тестовое оповещение для {user.email}. Канал работает.",
        )
    except RuntimeError as exc:
        raise HTTPException(
            status_code=502,
            detail={"code": "telegram_unreachable", "message": str(exc)},
        ) from exc
    write_audit(
        db,
        action="notify.test_telegram",
        message=f"Тест Telegram → {chat} (id={chat_id})",
        user=user,
        severity="info",
    )
    db.commit()
    return {"ok": True, "chat": chat, "chat_id": chat_id}


@router.post("/test-email")
def test_email(
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Проверка HTML-письма с логотипом без аварии."""
    if not settings.smtp_enabled or not settings.smtp_host:
        raise HTTPException(
            status_code=503,
            detail={
                "code": "smtp_disabled",
                "message": "SMTP на сервере выключен (SMTP_ENABLED / хост)",
            },
        )
    ns = (
        db.query(NotificationSettings)
        .filter(NotificationSettings.user_id == user.id)
        .first()
    )
    to_email = ((ns.alert_email_to if ns else None) or "").strip() or user.email
    if not to_email:
        raise HTTPException(
            status_code=400,
            detail={
                "code": "bad_request",
                "message": "Укажите email в каналах оповещений",
            },
        )
    plain = build_alert_plain(
        machine_code="TEST",
        message=f"Тестовое оповещение для {user.email}. Канал почты работает.",
    )
    html_body = build_alert_html(
        machine_code="TEST",
        message=f"Тестовое оповещение для {user.email}. Канал почты работает.",
    )
    try:
        send_email(
            to_email,
            "HydroWin · тест оповещения",
            plain,
            html_body=html_body,
        )
    except (RuntimeError, OSError) as exc:
        raise HTTPException(
            status_code=502,
            detail={"code": "smtp_unreachable", "message": str(exc)},
        ) from exc
    write_audit(
        db,
        action="notify.test_email",
        message=f"Тест email → {to_email}",
        user=user,
        severity="info",
    )
    db.commit()
    return {"ok": True, "email": to_email}
