from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.deps import get_current_user, user_to_json
from app.models import Organization, RefreshToken, User
from app.password_policy import validate_password
from app.rate_limit import enforce_rate_limit
from app.security import (
    create_access_token,
    hash_password,
    hash_token,
    verify_password,
)
from app.roles import ROLE_ORG_ADMIN
from app.seed import revoke_refresh_token, store_refresh_token

router = APIRouter(prefix="/auth", tags=["auth"])


class RegisterRequest(BaseModel):
    name: str
    email: EmailStr
    password: str = Field(min_length=10, max_length=72)
    organization_name: str
    terms_accepted: bool


class LoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(max_length=72)


class RefreshRequest(BaseModel):
    refresh_token: str


class ChangePasswordRequest(BaseModel):
    old_password: str = Field(min_length=1, max_length=72)
    new_password: str = Field(min_length=10, max_length=72)


def _tokens_response(db: Session, user: User) -> dict:
    access, expires_in = create_access_token(user.id, user.organization_id, user.role)
    refresh = store_refresh_token(db, user.id)
    org = db.get(Organization, user.organization_id)
    return {
        "access_token": access,
        "refresh_token": refresh,
        "expires_in": expires_in,
        "user": user_to_json(user, org),
    }


def _auth_limit(request: Request, *, email: str | None = None) -> None:
    enforce_rate_limit(
        request,
        scope="auth",
        limit=settings.auth_rate_limit,
        window_seconds=settings.auth_rate_window_seconds,
        extra_key=email,
    )


@router.post("/register", status_code=status.HTTP_201_CREATED)
def register(body: RegisterRequest, request: Request, db: Session = Depends(get_db)):
    if not settings.allow_public_register:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": "registration_disabled",
                "message": "Публичная регистрация отключена. Обратитесь к администратору.",
            },
        )
    _auth_limit(request, email=body.email)
    if not body.terms_accepted:
        raise HTTPException(
            status_code=400,
            detail={"code": "terms_required", "message": "Необходимо принять условия"},
        )
    validate_password(body.password)
    if db.query(User).filter(User.email == body.email.lower()).first():
        raise HTTPException(
            status_code=400,
            detail={"code": "email_exists", "message": "Email уже зарегистрирован"},
        )

    org = Organization(name=body.organization_name, org_type="client")
    db.add(org)
    db.flush()

    user = User(
        organization_id=org.id,
        name=body.name,
        email=body.email.lower(),
        password_hash=hash_password(body.password),
        role=ROLE_ORG_ADMIN,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return _tokens_response(db, user)


@router.post("/login")
def login(body: LoginRequest, request: Request, db: Session = Depends(get_db)):
    _auth_limit(request, email=body.email)
    email = body.email.lower()
    user = db.query(User).filter(User.email == email).first()
    if user is None or not verify_password(body.password, user.password_hash):
        from app.audit import write_audit

        write_audit(
            db,
            action="auth.login_failed",
            message=f"Неудачный вход: {email}",
            actor_email=email,
            organization_id=user.organization_id if user is not None else None,
            user=None,
            severity="warning",
            commit=True,
        )
        raise HTTPException(
            status_code=401,
            detail={"code": "invalid_credentials", "message": "Неверный email или пароль"},
        )
    from app.audit import write_audit

    write_audit(
        db,
        action="auth.login",
        message=f"Вход в систему: {user.name} ({user.email})",
        user=user,
        severity="info",
    )
    return _tokens_response(db, user)


@router.post("/refresh")
def refresh(body: RefreshRequest, request: Request, db: Session = Depends(get_db)):
    _auth_limit(request)
    token_hash = hash_token(body.refresh_token)
    row = (
        db.query(RefreshToken)
        .filter(RefreshToken.token_hash == token_hash, RefreshToken.revoked.is_(False))
        .first()
    )
    if row is None or row.expires_at < datetime.utcnow():
        raise HTTPException(
            status_code=401,
            detail={"code": "invalid_refresh", "message": "Refresh token недействителен"},
        )
    user = db.get(User, row.user_id)
    if user is None:
        raise HTTPException(
            status_code=401,
            detail={"code": "unauthorized", "message": "Пользователь не найден"},
        )
    row.revoked = True
    db.commit()
    return _tokens_response(db, user)


@router.post("/change-password")
def change_password(
    body: ChangePasswordRequest,
    request: Request,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Любой авторизованный пользователь меняет свой пароль (старый + новый)."""
    _auth_limit(request, email=user.email)
    if not verify_password(body.old_password, user.password_hash):
        raise HTTPException(
            status_code=400,
            detail={
                "code": "wrong_password",
                "message": "Неверный текущий пароль",
            },
        )
    if body.old_password == body.new_password:
        raise HTTPException(
            status_code=400,
            detail={
                "code": "same_password",
                "message": "Новый пароль должен отличаться от текущего",
            },
        )
    validate_password(body.new_password)
    user.password_hash = hash_password(body.new_password)
    db.commit()
    from app.audit import write_audit

    write_audit(
        db,
        action="auth.password_changed",
        message=f"Смена пароля: {user.name} ({user.email})",
        user=user,
        severity="info",
        commit=True,
    )
    return {"ok": True}


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(
    body: RefreshRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    revoke_refresh_token(db, body.refresh_token)
    db.query(RefreshToken).filter(
        RefreshToken.user_id == user.id,
        RefreshToken.revoked.is_(False),
    ).update({"revoked": True})
    db.commit()
    return None
