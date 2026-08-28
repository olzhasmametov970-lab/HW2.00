"""Раздача загруженных файлов (аватары, фото станков)."""

from __future__ import annotations

import re

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse

from app.avatar_storage import UPLOAD_ROOT as AVATAR_ROOT
from app.avatar_storage import ensure_upload_dir as ensure_avatar_dir
from app.machine_photo_storage import UPLOAD_ROOT as MACHINE_ROOT
from app.machine_photo_storage import ensure_upload_dir as ensure_machine_dir

router = APIRouter(prefix="/media", tags=["media"])

_SAFE = re.compile(r"^[0-9a-fA-F-]{36}\.(jpg|jpeg|png|webp)$")

_MEDIA = {
    "jpg": "image/jpeg",
    "jpeg": "image/jpeg",
    "png": "image/png",
    "webp": "image/webp",
}


def _file_response(root, filename: str):
    if not _SAFE.match(filename):
        raise HTTPException(status_code=404, detail={"code": "not_found"})
    path = root / filename
    if not path.is_file():
        raise HTTPException(status_code=404, detail={"code": "not_found"})
    media = _MEDIA[filename.rsplit(".", 1)[-1].lower()]
    return FileResponse(path, media_type=media)


@router.get("/avatars/{filename}")
def get_avatar(filename: str):
    ensure_avatar_dir()
    return _file_response(AVATAR_ROOT, filename)


@router.get("/machines/{filename}")
def get_machine_photo(filename: str):
    ensure_machine_dir()
    return _file_response(MACHINE_ROOT, filename)
