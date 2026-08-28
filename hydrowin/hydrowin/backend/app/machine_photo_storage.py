"""Хранение фото станков на диске."""

from __future__ import annotations

import base64
import re
from pathlib import Path

UPLOAD_ROOT = Path(__file__).resolve().parent.parent / "uploads" / "machines"
_MAX_BYTES = 700_000
_ALLOWED = {"jpg", "jpeg", "png", "webp"}


def ensure_upload_dir() -> Path:
    UPLOAD_ROOT.mkdir(parents=True, exist_ok=True)
    return UPLOAD_ROOT


def machine_photo_path(machine_id: str, ext: str) -> Path:
    safe_ext = ext.lower().lstrip(".")
    if safe_ext == "jpeg":
        safe_ext = "jpg"
    return ensure_upload_dir() / f"{machine_id}.{safe_ext}"


def save_machine_photo_base64(machine_id: str, data_url_or_b64: str) -> str:
    """Сохраняет data:image/...;base64,... или чистый base64. Возвращает ext."""
    raw = (data_url_or_b64 or "").strip()
    if not raw:
        raise ValueError("Пустое изображение")

    ext = "jpg"
    payload = raw
    m = re.match(
        r"^data:image/(png|jpeg|jpg|webp);base64,(.+)$",
        raw,
        flags=re.IGNORECASE | re.DOTALL,
    )
    if m:
        ext = m.group(1).lower()
        payload = m.group(2)
    try:
        binary = base64.b64decode(payload, validate=False)
    except Exception as exc:  # noqa: BLE001
        raise ValueError("Некорректный base64") from exc
    if not binary:
        raise ValueError("Пустое изображение")
    if len(binary) > _MAX_BYTES:
        raise ValueError("Фото слишком большое (макс. ~500 КБ)")
    if ext == "jpeg":
        ext = "jpg"
    if ext not in _ALLOWED:
        raise ValueError("Допустимы JPG, PNG, WEBP")

    for old in ensure_upload_dir().glob(f"{machine_id}.*"):
        try:
            old.unlink()
        except OSError:
            pass
    path = machine_photo_path(machine_id, ext)
    path.write_bytes(binary)
    return ext


def delete_machine_photo(machine_id: str) -> None:
    for old in ensure_upload_dir().glob(f"{machine_id}.*"):
        try:
            old.unlink()
        except OSError:
            pass
