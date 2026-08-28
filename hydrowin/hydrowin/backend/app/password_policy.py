"""Password complexity rules."""

from __future__ import annotations

import re

from fastapi import HTTPException, status

_MIN_LEN = 10
_MAX_LEN = 72
_HAS_LETTER = re.compile(r"[A-Za-zА-Яа-яЁё]")
_HAS_DIGIT = re.compile(r"\d")
_HAS_SPECIAL = re.compile(r"[^A-Za-zА-Яа-яЁё0-9]")


def validate_password(password: str) -> None:
    if len(password) < _MIN_LEN:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={
                "code": "weak_password",
                "message": f"Пароль должен быть не короче {_MIN_LEN} символов",
            },
        )
    if len(password) > _MAX_LEN:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={
                "code": "weak_password",
                "message": f"Пароль слишком длинный (макс. {_MAX_LEN})",
            },
        )
    if (
        not _HAS_LETTER.search(password)
        or not _HAS_DIGIT.search(password)
        or not _HAS_SPECIAL.search(password)
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={
                "code": "weak_password",
                "message": "Пароль: буквы, цифры и спецсимвол",
            },
        )
