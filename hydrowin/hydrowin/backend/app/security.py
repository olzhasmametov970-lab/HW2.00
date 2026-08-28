import hashlib
import secrets
from datetime import datetime, timedelta

from jose import JWTError, jwt
from passlib.context import CryptContext

from app.config import settings

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
ALGORITHM = "HS256"


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    return pwd_context.verify(password, password_hash)


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def hash_device_key(key: str) -> str:
    return hashlib.sha256(key.encode()).hexdigest()


def create_access_token(user_id: str, org_id: str, role: str) -> tuple[str, int]:
    expires_min = settings.jwt_access_minutes
    expire = datetime.utcnow() + timedelta(minutes=expires_min)
    payload = {
        "sub": user_id,
        "org": org_id,
        "role": role,
        "type": "access",
        "exp": expire,
    }
    token = jwt.encode(payload, settings.jwt_secret, algorithm=ALGORITHM)
    return token, expires_min * 60


def create_refresh_token() -> str:
    return secrets.token_urlsafe(48)


def decode_access_token(token: str) -> dict:
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[ALGORITHM])
        if payload.get("type") != "access":
            raise JWTError("invalid token type")
        return payload
    except JWTError as exc:
        raise ValueError("invalid token") from exc


def evaluate_status(value: float, sensor) -> str:
    if sensor.critical_low is not None and value < sensor.critical_low:
        return "critical"
    if value > sensor.critical_high:
        return "critical"
    if sensor.warn_high is not None and value > sensor.warn_high:
        return "warning"
    if sensor.norm_min is not None and value < sensor.norm_min:
        return "warning"
    if value > sensor.norm_max:
        return "warning"
    return "ok"


def worst_status(statuses: list[str]) -> str:
    order = {"critical": 3, "warning": 2, "ok": 1, "offline": 0}
    if not statuses:
        return "offline"
    return max(statuses, key=lambda s: order.get(s, 0))


def headline_for_status(
    status: str, alert_headlines: list[tuple[str, str]]
) -> str | None:
    """Текст для карточки парка: худший алерт из пакета или None при OK."""
    if status == "critical":
        for sev, msg in alert_headlines:
            if sev == "critical":
                return msg
        return "Критическое состояние"
    if status == "warning":
        for sev, msg in alert_headlines:
            if sev == "warning":
                return msg
        return "Предупреждение"
    return None


# Если блок не присылал данных дольше этого времени — считаем машину офлайн,
# даже если в БД сохранён старый статус ok/warning/critical.
OFFLINE_AFTER_SECONDS = 120


def effective_machine_status(machine) -> str:
    """Статус машины с учётом «свежести» данных.

    `machine.status` хранит статус на момент последнего пакета, но не
    отражает то, что блок отключился. Здесь мы понижаем статус до
    "offline", если last_seen_at устарел, — иначе парк машин показывал
    бы старый статус вечно.
    """
    if machine.last_seen_at is None:
        return "offline"
    age = (datetime.utcnow() - machine.last_seen_at).total_seconds()
    if age > OFFLINE_AFTER_SECONDS:
        return "offline"
    if machine.status in ("ok", "warning", "critical"):
        return machine.status
    return "ok"
