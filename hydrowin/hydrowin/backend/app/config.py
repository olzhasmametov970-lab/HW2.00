from pydantic_settings import BaseSettings, SettingsConfigDict

_WEAK_JWT_SECRETS = frozenset(
    {
        "dev-secret-change-in-production",
        "change-me-to-random-64-chars-minimum-for-production-security",
        "secret",
        "changeme",
    }
)


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql://hydrowin:hydrowin_secret@db:5432/hydrowin"

    jwt_secret: str = "dev-secret-change-in-production"
    jwt_access_minutes: int = 15
    jwt_refresh_days: int = 30
    api_host: str = "0.0.0.0"
    api_port: int = 8090
    # Для Flutter CORS почти не важен; "*" + credentials запрещены.
    cors_origins: str = ""
    default_device_key: str = "hydro-demo-device-key"
    environment: str = "development"
    allow_public_register: bool = False
    auth_rate_limit: int = 10
    auth_rate_window_seconds: int = 60
    ingest_rate_limit: int = 120
    ingest_rate_window_seconds: int = 60

    db_pool_size: int = 10
    db_max_overflow: int = 20
    db_pool_timeout_seconds: int = 30
    uvicorn_workers: int = 1
    # Сырые точки (live / график «час»).
    readings_retention_days: int = 30
    # Агрегаты hourly/daily — максимум полгода для экспорта/отчётов.
    readings_archive_days: int = 180
    readings_purge_interval_hours: int = 24

    # MQTT опционален (LAN/отладка). Продакшен: HTTPS ingest, MQTT_ENABLED=false.
    mqtt_enabled: bool = False
    mqtt_host: str = "mosquitto"
    mqtt_port: int = 1883
    mqtt_api_user: str = "hydrowin-api"
    mqtt_api_password: str = "change-me-mqtt-api"
    mqtt_device_user: str = "hydrowin-device"
    mqtt_device_password: str = "change-me-mqtt-device"
    mqtt_client_id: str = "hydrowin-api-subscriber"
    mqtt_reconnect_seconds: int = 5

    # Реальные каналы уведомлений
    telegram_enabled: bool = False
    telegram_bot_token: str = ""
    telegram_api_base: str = "https://api.telegram.org"
    # HTTP(S) прокси, если api.telegram.org недоступен (типично для РФ/ISP).
    # Пример: http://127.0.0.1:7890 или socks5://... (нужен PySocks).
    telegram_proxy_url: str = ""

    smtp_enabled: bool = False
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_user: str = ""
    smtp_password: str = ""
    smtp_from_email: str = ""
    smtp_from_name: str = "HydroWin"
    smtp_starttls: bool = True
    smtp_ssl: bool = False

    # GSM-локация по соте. Бесплатный ключ: https://opencellid.org
    opencellid_api_key: str = ""

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    @property
    def is_production(self) -> bool:
        return self.environment.strip().lower() in {"production", "prod"}

    def assert_secure_secrets(self) -> None:
        weak_jwt = self.jwt_secret in _WEAK_JWT_SECRETS or len(self.jwt_secret) < 32
        weak_device = self.default_device_key in {
            "hydro-demo-device-key",
            "hydro-demo-device-key-change-me",
        }
        weak_mqtt = self.mqtt_enabled and (
            self.mqtt_api_password in {"change-me-mqtt-api", "changeme", "secret"}
            or self.mqtt_device_password
            in {"change-me-mqtt-device", "changeme", "secret"}
            or len(self.mqtt_api_password) < 16
            or len(self.mqtt_device_password) < 16
        )
        weak_telegram = self.telegram_enabled and (
            not self.telegram_bot_token or "change-me" in self.telegram_bot_token
        )
        weak_smtp = self.smtp_enabled and (
            not self.smtp_host
            or not self.smtp_from_email
            or (self.smtp_user and len(self.smtp_password) < 8)
        )
        weak_db_password = any(
            frag in self.database_url
            for frag in (
                ":hydrowin_secret@",
                ":postgres@",
                ":password@",
                ":changeme@",
            )
        )
        weak_cors_localhost = self.is_production and any(
            o.startswith("http://localhost") or o.startswith("http://127.0.0.1")
            for o in self.cors_origin_list
        )
        if weak_db_password:
            print(
                "⚠️  Пароль PostgreSQL дефолтный (hydrowin_secret) — "
                "смените перед выходом на рынок (ALTER USER + .env)"
            )
        if not self.is_production:
            if weak_jwt:
                print("⚠️  JWT_SECRET слабый/дефолтный — смените перед продакшеном")
            if weak_mqtt:
                print("⚠️  MQTT пароли слабые/дефолтные — смените перед продакшеном")
            if weak_telegram:
                print("⚠️  TELEGRAM_BOT_TOKEN не настроен")
            if weak_smtp:
                print("⚠️  SMTP не настроен полностью")
            if self.uvicorn_workers > 1:
                print(
                    "⚠️  UVICORN_WORKERS>1: in-memory rate limit не шарится "
                    "между процессами"
                )
            return
        problems: list[str] = []
        if weak_jwt:
            problems.append(
                "JWT_SECRET должен быть случайной строкой ≥32 символов"
            )
        if weak_device:
            problems.append("DEFAULT_DEVICE_KEY не должен быть demo-значением")
        if weak_mqtt:
            problems.append(
                "MQTT_API_PASSWORD и MQTT_DEVICE_PASSWORD должны быть уникальными ≥16 символов"
            )
        if weak_telegram:
            problems.append("TELEGRAM_BOT_TOKEN должен быть задан для Telegram alerts")
        if weak_smtp:
            problems.append("SMTP_HOST и SMTP_FROM_EMAIL должны быть заданы для email alerts")
        if weak_cors_localhost:
            problems.append(
                "CORS_ORIGINS в production не должен включать localhost"
            )
        if self.uvicorn_workers > 1:
            print(
                "⚠️  UVICORN_WORKERS>1: in-memory rate limit login/ingest "
                "не шарится между workers (оставьте 1 или Redis)"
            )
        if problems:
            raise RuntimeError(
                "Небезопасная конфигурация production:\n- " + "\n- ".join(problems)
            )


settings = Settings()
