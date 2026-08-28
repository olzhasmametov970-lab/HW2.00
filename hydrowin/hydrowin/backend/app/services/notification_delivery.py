from __future__ import annotations

import json
import logging
import smtplib
from email.message import EmailMessage
from email.utils import formataddr
from urllib import error, request

from app.config import settings
from app.email_templates import (
    LOGO_CID,
    LOGO_FILENAME,
    build_alert_html,
    build_alert_plain,
    logo_path,
)

logger = logging.getLogger("hydrowin.notify")


def _opener() -> request.OpenerDirector:
    proxy = (settings.telegram_proxy_url or "").strip()
    if not proxy:
        return request.build_opener()
    return request.build_opener(request.ProxyHandler({"http": proxy, "https": proxy}))


def _post_json(url: str, payload: dict, *, token: str = "", timeout: int = 15) -> dict:
    data = json.dumps(payload).encode("utf-8")
    req = request.Request(url, data=data, method="POST")
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    with _opener().open(req, timeout=timeout) as resp:
        body = resp.read().decode("utf-8", errors="ignore")
        if resp.status >= 300:
            raise RuntimeError(f"HTTP {resp.status}: {body[:200]}")
        try:
            return json.loads(body) if body else {}
        except json.JSONDecodeError:
            return {}


def send_telegram(chat: str, text: str) -> None:
    if not settings.telegram_enabled or not settings.telegram_bot_token:
        raise RuntimeError("Telegram disabled")
    chat_id = (chat or "").strip()
    if not chat_id:
        raise RuntimeError("Telegram chat id пуст")
    url = (
        f"{settings.telegram_api_base.rstrip('/')}/bot"
        f"{settings.telegram_bot_token}/sendMessage"
    )
    try:
        result = _post_json(url, {"chat_id": chat_id, "text": text}, timeout=20)
    except error.URLError as exc:
        raise RuntimeError(
            f"Нет доступа к Telegram API ({exc.reason}). "
            "Проверьте сеть/VPN или задайте TELEGRAM_PROXY_URL"
        ) from exc
    if isinstance(result, dict) and result.get("ok") is False:
        raise RuntimeError(result.get("description") or "Telegram API error")


def _from_header() -> str:
    addr = (settings.smtp_from_email or settings.smtp_user or "").strip()
    name = (settings.smtp_from_name or "HydroWin").strip()
    if not addr:
        return name
    return formataddr((name, addr))


def _attach_inline_logo(html_part: EmailMessage) -> None:
    path = logo_path()
    if not path.is_file():
        logger.warning("email logo missing: %s", path)
        return
    html_part.add_related(
        path.read_bytes(),
        maintype="image",
        subtype="png",
        cid=LOGO_CID,
        filename=LOGO_FILENAME,
    )


def send_email(
    to_email: str,
    subject: str,
    text: str,
    *,
    html_body: str | None = None,
) -> None:
    if not settings.smtp_enabled or not settings.smtp_host:
        raise RuntimeError("SMTP disabled")
    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = _from_header()
    msg["To"] = to_email
    msg.set_content(text)
    if html_body:
        msg.add_alternative(html_body, subtype="html")
        # multipart/related: логотип как cid: — виден без загрузки с сайта
        html_part = msg.get_payload()[-1]
        _attach_inline_logo(html_part)

    if settings.smtp_ssl:
        with smtplib.SMTP_SSL(
            settings.smtp_host, settings.smtp_port, timeout=20
        ) as smtp:
            if settings.smtp_user:
                smtp.login(settings.smtp_user, settings.smtp_password)
            smtp.send_message(msg)
        return

    with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=20) as smtp:
        smtp.ehlo()
        if settings.smtp_starttls:
            smtp.starttls()
            smtp.ehlo()
        if settings.smtp_user:
            smtp.login(settings.smtp_user, settings.smtp_password)
        smtp.send_message(msg)


def notify_channel(channel: str, target: str, machine_code: str, message: str) -> None:
    if channel == "telegram":
        send_telegram(target, f"HydroWin {machine_code}: {message}")
        return
    if channel == "email":
        plain = build_alert_plain(machine_code=machine_code, message=message)
        html_body = build_alert_html(machine_code=machine_code, message=message)
        send_email(
            target,
            f"HydroWin · авария · {machine_code}",
            plain,
            html_body=html_body,
        )
        return
    raise RuntimeError(f"Unsupported channel: {channel}")


def safe_notify_channel(channel: str, target: str, machine_code: str, message: str) -> bool:
    try:
        notify_channel(channel, target, machine_code, message)
        logger.info("notify sent channel=%s target=%s machine=%s", channel, target, machine_code)
        return True
    except (RuntimeError, OSError, smtplib.SMTPException, error.URLError) as exc:
        logger.warning(
            "notify failed channel=%s target=%s machine=%s error=%s",
            channel,
            target,
            machine_code,
            exc,
        )
        return False
