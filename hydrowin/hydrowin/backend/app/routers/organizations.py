from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import FileResponse
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy.orm import Session

from app.avatar_storage import (
    avatar_path,
    delete_avatar,
    ensure_upload_dir,
    save_avatar_base64,
)
from app.database import get_db
from app.deps import (
    get_current_user,
    is_admin,
    org_to_json,
    require_admin,
    require_staff,
    user_to_json,
)
from app.models import Machine, NotificationSettings, Organization, User
from app.org_access import get_user_org, is_manufacturer_org, is_platform_org
from app.org_types import ORG_TYPE_CLIENT, ORG_TYPE_MANUFACTURER, ORG_TYPE_PLATFORM
from app.password_policy import validate_password
from app.purge import purge_organization, purge_user
from app.roles import CREATABLE_ROLES, ROLE_DRIVER, ROLE_ORG_ADMIN
from app.security import hash_password

router = APIRouter(prefix="/orgs", tags=["organizations"])

_GENDERS = frozenset({"", "male", "female", "other"})


class UpdateProfileRequest(BaseModel):
    first_name: str | None = Field(default=None, max_length=128)
    last_name: str | None = Field(default=None, max_length=128)
    birth_date: str | None = Field(
        default=None, description="YYYY-MM-DD или пусто"
    )
    gender: str | None = Field(default=None, max_length=16)
    phone: str | None = Field(default=None, max_length=64)
    about: str | None = Field(default=None, max_length=2000)
    # data:image/...;base64,... или null чтобы удалить
    avatar_base64: str | None = None
    clear_avatar: bool = False


class CreateClientOrgRequest(BaseModel):
    name: str = Field(min_length=2, max_length=255)
    admin_name: str = Field(min_length=2, max_length=255)
    admin_email: EmailStr
    admin_password: str = Field(min_length=10, max_length=72)
    # Только для админа платформы: под каким производителем создать завод.
    manufacturer_organization_id: str | None = Field(
        default=None, min_length=36, max_length=36
    )


class CreateManufacturerRequest(BaseModel):
    name: str = Field(min_length=2, max_length=255)
    admin_name: str = Field(min_length=2, max_length=255)
    admin_email: EmailStr
    admin_password: str = Field(min_length=10, max_length=72)


class CreateUserRequest(BaseModel):
    name: str = Field(min_length=2, max_length=255)
    email: EmailStr
    password: str = Field(min_length=10, max_length=72)
    role: str = Field(default=ROLE_ORG_ADMIN)
    # Обязательно для role=driver: машина того же завода.
    assigned_machine_id: str | None = Field(
        default=None, min_length=36, max_length=36
    )


class AssignMachineRequest(BaseModel):
    assigned_machine_id: str = Field(min_length=36, max_length=36)


def _apply_display_name(user: User) -> None:
    first = (user.first_name or "").strip()
    last = (user.last_name or "").strip()
    if first or last:
        user.name = f"{first} {last}".strip()


@router.get("/me")
def get_my_org(
    user: User = Depends(require_staff),
    db: Session = Depends(get_db),
):
    org = get_user_org(db, user)
    if org is None:
        raise HTTPException(status_code=404, detail={"code": "not_found", "message": "Организация не найдена"})
    return {
        "organization": org_to_json(org),
        "user": user_to_json(user, org),
        "is_manufacturer": is_manufacturer_org(org),
        "is_platform": is_platform_org(org),
        "is_client": org.org_type == ORG_TYPE_CLIENT,
    }


@router.put("/me/profile")
def update_my_profile(
    body: UpdateProfileRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Любой авторизованный пользователь редактирует свой профиль."""
    if body.first_name is not None:
        user.first_name = body.first_name.strip() or None
    if body.last_name is not None:
        user.last_name = body.last_name.strip() or None
    if body.phone is not None:
        user.phone = body.phone.strip() or None
    if body.about is not None:
        user.about = body.about.strip() or None
    if body.gender is not None:
        gender = body.gender.strip().lower()
        if gender not in _GENDERS:
            raise HTTPException(
                status_code=400,
                detail={
                    "code": "bad_request",
                    "message": "Пол: male, female, other или пусто",
                },
            )
        user.gender = gender or None
    if body.birth_date is not None:
        raw = body.birth_date.strip()
        if not raw:
            user.birth_date = None
        else:
            try:
                user.birth_date = datetime.strptime(raw[:10], "%Y-%m-%d")
            except ValueError as exc:
                raise HTTPException(
                    status_code=400,
                    detail={
                        "code": "bad_request",
                        "message": "Дата рождения: ГГГГ-ММ-ДД",
                    },
                ) from exc

    if body.clear_avatar:
        delete_avatar(user.id)
        user.avatar_ext = None
    elif body.avatar_base64:
        try:
            user.avatar_ext = save_avatar_base64(user.id, body.avatar_base64)
        except ValueError as exc:
            raise HTTPException(
                status_code=400,
                detail={"code": "bad_request", "message": str(exc)},
            ) from exc

    _apply_display_name(user)
    db.commit()
    db.refresh(user)
    org = get_user_org(db, user)
    return user_to_json(user, org)


@router.get("/manufacturers")
def list_manufacturers(
    user: User = Depends(require_staff),
    db: Session = Depends(get_db),
):
    """Список производителей — для админа платформы."""
    org = get_user_org(db, user)
    if not is_platform_org(org):
        raise HTTPException(
            status_code=403,
            detail={"code": "forbidden", "message": "Только для админа платформы"},
        )
    makers = (
        db.query(Organization)
        .filter(Organization.org_type == ORG_TYPE_MANUFACTURER)
        .order_by(Organization.name)
        .all()
    )
    return {"items": [org_to_json(m) for m in makers]}


@router.post("/manufacturers", status_code=201)
def create_manufacturer(
    body: CreateManufacturerRequest,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Админ платформы создаёт организацию-производителя и её администратора."""
    org = get_user_org(db, user)
    if not is_platform_org(org):
        raise HTTPException(
            status_code=403,
            detail={"code": "forbidden", "message": "Только админ платформы может создавать производителей"},
        )

    if db.query(User).filter(User.email == body.admin_email.lower()).first():
        raise HTTPException(
            status_code=400,
            detail={"code": "email_exists", "message": "Email админа уже занят"},
        )
    validate_password(body.admin_password)

    maker = Organization(
        name=body.name.strip(),
        org_type=ORG_TYPE_MANUFACTURER,
        manufacturer_id=None,
    )
    db.add(maker)
    db.flush()

    admin = User(
        organization_id=maker.id,
        name=body.admin_name.strip(),
        email=body.admin_email.lower(),
        password_hash=hash_password(body.admin_password),
        role=ROLE_ORG_ADMIN,
    )
    db.add(admin)
    db.flush()
    db.add(NotificationSettings(user_id=admin.id))

    db.commit()
    db.refresh(maker)
    return {
        "organization": org_to_json(maker),
        "admin": user_to_json(admin, maker),
    }


@router.get("/clients")
def list_client_orgs(
    manufacturer_organization_id: str | None = Query(
        default=None, min_length=36, max_length=36
    ),
    user: User = Depends(require_staff),
    db: Session = Depends(get_db),
):
    """Клиенты-заводы.

    - Производитель: свои заводы.
    - Платформа: все заводы, либо только у указанного manufacturer_organization_id.
    """
    org = get_user_org(db, user)
    q = db.query(Organization).filter(Organization.org_type == ORG_TYPE_CLIENT)

    if is_manufacturer_org(org):
        q = q.filter(Organization.manufacturer_id == org.id)
    elif is_platform_org(org):
        if manufacturer_organization_id:
            maker = db.get(Organization, manufacturer_organization_id)
            if maker is None or maker.org_type != ORG_TYPE_MANUFACTURER:
                raise HTTPException(
                    status_code=400,
                    detail={
                        "code": "bad_request",
                        "message": "Укажите организацию-производителя",
                    },
                )
            q = q.filter(
                Organization.manufacturer_id == manufacturer_organization_id
            )
    else:
        raise HTTPException(
            status_code=403,
            detail={
                "code": "forbidden",
                "message": "Только для производителя или админа платформы",
            },
        )

    clients = q.order_by(Organization.name).all()
    return {"items": [org_to_json(c) for c in clients]}


@router.post("/clients", status_code=201)
def create_client_org(
    body: CreateClientOrgRequest,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Производитель или админ платформы создаёт завод и его администратора."""
    org = get_user_org(db, user)
    maker_id: str | None = None
    if is_manufacturer_org(org):
        maker_id = org.id
    elif is_platform_org(org):
        maker_id = body.manufacturer_organization_id
        if not maker_id:
            raise HTTPException(
                status_code=400,
                detail={
                    "code": "bad_request",
                    "message": "Укажите manufacturer_organization_id",
                },
            )
        maker = db.get(Organization, maker_id)
        if maker is None or maker.org_type != ORG_TYPE_MANUFACTURER:
            raise HTTPException(
                status_code=400,
                detail={
                    "code": "bad_request",
                    "message": "Укажите организацию-производителя",
                },
            )
    else:
        raise HTTPException(
            status_code=403,
            detail={
                "code": "forbidden",
                "message": "Только производитель или админ платформы может создавать заводы",
            },
        )

    if db.query(User).filter(User.email == body.admin_email.lower()).first():
        raise HTTPException(
            status_code=400,
            detail={"code": "email_exists", "message": "Email админа уже занят"},
        )
    validate_password(body.admin_password)

    client = Organization(
        name=body.name.strip(),
        org_type=ORG_TYPE_CLIENT,
        manufacturer_id=maker_id,
    )
    db.add(client)
    db.flush()

    admin = User(
        organization_id=client.id,
        name=body.admin_name.strip(),
        email=body.admin_email.lower(),
        password_hash=hash_password(body.admin_password),
        role=ROLE_ORG_ADMIN,
    )
    db.add(admin)
    db.flush()
    db.add(NotificationSettings(user_id=admin.id))

    db.commit()
    db.refresh(client)
    return {
        "organization": org_to_json(client),
        "admin": user_to_json(admin, client),
    }


@router.post("/users", status_code=201)
def create_org_user(
    body: CreateUserRequest,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """
    Создать пользователя:
    - админ завода → водитель своей организации;
    - админ платформы → водитель любого завода (по машине).
    """
    role = (body.role or ROLE_ORG_ADMIN).strip().lower()
    if role not in CREATABLE_ROLES:
        raise HTTPException(
            status_code=400,
            detail={
                "code": "bad_request",
                "message": f"Допустимые роли: {', '.join(CREATABLE_ROLES)}",
            },
        )

    actor_org = get_user_org(db, user)
    if actor_org is None:
        raise HTTPException(
            status_code=404,
            detail={"code": "not_found", "message": "Организация не найдена"},
        )

    is_platform = is_platform_org(actor_org)
    is_factory = actor_org.org_type == ORG_TYPE_CLIENT

    if role == ROLE_ORG_ADMIN:
        raise HTTPException(
            status_code=400,
            detail={
                "code": "bad_request",
                "message": "Админов создавайте через производителя или завод",
            },
        )

    if role != ROLE_DRIVER:
        raise HTTPException(
            status_code=400,
            detail={
                "code": "bad_request",
                "message": "Через этот метод создаётся только роль driver",
            },
        )

    if not is_platform and not is_factory:
        raise HTTPException(
            status_code=403,
            detail={
                "code": "forbidden",
                "message": "Водителя создаёт админ завода или админ платформы",
            },
        )

    mid = (body.assigned_machine_id or "").strip()
    if not mid:
        raise HTTPException(
            status_code=400,
            detail={
                "code": "bad_request",
                "message": "Для водителя укажите assigned_machine_id",
            },
        )
    machine = db.get(Machine, mid)
    if machine is None:
        raise HTTPException(
            status_code=400,
            detail={"code": "bad_request", "message": "Машина не найдена"},
        )

    factory = db.get(Organization, machine.organization_id)
    if factory is None or factory.org_type != ORG_TYPE_CLIENT:
        raise HTTPException(
            status_code=400,
            detail={
                "code": "bad_request",
                "message": "Водителя можно привязать только к машине завода",
            },
        )

    if is_factory and machine.organization_id != user.organization_id:
        raise HTTPException(
            status_code=400,
            detail={
                "code": "bad_request",
                "message": "Машина не найдена в вашем заводе",
            },
        )

    target_org = factory
    assigned_machine_id = machine.id

    validate_password(body.password)
    if db.query(User).filter(User.email == body.email.lower()).first():
        raise HTTPException(
            status_code=400,
            detail={"code": "email_exists", "message": "Email уже занят"},
        )

    new_user = User(
        organization_id=target_org.id,
        name=body.name.strip(),
        email=body.email.lower(),
        password_hash=hash_password(body.password),
        role=role,
        assigned_machine_id=assigned_machine_id,
    )
    db.add(new_user)
    db.flush()
    db.add(NotificationSettings(user_id=new_user.id))
    db.commit()
    db.refresh(new_user)
    return user_to_json(new_user, target_org)


@router.post("/users/{user_id}/assign-machine")
def assign_driver_machine(
    user_id: str,
    body: AssignMachineRequest,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Админ завода меняет привязку водителя к машине."""
    org = get_user_org(db, user)
    if org is None or org.org_type != ORG_TYPE_CLIENT:
        raise HTTPException(
            status_code=403,
            detail={
                "code": "forbidden",
                "message": "Только админ завода может назначать машину водителю",
            },
        )

    target = db.get(User, user_id)
    if target is None or target.organization_id != user.organization_id:
        raise HTTPException(
            status_code=404,
            detail={"code": "not_found", "message": "Пользователь не найден"},
        )
    if target.role != ROLE_DRIVER:
        raise HTTPException(
            status_code=400,
            detail={
                "code": "bad_request",
                "message": "Назначение машины только для роли driver",
            },
        )

    machine = db.get(Machine, body.assigned_machine_id.strip())
    if machine is None or machine.organization_id != user.organization_id:
        raise HTTPException(
            status_code=400,
            detail={
                "code": "bad_request",
                "message": "Машина не найдена в вашем заводе",
            },
        )

    target.assigned_machine_id = machine.id
    db.commit()
    db.refresh(target)
    return user_to_json(target, org)


def _users_json_for_orgs(db: Session, org_ids: list[str]) -> list[dict]:
    if not org_ids:
        return []
    orgs = {
        o.id: o
        for o in db.query(Organization).filter(Organization.id.in_(org_ids)).all()
    }
    users = (
        db.query(User)
        .filter(User.organization_id.in_(org_ids))
        .order_by(User.name)
        .all()
    )
    machine_ids = [u.assigned_machine_id for u in users if u.assigned_machine_id]
    machines: dict[str, Machine] = {}
    if machine_ids:
        machines = {
            m.id: m
            for m in db.query(Machine).filter(Machine.id.in_(machine_ids)).all()
        }
    return [
        user_to_json(
            u,
            orgs.get(u.organization_id),
            machine=machines.get(u.assigned_machine_id)
            if u.assigned_machine_id
            else None,
        )
        for u in users
    ]


def _can_manage_user(actor_org: Organization, target: User, db: Session) -> bool:
    if target.organization_id == actor_org.id:
        return True
    target_org = db.get(Organization, target.organization_id)
    if target_org is None:
        return False
    if actor_org.org_type == ORG_TYPE_PLATFORM:
        return target_org.org_type == ORG_TYPE_CLIENT
    if actor_org.org_type == ORG_TYPE_MANUFACTURER:
        return (
            target_org.org_type == ORG_TYPE_CLIENT
            and target_org.manufacturer_id == actor_org.id
        )
    return False


@router.get("/users")
def list_org_users(
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Список пользователей.

    - Завод (client): только своя организация.
    - Производитель: пользователи своих заводов-клиентов.
    - Платформа: свои пользователи + все заводы (client) с водителями/админами.
    """
    org = get_user_org(db, user)
    if org is None:
        return {"items": []}

    if org.org_type == ORG_TYPE_PLATFORM:
        client_ids = [
            o.id
            for o in db.query(Organization)
            .filter(Organization.org_type == ORG_TYPE_CLIENT)
            .order_by(Organization.name)
            .all()
        ]
        return {"items": _users_json_for_orgs(db, [org.id, *client_ids])}

    if org.org_type == ORG_TYPE_MANUFACTURER:
        client_ids = [
            o.id
            for o in db.query(Organization)
            .filter(
                Organization.org_type == ORG_TYPE_CLIENT,
                Organization.manufacturer_id == org.id,
            )
            .order_by(Organization.name)
            .all()
        ]
        return {"items": _users_json_for_orgs(db, client_ids)}

    return {"items": _users_json_for_orgs(db, [org.id])}


@router.delete("/users/{user_id}")
def delete_org_user(
    user_id: str,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Админ удаляет пользователя своей org или завода в зоне ответственности."""
    if user_id == user.id:
        raise HTTPException(
            status_code=400,
            detail={
                "code": "bad_request",
                "message": "Нельзя удалить свою учётную запись",
            },
        )

    actor_org = get_user_org(db, user)
    target = db.get(User, user_id)
    if (
        actor_org is None
        or target is None
        or not _can_manage_user(actor_org, target, db)
    ):
        raise HTTPException(
            status_code=404,
            detail={"code": "not_found", "message": "Пользователь не найден"},
        )

    purge_user(db, target)
    db.commit()
    return {"deleted": True, "id": user_id}


@router.delete("/{org_id}")
def delete_organization(
    org_id: str,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """
    Админ платформы удаляет организацию каскадом:
    клиенты производителя → пользователи → машины (история) → орг.
    """
    actor_org = get_user_org(db, user)
    if not is_platform_org(actor_org):
        raise HTTPException(
            status_code=403,
            detail={
                "code": "forbidden",
                "message": "Удалять организации может только админ платформы",
            },
        )

    target = db.get(Organization, org_id)
    if target is None:
        raise HTTPException(
            status_code=404,
            detail={"code": "not_found", "message": "Организация не найдена"},
        )
    if target.org_type == ORG_TYPE_PLATFORM:
        raise HTTPException(
            status_code=400,
            detail={
                "code": "bad_request",
                "message": "Платформенную организацию удалить нельзя",
            },
        )
    if target.id == actor_org.id:
        raise HTTPException(
            status_code=400,
            detail={
                "code": "bad_request",
                "message": "Нельзя удалить свою организацию",
            },
        )

    stats = purge_organization(db, target)
    db.commit()
    return {"deleted": True, "id": org_id, **stats}
