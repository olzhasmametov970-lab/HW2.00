# Ротация секретов HydroWin (после утечки в чат/логи)
#
# Уже сделано автоматически в `.env` + перезапуск API/Mosquitto:
# - JWT_SECRET
# - MQTT_API_PASSWORD / MQTT_DEVICE_PASSWORD
# - DEFAULT_DEVICE_KEY (только для ensure-device / seed; живые платы
#   со своими KEY в NVS не затронуты — в БД их hash не совпал)
#
# Сделайте вручную (я не могу сменить пароль у BeGet/BotFather за вас):
#
# 1) Telegram
#    - @BotFather → /revoke → новый токен
#    - в `.env`: TELEGRAM_BOT_TOKEN=...
#    - docker compose up -d api
#    - пользователи снова пишут боту /start
#
# 2) SMTP (BeGet help@hydrowin.ru)
#    - панель BeGet → смена пароля ящика
#    - в `.env`: SMTP_PASSWORD=...
#    - docker compose up -d api
#
# 3) ESP32 — что прошивать / писать в Serial
#    Wi‑Fi фикс (не рвать канал после HTTPS fail): перепрошейте
#      firmware/esp32_ingest
#    MQTT на плате (если TELEMETRY_TRANSPORT=2): MQTT_PASSWORD в config.h
#      = MQTT_DEVICE_PASSWORD из `.env`
#    DEFAULT_DEVICE_KEY на плате НЕ нужен, если ключ уже выдан через
#      register-board / KEY <device_key> и лежит в NVS.
#
# После ротации JWT все пользователи приложения должны войти заново.
