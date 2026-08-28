"""Резолв Telegram @username → numeric chat_id.

Bot API не шлёт личные сообщения только по @username: пользователь должен
написать боту /start, после чего getUpdates даёт chat.id + username.
"""

from __future__ import annotations

import json
import logging
import re
import uuid
from datetime import datetime
from urllib import error, request

from sqlalchemy.orm import Session

from app.config import settings
from app.models import TelegramChatBinding

logger = logging.getLogger("hydrowin.telegram")

_USERNAME_RE = re.compile(r"^@?[A-Za-z][A-Za-z0-9_]{4,31}$")


def normalize_telegram_contact(raw: str) -> str:
    """Привести ввод к @username или numeric chat id."""
    value = (raw or "").strip()
    if not value:
        return ""
    if value.lstrip("-").isdigit():
        return value
    if not value.startswith("@"):
        value = f"@{value}"
    return value


def is_valid_telegram_contact(raw: str) -> bool:
    value = normalize_telegram_contact(raw)
    if not value:
        return True
    if value.lstrip("-").isdigit():
        return True
    return bool(_USERNAME_RE.match(value))


def _opener() -> request.OpenerDirector:
    proxy = (settings.telegram_proxy_url or "").strip()
    if not proxy:
        return request.build_opener()
    return request.build_opener(request.ProxyHandler({"http": proxy, "https": proxy}))


def _api_call(method: str, payload: dict | None = None, *, timeout: int = 20) -> dict:
    if not settings.telegram_enabled or not settings.telegram_bot_token:
        raise RuntimeError("Telegram disabled")
    url = (
        f"{settings.telegram_api_base.rstrip('/')}/bot"
        f"{settings.telegram_bot_token}/{method}"
    )
    data = None
    headers = {}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = request.Request(url, data=data, method="POST" if payload is not None else "GET")
    for k, v in headers.items():
        req.add_header(k, v)
    try:
        with _opener().open(req, timeout=timeout) as resp:
            body = resp.read().decode("utf-8", errors="ignore")
    except error.URLError as exc:
        raise RuntimeError(
            f"Нет доступа к Telegram API ({exc.reason}). "
            "Проверьте сеть/VPN или задайте TELEGRAM_PROXY_URL"
        ) from exc
    try:
        result = json.loads(body) if body else {}
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Некорректный ответ Telegram: {body[:200]}") from exc
    if isinstance(result, dict) and result.get("ok") is False:
        raise RuntimeError(result.get("description") or "Telegram API error")
    return result if isinstance(result, dict) else {}


def _upsert_binding(
    db: Session,
    *,
    username: str,
    chat_id: str,
    display_name: str | None,
) -> None:
    uname = username.lower().lstrip("@")
    if not uname:
        return
    row = (
        db.query(TelegramChatBinding)
        .filter(TelegramChatBinding.username == uname)
        .first()
    )
    now = datetime.utcnow()
    if row is None:
        db.add(
            TelegramChatBinding(
                id=str(uuid.uuid4()),
                username=uname,
                chat_id=str(chat_id),
                display_name=display_name,
                updated_at=now,
            )
        )
    else:
        row.chat_id = str(chat_id)
        row.display_name = display_name or row.display_name
        row.updated_at = now


def sync_telegram_bindings(db: Session) -> int:
    """Забрать свежие /start (и любые сообщения) из getUpdates → сохранить username."""
    result = _api_call("getUpdates", {"timeout": 0, "limit": 100}, timeout=25)
    updates = result.get("result") or []
    count = 0
    max_update_id: int | None = None
    for upd in updates:
        if not isinstance(upd, dict):
            continue
        uid = upd.get("update_id")
        if isinstance(uid, int):
            max_update_id = uid if max_update_id is None else max(max_update_id, uid)
        msg = upd.get("message") or upd.get("edited_message") or {}
        if not isinstance(msg, dict):
            continue
        chat = msg.get("chat") or {}
        fr = msg.get("from") or {}
        if not isinstance(chat, dict):
            continue
        chat_id = chat.get("id")
        username = (fr.get("username") if isinstance(fr, dict) else None) or chat.get(
            "username"
        )
        if chat_id is None or not username:
            continue
        first = (fr.get("first_name") if isinstance(fr, dict) else None) or ""
        last = (fr.get("last_name") if isinstance(fr, dict) else None) or ""
        display = f"{first} {last}".strip() or None
        _upsert_binding(
            db,
            username=str(username),
            chat_id=str(chat_id),
            display_name=display,
        )
        count += 1
        # Ответ на /start — чтобы пользователь видел, что бот жив.
        text = (msg.get("text") or "").strip().lower()
        if text.startswith("/start"):
            try:
                _api_call(
                    "sendMessage",
                    {
                        "chat_id": chat_id,
                        "text": (
                            "HydroWin: бот подключён. "
                            "В приложении укажите ваш @username в каналах оповещений."
                        ),
                    },
                )
            except RuntimeError as exc:
                logger.warning("telegram /start reply failed: %s", exc)

    # Сдвигаем offset, чтобы не обрабатывать одно и то же вечно.
    if max_update_id is not None:
        try:
            _api_call("getUpdates", {"offset": max_update_id + 1, "timeout": 0, "limit": 1})
        except RuntimeError:
            pass

    if count:
        db.commit()
    return count


def lookup_chat_id(db: Session, username: str) -> str | None:
    uname = username.lower().lstrip("@")
    row = (
        db.query(TelegramChatBinding)
        .filter(TelegramChatBinding.username == uname)
        .first()
    )
    return row.chat_id if row else None


def resolve_telegram_chat_id(db: Session, contact: str) -> str:
    """Вернуть numeric chat_id. Для @username — из кэша после /start."""
    value = normalize_telegram_contact(contact)
    if not value:
        raise RuntimeError("Telegram контакт пуст")
    if value.lstrip("-").isdigit():
        return value

    found = lookup_chat_id(db, value)
    if found:
        return found

    # Подтянуть свежие сообщения боту и повторить поиск.
    try:
        sync_telegram_bindings(db)
    except RuntimeError as exc:
        raise RuntimeError(str(exc)) from exc

    found = lookup_chat_id(db, value)
    if found:
        return found

    raise RuntimeError(
        f"Не найден chat id для {value}. "
        "Откройте бота HydroWin в Telegram, нажмите Start (/start), "
        "затем снова «Проверить Telegram» в приложении. "
        "У аккаунта должен быть публичный @username."
    )
