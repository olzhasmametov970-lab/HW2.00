"""Раздача загруженных файлов (аватары, фото станков) — только с JWT."""

from __future__ import annotations

import re

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from app.avatar_storage import UPLOAD_ROOT as AVATAR_ROOT
from app.avatar_storage import ensure_upload_dir as ensure_avatar_dir
from app.database import get_db
from app.deps import get_current_user
from app.machine_photo_storage import UPLOAD_ROOT as MACHINE_ROOT
from app.machine_photo_storage import ensure_upload_dir as ensure_machine_dir
from app.models import Machine, User
from app.org_access import can_view_machine, get_user_org, is_platform_org

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


def _subject_id(filename: str) -> str:
    return filename.rsplit(".", 1)[0]


@router.get("/avatars/{filename}")
def get_avatar(
    filename: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    ensure_avatar_dir()
    if not _SAFE.match(filename):
        raise HTTPException(status_code=404, detail={"code": "not_found"})
    subject_id = _subject_id(filename)
    subject = db.get(User, subject_id)
    if subject is None:
        raise HTTPException(status_code=404, detail={"code": "not_found"})
    org = get_user_org(db, user)
    if (
        subject.id != user.id
        and not is_platform_org(org)
        and subject.organization_id != user.organization_id
    ):
        raise HTTPException(status_code=404, detail={"code": "not_found"})
    return _file_response(AVATAR_ROOT, filename)


@router.get("/machines/{filename}")
def get_machine_photo(
    filename: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    ensure_machine_dir()
    if not _SAFE.match(filename):
        raise HTTPException(status_code=404, detail={"code": "not_found"})
    machine_id = _subject_id(filename)
    machine = db.get(Machine, machine_id)
    if machine is None or not can_view_machine(db, user, machine):
        raise HTTPException(status_code=404, detail={"code": "not_found"})
    return _file_response(MACHINE_ROOT, filename)
