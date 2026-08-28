import uuid
from datetime import datetime

from sqlalchemy import (
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
    Index,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


def _uuid() -> str:
    return str(uuid.uuid4())


class Organization(Base):
    __tablename__ = "organizations"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    # manufacturer | client | platform
    org_type: Mapped[str] = mapped_column(String(32), default="client")
    # Для client: производитель, который ведёт этого клиента (опционально)
    manufacturer_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("organizations.id"), nullable=True, index=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    users: Mapped[list["User"]] = relationship(back_populates="organization")
    machines: Mapped[list["Machine"]] = relationship(
        back_populates="organization",
        foreign_keys="Machine.organization_id",
    )


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    organization_id: Mapped[str] = mapped_column(ForeignKey("organizations.id"), nullable=False)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    email: Mapped[str] = mapped_column(String(255), unique=True, nullable=False, index=True)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    role: Mapped[str] = mapped_column(String(32), default="org_admin")
    # Водитель: ровно одна машина завода (NULL у admin / без привязки).
    assigned_machine_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("machines.id"), nullable=True, index=True
    )
    # Профиль (все поля опциональны)
    first_name: Mapped[str | None] = mapped_column(String(128), nullable=True)
    last_name: Mapped[str | None] = mapped_column(String(128), nullable=True)
    birth_date: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    gender: Mapped[str | None] = mapped_column(String(16), nullable=True)
    phone: Mapped[str | None] = mapped_column(String(64), nullable=True)
    about: Mapped[str | None] = mapped_column(Text, nullable=True)
    avatar_ext: Mapped[str | None] = mapped_column(String(8), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    organization: Mapped["Organization"] = relationship(back_populates="users")
    assigned_machine: Mapped["Machine | None"] = relationship(
        foreign_keys=[assigned_machine_id]
    )
    refresh_tokens: Mapped[list["RefreshToken"]] = relationship(back_populates="user")
    notification_settings: Mapped["NotificationSettings | None"] = relationship(
        back_populates="user", uselist=False
    )


class RefreshToken(Base):
    __tablename__ = "refresh_tokens"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    revoked: Mapped[bool] = mapped_column(Boolean, default=False)

    user: Mapped["User"] = relationship(back_populates="refresh_tokens")


class Device(Base):
    __tablename__ = "devices"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    device_id: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    machine_id: Mapped[str] = mapped_column(ForeignKey("machines.id"), nullable=False)
    api_key_hash: Mapped[str] = mapped_column(String(64), nullable=False)

    machine: Mapped["Machine"] = relationship(back_populates="devices")


class Machine(Base):
    __tablename__ = "machines"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    # Текущий владелец (клиент или склад производителя)
    organization_id: Mapped[str] = mapped_column(ForeignKey("organizations.id"), nullable=False)
    # Кто изготовил / продал (производитель видит проданные станции)
    manufacturer_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("organizations.id"), nullable=True, index=True
    )
    sold_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    code: Mapped[str] = mapped_column(String(32), nullable=False)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    model: Mapped[str] = mapped_column(String(128), default="")
    status: Mapped[str] = mapped_column(String(16), default="offline")
    location_label: Mapped[str] = mapped_column(String(255), default="")
    operator_name: Mapped[str] = mapped_column(String(255), default="")
    headline_alert: Mapped[str | None] = mapped_column(String(512), nullable=True)
    engine_hours: Mapped[float | None] = mapped_column(Float, nullable=True)
    # Накопленное время связи/питания блока (не сбрасывается по дням)
    uptime_hours: Mapped[float | None] = mapped_column(Float, nullable=True, default=0.0)
    # Насос: накопленное время работы и число запусков
    pump_hours: Mapped[float | None] = mapped_column(Float, nullable=True, default=0.0)
    pump_starts: Mapped[int | None] = mapped_column(Integer, nullable=True, default=0)
    pump_was_on: Mapped[bool] = mapped_column(Boolean, default=False)
    # Пороги «насос вкл» (на карточке машины)
    pump_on_pressure_bar: Mapped[float] = mapped_column(Float, default=20.0)
    pump_on_temperature_c: Mapped[float] = mapped_column(Float, default=35.0)
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    gps_lat: Mapped[float | None] = mapped_column(Float, nullable=True)
    gps_lon: Mapped[float | None] = mapped_column(Float, nullable=True)
    gps_accuracy_m: Mapped[float | None] = mapped_column(Float, nullable=True)
    last_cell_mcc: Mapped[int | None] = mapped_column(Integer, nullable=True)
    last_cell_mnc: Mapped[int | None] = mapped_column(Integer, nullable=True)
    last_cell_lac: Mapped[int | None] = mapped_column(Integer, nullable=True)
    last_cell_cid: Mapped[int | None] = mapped_column(Integer, nullable=True)
    geo_region_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    geo_center_lat: Mapped[float | None] = mapped_column(Float, nullable=True)
    geo_center_lon: Mapped[float | None] = mapped_column(Float, nullable=True)
    geo_radius_m: Mapped[float | None] = mapped_column(Float, nullable=True)
    geo_fence_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    geo_last_inside: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    bluetooth_status: Mapped[str] = mapped_column(String(16), default="disconnected")
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    photo_ext: Mapped[str | None] = mapped_column(String(8), nullable=True)

    organization: Mapped["Organization"] = relationship(
        back_populates="machines",
        foreign_keys=[organization_id],
    )
    sensors: Mapped[list["Sensor"]] = relationship(back_populates="machine")
    readings: Mapped[list["Reading"]] = relationship(back_populates="machine")
    devices: Mapped[list["Device"]] = relationship(back_populates="machine")
    events: Mapped[list["Event"]] = relationship(back_populates="machine")
    track_points: Mapped[list["MachineGpsPoint"]] = relationship(back_populates="machine")
    geofence: Mapped["MachineGeofence | None"] = relationship(
        back_populates="machine", uselist=False
    )


class Sensor(Base):
    __tablename__ = "sensors"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    machine_id: Mapped[str] = mapped_column(ForeignKey("machines.id"), nullable=False, index=True)
    name: Mapped[str] = mapped_column(String(128), nullable=False)
    type: Mapped[str] = mapped_column(String(32), nullable=False)
    unit: Mapped[str] = mapped_column(String(16), default="")
    scale_min: Mapped[float] = mapped_column(Float, default=0)
    scale_max: Mapped[float] = mapped_column(Float, default=100)
    norm_min: Mapped[float | None] = mapped_column(Float, nullable=True)
    norm_max: Mapped[float] = mapped_column(Float, default=100)
    warn_high: Mapped[float | None] = mapped_column(Float, nullable=True)
    critical_high: Mapped[float] = mapped_column(Float, default=999)
    critical_low: Mapped[float | None] = mapped_column(Float, nullable=True)
    # Поле channel_index используется для корректного отображения во Flutter
    channel_index: Mapped[int] = mapped_column(Integer, default=0)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    last_value: Mapped[float | None] = mapped_column(Float, nullable=True)
    last_ts: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    last_status: Mapped[str | None] = mapped_column(String(16), nullable=True)
    last_fault: Mapped[str | None] = mapped_column(String(16), nullable=True)
    last_current_ma: Mapped[float | None] = mapped_column(Float, nullable=True)

    machine: Mapped["Machine"] = relationship(back_populates="sensors")
    readings: Mapped[list["Reading"]] = relationship(back_populates="sensor")


class Reading(Base):
    __tablename__ = "readings"
    
    # ─── СОСТАВНОЙ ИНДЕКС ДЛЯ МОЛНИЕНОСНЫХ ГРАФИКОВ ───────────────────
    __table_args__ = (
        Index("ix_readings_sensor_id_ts", "sensor_id", "ts"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    machine_id: Mapped[str] = mapped_column(ForeignKey("machines.id"), nullable=False, index=True)
    
    # Здесь index=True можно оставить или убрать, составной индекс покроет основные запросы
    sensor_id: Mapped[str] = mapped_column(ForeignKey("sensors.id"), nullable=False) 
    ts: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    
    value: Mapped[float] = mapped_column(Float, nullable=False)
    status: Mapped[str] = mapped_column(String(16), default="ok")

    machine: Mapped["Machine"] = relationship(back_populates="readings")
    sensor: Mapped["Sensor"] = relationship(back_populates="readings")


class ReadingHourly(Base):
    """Часовые агрегаты для истории до 6 месяцев."""

    __tablename__ = "readings_hourly"
    __table_args__ = (
        UniqueConstraint(
            "sensor_id", "period", name="uq_readings_hourly_sensor_period"
        ),
        Index("ix_readings_hourly_sensor_period", "sensor_id", "period"),
        Index("ix_readings_hourly_machine_period", "machine_id", "period"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    machine_id: Mapped[str] = mapped_column(String(36), nullable=False, index=True)
    sensor_id: Mapped[str] = mapped_column(String(36), nullable=False)
    period: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    avg_value: Mapped[float] = mapped_column(Float, nullable=False)
    min_value: Mapped[float] = mapped_column(Float, nullable=False)
    max_value: Mapped[float] = mapped_column(Float, nullable=False)
    samples: Mapped[int] = mapped_column(Integer, default=0)
    status: Mapped[str] = mapped_column(String(16), default="ok")


class ReadingDaily(Base):
    """Суточные агрегаты для длинных отчётов (до 6 месяцев)."""

    __tablename__ = "readings_daily"
    __table_args__ = (
        UniqueConstraint(
            "sensor_id", "period", name="uq_readings_daily_sensor_period"
        ),
        Index("ix_readings_daily_sensor_period", "sensor_id", "period"),
        Index("ix_readings_daily_machine_period", "machine_id", "period"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    machine_id: Mapped[str] = mapped_column(String(36), nullable=False, index=True)
    sensor_id: Mapped[str] = mapped_column(String(36), nullable=False)
    period: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    avg_value: Mapped[float] = mapped_column(Float, nullable=False)
    min_value: Mapped[float] = mapped_column(Float, nullable=False)
    max_value: Mapped[float] = mapped_column(Float, nullable=False)
    samples: Mapped[int] = mapped_column(Integer, default=0)
    status: Mapped[str] = mapped_column(String(16), default="ok")


class IngestDedup(Base):
    __tablename__ = "ingest_dedup"
    __table_args__ = (UniqueConstraint("message_id", name="uq_message_id"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    message_id: Mapped[str] = mapped_column(String(36), nullable=False)
    received_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class CellTowerCache(Base):
    """Координаты вышки, выученные по GNSS или ручной точке (бесплатно)."""

    __tablename__ = "cell_tower_cache"
    __table_args__ = (
        UniqueConstraint("mcc", "mnc", "lac", "cid", name="uq_cell_tower"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    mcc: Mapped[int] = mapped_column(Integer, nullable=False)
    mnc: Mapped[int] = mapped_column(Integer, nullable=False)
    lac: Mapped[int] = mapped_column(Integer, nullable=False)
    cid: Mapped[int] = mapped_column(Integer, nullable=False)
    lat: Mapped[float] = mapped_column(Float, nullable=False)
    lon: Mapped[float] = mapped_column(Float, nullable=False)
    accuracy_m: Mapped[float | None] = mapped_column(Float, nullable=True)
    source: Mapped[str] = mapped_column(String(16), default="gnss")
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow
    )


class MachineGpsPoint(Base):
    __tablename__ = "machine_gps_points"
    __table_args__ = (
        Index("ix_machine_gps_points_machine_ts", "machine_id", "ts"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    machine_id: Mapped[str] = mapped_column(
        ForeignKey("machines.id"), nullable=False, index=True
    )
    ts: Mapped[datetime] = mapped_column(DateTime, nullable=False, index=True)
    lat: Mapped[float] = mapped_column(Float, nullable=False)
    lon: Mapped[float] = mapped_column(Float, nullable=False)
    accuracy_m: Mapped[float | None] = mapped_column(Float, nullable=True)
    source: Mapped[str] = mapped_column(String(32), default="ingest")

    machine: Mapped["Machine"] = relationship(back_populates="track_points")


class MachineGeofence(Base):
    __tablename__ = "machine_geofences"
    __table_args__ = (
        UniqueConstraint("machine_id", name="uq_machine_geofence_machine_id"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    machine_id: Mapped[str] = mapped_column(ForeignKey("machines.id"), nullable=False)
    name: Mapped[str] = mapped_column(String(255), default="")
    center_lat: Mapped[float] = mapped_column(Float, nullable=False)
    center_lon: Mapped[float] = mapped_column(Float, nullable=False)
    radius_m: Mapped[float] = mapped_column(Float, nullable=False)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow
    )

    machine: Mapped["Machine"] = relationship(back_populates="geofence")


class Event(Base):
    __tablename__ = "events"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    machine_id: Mapped[str] = mapped_column(ForeignKey("machines.id"), nullable=False, index=True)
    sensor_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    type: Mapped[str] = mapped_column(String(64), nullable=False)
    severity: Mapped[str] = mapped_column(String(16), default="info")
    message: Mapped[str] = mapped_column(Text, default="")
    ts: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)
    acknowledged: Mapped[bool] = mapped_column(Boolean, default=False)

    machine: Mapped["Machine"] = relationship(back_populates="events")


class NotificationSettings(Base):
    __tablename__ = "notification_settings"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), unique=True, nullable=False)
    # Аварии (critical): пуш, СМС, почта, Telegram по умолчанию.
    critical_push: Mapped[bool] = mapped_column(Boolean, default=True)
    critical_sound: Mapped[bool] = mapped_column(Boolean, default=True)
    critical_vibration: Mapped[bool] = mapped_column(Boolean, default=True)
    critical_sms: Mapped[bool] = mapped_column(Boolean, default=True)
    critical_email: Mapped[bool] = mapped_column(Boolean, default=True)
    critical_telegram: Mapped[bool] = mapped_column(Boolean, default=True)
    critical_phone: Mapped[bool] = mapped_column(Boolean, default=False)  # устарело
    # Предупреждения только в журнал — каналы оповещения выключены.
    warning_push: Mapped[bool] = mapped_column(Boolean, default=False)
    warning_sound: Mapped[bool] = mapped_column(Boolean, default=False)
    warning_vibration: Mapped[bool] = mapped_column(Boolean, default=False)
    warning_sms: Mapped[bool] = mapped_column(Boolean, default=False)
    warning_email: Mapped[bool] = mapped_column(Boolean, default=False)
    warning_telegram: Mapped[bool] = mapped_column(Boolean, default=False)
    warning_phone: Mapped[bool] = mapped_column(Boolean, default=False)
    alert_email_to: Mapped[str | None] = mapped_column(String(255), nullable=True)
    alert_telegram_chat: Mapped[str | None] = mapped_column(String(255), nullable=True)
    alert_sms_phone: Mapped[str | None] = mapped_column(String(32), nullable=True)
    quiet_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    quiet_from: Mapped[str] = mapped_column(String(8), default="22:00")
    quiet_to: Mapped[str] = mapped_column(String(8), default="08:00")

    user: Mapped["User"] = relationship(back_populates="notification_settings")


class TelegramChatBinding(Base):
    """Связка @username → chat_id после /start боту."""

    __tablename__ = "telegram_chat_bindings"
    __table_args__ = (
        UniqueConstraint("username", name="uq_telegram_username"),
        Index("ix_telegram_chat_bindings_chat_id", "chat_id"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    username: Mapped[str] = mapped_column(String(64), nullable=False)
    chat_id: Mapped[str] = mapped_column(String(64), nullable=False)
    display_name: Mapped[str | None] = mapped_column(String(128), nullable=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow
    )


class AuditLog(Base):
    """Журнал безопасности и действий: входы, смена настроек, подтверждения."""

    __tablename__ = "audit_logs"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    organization_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("organizations.id"), nullable=True, index=True
    )
    user_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("users.id"), nullable=True, index=True
    )
    actor_email: Mapped[str | None] = mapped_column(String(255), nullable=True)
    action: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    severity: Mapped[str] = mapped_column(String(16), default="info")
    message: Mapped[str] = mapped_column(Text, default="")
    ts: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)