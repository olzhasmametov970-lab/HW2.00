"""Миграция схемы без Alembic: безопасные ALTER TABLE IF NOT EXISTS."""

from sqlalchemy import text
from sqlalchemy.engine import Engine


def apply_org_schema(engine: Engine) -> list[str]:
    """Добавляет колонки multi-tenant (org type, manufacturer links)."""
    statements = [
        # organizations
        """
        ALTER TABLE organizations
        ADD COLUMN IF NOT EXISTS org_type VARCHAR(32) NOT NULL DEFAULT 'client'
        """,
        """
        ALTER TABLE organizations
        ADD COLUMN IF NOT EXISTS manufacturer_id VARCHAR(36) NULL
        """,
        # machines
        """
        ALTER TABLE machines
        ADD COLUMN IF NOT EXISTS manufacturer_id VARCHAR(36) NULL
        """,
        """
        ALTER TABLE machines
        ADD COLUMN IF NOT EXISTS sold_at TIMESTAMP NULL
        """,
        """
        ALTER TABLE machines
        ADD COLUMN IF NOT EXISTS uptime_hours DOUBLE PRECISION NULL DEFAULT 0
        """,
        """
        ALTER TABLE machines
        ADD COLUMN IF NOT EXISTS pump_hours DOUBLE PRECISION NULL DEFAULT 0
        """,
        """
        ALTER TABLE machines
        ADD COLUMN IF NOT EXISTS pump_starts INTEGER NULL DEFAULT 0
        """,
        """
        ALTER TABLE machines
        ADD COLUMN IF NOT EXISTS pump_was_on BOOLEAN NOT NULL DEFAULT FALSE
        """,
        """
        ALTER TABLE machines
        ADD COLUMN IF NOT EXISTS pump_on_pressure_bar DOUBLE PRECISION NOT NULL DEFAULT 20
        """,
        """
        ALTER TABLE machines
        ADD COLUMN IF NOT EXISTS pump_on_temperature_c DOUBLE PRECISION NOT NULL DEFAULT 35
        """,
        """
        ALTER TABLE machines
        ADD COLUMN IF NOT EXISTS geo_region_name VARCHAR(255) NULL
        """,
        """
        ALTER TABLE machines
        ADD COLUMN IF NOT EXISTS geo_center_lat DOUBLE PRECISION NULL
        """,
        """
        ALTER TABLE machines
        ADD COLUMN IF NOT EXISTS geo_center_lon DOUBLE PRECISION NULL
        """,
        """
        ALTER TABLE machines
        ADD COLUMN IF NOT EXISTS geo_radius_m DOUBLE PRECISION NULL
        """,
        """
        ALTER TABLE machines
        ADD COLUMN IF NOT EXISTS geo_fence_enabled BOOLEAN NOT NULL DEFAULT FALSE
        """,
        """
        ALTER TABLE machines
        ADD COLUMN IF NOT EXISTS geo_last_inside BOOLEAN NULL
        """,
        # users: водитель → одна машина
        """
        ALTER TABLE users
        ADD COLUMN IF NOT EXISTS assigned_machine_id VARCHAR(36) NULL
        """,
        """
        ALTER TABLE users
        ADD COLUMN IF NOT EXISTS first_name VARCHAR(128) NULL
        """,
        """
        ALTER TABLE users
        ADD COLUMN IF NOT EXISTS last_name VARCHAR(128) NULL
        """,
        """
        ALTER TABLE users
        ADD COLUMN IF NOT EXISTS birth_date TIMESTAMP NULL
        """,
        """
        ALTER TABLE users
        ADD COLUMN IF NOT EXISTS gender VARCHAR(16) NULL
        """,
        """
        ALTER TABLE users
        ADD COLUMN IF NOT EXISTS phone VARCHAR(64) NULL
        """,
        """
        ALTER TABLE users
        ADD COLUMN IF NOT EXISTS about TEXT NULL
        """,
        """
        ALTER TABLE users
        ADD COLUMN IF NOT EXISTS avatar_ext VARCHAR(8) NULL
        """,
        """
        ALTER TABLE machines
        ADD COLUMN IF NOT EXISTS description TEXT NULL
        """,
        """
        ALTER TABLE machines
        ADD COLUMN IF NOT EXISTS photo_ext VARCHAR(8) NULL
        """,
    # Каналы оповещений: голосовой звонок / робот
        """
        ALTER TABLE notification_settings
        ADD COLUMN IF NOT EXISTS critical_phone BOOLEAN NOT NULL DEFAULT FALSE
        """,
        """
        ALTER TABLE notification_settings
        ADD COLUMN IF NOT EXISTS warning_phone BOOLEAN NOT NULL DEFAULT FALSE
        """,
        # Предупреждения больше не пушат по умолчанию (политика: только журнал)
        """
        ALTER TABLE notification_settings
        ALTER COLUMN warning_push SET DEFAULT FALSE
        """,
        """
        ALTER TABLE notification_settings
        ALTER COLUMN warning_sound SET DEFAULT FALSE
        """,
        """
        ALTER TABLE notification_settings
        ALTER COLUMN warning_vibration SET DEFAULT FALSE
        """,
        # Аварии: СМС / почта / Telegram включены по умолчанию; робот-звонок выкл.
        """
        ALTER TABLE notification_settings
        ALTER COLUMN critical_sms SET DEFAULT TRUE
        """,
        """
        ALTER TABLE notification_settings
        ALTER COLUMN critical_email SET DEFAULT TRUE
        """,
        """
        ALTER TABLE notification_settings
        ALTER COLUMN critical_telegram SET DEFAULT TRUE
        """,
        """
        ALTER TABLE notification_settings
        ADD COLUMN IF NOT EXISTS alert_email_to VARCHAR(255) NULL
        """,
        """
        ALTER TABLE notification_settings
        ADD COLUMN IF NOT EXISTS alert_telegram_chat VARCHAR(255) NULL
        """,
        """
        ALTER TABLE notification_settings
        ADD COLUMN IF NOT EXISTS alert_sms_phone VARCHAR(32) NULL
        """,
        # Live-кэш на датчиках (GET /fleet/live без скана readings)
        """
        ALTER TABLE sensors
        ADD COLUMN IF NOT EXISTS last_value DOUBLE PRECISION NULL
        """,
        """
        ALTER TABLE sensors
        ADD COLUMN IF NOT EXISTS last_ts TIMESTAMP NULL
        """,
        """
        ALTER TABLE sensors
        ADD COLUMN IF NOT EXISTS last_status VARCHAR(16) NULL
        """,
        """
        ALTER TABLE sensors
        ADD COLUMN IF NOT EXISTS last_fault VARCHAR(16) NULL
        """,
        """
        ALTER TABLE sensors
        ADD COLUMN IF NOT EXISTS last_current_ma DOUBLE PRECISION NULL
        """,
        """
        ALTER TABLE sensors
        ADD COLUMN IF NOT EXISTS enabled BOOLEAN NOT NULL DEFAULT TRUE
        """,
    ]
    applied: list[str] = []
    with engine.begin() as conn:
        for stmt in statements:
            conn.execute(text(stmt))
            applied.append(stmt.strip().split()[5] if "ADD COLUMN" in stmt else "ok")
        # FK-индексы (без жёсткого FK на старых данных — только index)
        conn.execute(
            text(
                "CREATE INDEX IF NOT EXISTS ix_organizations_manufacturer_id "
                "ON organizations (manufacturer_id)"
            )
        )
        conn.execute(
            text(
                "CREATE INDEX IF NOT EXISTS ix_machines_manufacturer_id "
                "ON machines (manufacturer_id)"
            )
        )
        conn.execute(
            text(
                "CREATE INDEX IF NOT EXISTS ix_users_assigned_machine_id "
                "ON users (assigned_machine_id)"
            )
        )
        conn.execute(
            text(
                """
                CREATE TABLE IF NOT EXISTS machine_gps_points (
                    id VARCHAR(36) PRIMARY KEY,
                    machine_id VARCHAR(36) NOT NULL,
                    ts TIMESTAMP NOT NULL,
                    lat DOUBLE PRECISION NOT NULL,
                    lon DOUBLE PRECISION NOT NULL,
                    accuracy_m DOUBLE PRECISION NULL,
                    source VARCHAR(32) NOT NULL DEFAULT 'ingest'
                )
                """
            )
        )
        conn.execute(
            text(
                """
                CREATE TABLE IF NOT EXISTS cell_tower_cache (
                    id VARCHAR(36) PRIMARY KEY,
                    mcc INTEGER NOT NULL,
                    mnc INTEGER NOT NULL,
                    lac INTEGER NOT NULL,
                    cid INTEGER NOT NULL,
                    lat DOUBLE PRECISION NOT NULL,
                    lon DOUBLE PRECISION NOT NULL,
                    accuracy_m DOUBLE PRECISION NULL,
                    source VARCHAR(16) NOT NULL DEFAULT 'gnss',
                    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
                    CONSTRAINT uq_cell_tower UNIQUE (mcc, mnc, lac, cid)
                )
                """
            )
        )
        for col, typ in (
            ("last_cell_mcc", "INTEGER"),
            ("last_cell_mnc", "INTEGER"),
            ("last_cell_lac", "INTEGER"),
            ("last_cell_cid", "INTEGER"),
        ):
            conn.execute(
                text(
                    f"ALTER TABLE machines ADD COLUMN IF NOT EXISTS {col} {typ} NULL"
                )
            )
        conn.execute(
            text(
                """
                CREATE TABLE IF NOT EXISTS machine_geofences (
                    id VARCHAR(36) PRIMARY KEY,
                    machine_id VARCHAR(36) NOT NULL UNIQUE,
                    name VARCHAR(255) NOT NULL DEFAULT '',
                    center_lat DOUBLE PRECISION NOT NULL,
                    center_lon DOUBLE PRECISION NOT NULL,
                    radius_m DOUBLE PRECISION NOT NULL,
                    enabled BOOLEAN NOT NULL DEFAULT TRUE,
                    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
                    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
                )
                """
            )
        )
        conn.execute(
            text(
                "CREATE INDEX IF NOT EXISTS ix_machine_gps_points_machine_ts "
                "ON machine_gps_points (machine_id, ts)"
            )
        )
        conn.execute(
            text(
                "CREATE INDEX IF NOT EXISTS ix_machine_gps_points_machine_id "
                "ON machine_gps_points (machine_id)"
            )
        )
        applied.append("indexes")

        # Один раз: включить СМС/почта/Telegram, выключить робот-звонок.
        conn.execute(
            text(
                """
                CREATE TABLE IF NOT EXISTS schema_flags (
                    key VARCHAR(64) PRIMARY KEY,
                    applied_at TIMESTAMP NOT NULL DEFAULT NOW()
                )
                """
            )
        )
        already = conn.execute(
            text("SELECT 1 FROM schema_flags WHERE key = 'notify_channels_v2'")
        ).first()
        if already is None:
            conn.execute(
                text(
                    """
                    UPDATE notification_settings
                    SET critical_sms = TRUE,
                        critical_email = TRUE,
                        critical_telegram = TRUE,
                        alert_email_to = COALESCE(alert_email_to, ''),
                        alert_telegram_chat = COALESCE(alert_telegram_chat, ''),
                        alert_sms_phone = COALESCE(alert_sms_phone, ''),
                        critical_phone = FALSE,
                        warning_phone = FALSE
                    """
                )
            )
            conn.execute(
                text(
                    "INSERT INTO schema_flags (key) VALUES ('notify_channels_v2')"
                )
            )
            applied.append("notify_channels_v2")

        conn.execute(
            text(
                """
                CREATE TABLE IF NOT EXISTS telegram_chat_bindings (
                    id VARCHAR(36) PRIMARY KEY,
                    username VARCHAR(64) NOT NULL,
                    chat_id VARCHAR(64) NOT NULL,
                    display_name VARCHAR(128) NULL,
                    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
                )
                """
            )
        )
        conn.execute(
            text(
                "CREATE UNIQUE INDEX IF NOT EXISTS uq_telegram_username "
                "ON telegram_chat_bindings (username)"
            )
        )
        conn.execute(
            text(
                "CREATE INDEX IF NOT EXISTS ix_telegram_chat_bindings_chat_id "
                "ON telegram_chat_bindings (chat_id)"
            )
        )
        applied.append("telegram_chat_bindings")

        # Backfill last_* не делаем при старте: DISTINCT ON по readings на большой
        # истории блокирует ALTER и валит API (502). Кэш заполнится с новых ingest.
        already_live = conn.execute(
            text("SELECT 1 FROM schema_flags WHERE key = 'sensor_live_cache_v1'")
        ).first()
        if already_live is None:
            conn.execute(
                text(
                    "INSERT INTO schema_flags (key) VALUES ('sensor_live_cache_v1')"
                )
            )
            applied.append("sensor_live_cache_v1_skip_backfill")

        conn.execute(text("CREATE EXTENSION IF NOT EXISTS pgcrypto"))
        conn.execute(
            text(
                """
                CREATE TABLE IF NOT EXISTS readings_hourly (
                    id VARCHAR(36) PRIMARY KEY,
                    machine_id VARCHAR(36) NOT NULL,
                    sensor_id VARCHAR(36) NOT NULL,
                    period TIMESTAMP NOT NULL,
                    avg_value DOUBLE PRECISION NOT NULL,
                    min_value DOUBLE PRECISION NOT NULL,
                    max_value DOUBLE PRECISION NOT NULL,
                    samples INTEGER NOT NULL DEFAULT 0,
                    status VARCHAR(16) NOT NULL DEFAULT 'ok'
                )
                """
            )
        )
        conn.execute(
            text(
                """
                CREATE TABLE IF NOT EXISTS readings_daily (
                    id VARCHAR(36) PRIMARY KEY,
                    machine_id VARCHAR(36) NOT NULL,
                    sensor_id VARCHAR(36) NOT NULL,
                    period TIMESTAMP NOT NULL,
                    avg_value DOUBLE PRECISION NOT NULL,
                    min_value DOUBLE PRECISION NOT NULL,
                    max_value DOUBLE PRECISION NOT NULL,
                    samples INTEGER NOT NULL DEFAULT 0,
                    status VARCHAR(16) NOT NULL DEFAULT 'ok'
                )
                """
            )
        )
        conn.execute(
            text(
                "CREATE UNIQUE INDEX IF NOT EXISTS uq_readings_hourly_sensor_period "
                "ON readings_hourly (sensor_id, period)"
            )
        )
        conn.execute(
            text(
                "CREATE UNIQUE INDEX IF NOT EXISTS uq_readings_daily_sensor_period "
                "ON readings_daily (sensor_id, period)"
            )
        )
        conn.execute(
            text(
                "CREATE INDEX IF NOT EXISTS ix_readings_hourly_sensor_period "
                "ON readings_hourly (sensor_id, period)"
            )
        )
        conn.execute(
            text(
                "CREATE INDEX IF NOT EXISTS ix_readings_daily_sensor_period "
                "ON readings_daily (sensor_id, period)"
            )
        )
        conn.execute(
            text(
                "CREATE INDEX IF NOT EXISTS ix_readings_hourly_machine_period "
                "ON readings_hourly (machine_id, period)"
            )
        )
        conn.execute(
            text(
                "CREATE INDEX IF NOT EXISTS ix_readings_daily_machine_period "
                "ON readings_daily (machine_id, period)"
            )
        )
        applied.append("readings_archive_tables")
    return applied
