# HydroWin — готовность к рынку и производству

Чеклист перед отгрузкой плат / публикацией кабинета.

## P0 — обязательно (иначе не выпускать)

### Инфраструктура
- [ ] DNS: `app.hydrowin.ru` → сервер API (Ubuntu Caddy) **или** BeGet proxy `/v1` → API
- [ ] `https://app.hydrowin.ru/v1/health` → `{"status":"ok"}`
- [ ] `https://5-165-27-141.sslip.io/` → **410/403** (Caddy явно отклоняет sslip)
- [ ] Firewall: снаружи только **443** (+ SSH по ключу). **Не** публиковать 5432 / 8090 / 1883 в интернет

### Секреты (ротация)
- [ ] `JWT_SECRET` — случайный ≥32 (уже проверяется при старте)
- [ ] `POSTGRES_PASSWORD` — не `hydrowin_secret` (`ALTER USER` + `.env` + `DATABASE_URL`)
- [ ] `DEFAULT_DEVICE_KEY` — не demo; лучше **не** использовать общий ключ
- [ ] SMTP / Telegram / OpenCellID — ротировать, если ключи светились в чатах/репо
- [ ] Пароли `admin@…` и прочих учёток — сменить с bootstrap-значений

### Прошивка (каждая плата)
- [ ] `TLS_INSECURE=0` (дефолт в `config.h`)
- [ ] `DEVICE_KEY` / `MACHINE_ID` только через Serial/BLE после регистрации в кабинете
- [ ] Wi‑Fi/APN — через Serial/BLE, не из git
- [ ] Проверка: ingest на `https://app.hydrowin.ru/v1/ingest/telemetry`

### Клиенты
- [ ] Сборка Full: `ENABLE_DEMO=false` (дефолт), API `https://app.hydrowin.ru/v1`
- [ ] Web залить в `backend/web` + restart Caddy / BeGet
- [ ] Windows/Android release без «Демо завода» для клиентов

## P1 — сильно желательно

- [ ] CORS только `https://hydrowin.ru`, `https://www.hydrowin.ru`, `https://app.hydrowin.ru`
- [ ] MQTT выкл. (`MQTT_ENABLED=false`) — телеметрия только HTTPS
- [ ] Резервное копирование PostgreSQL (ежедневно)
- [ ] Мониторинг `/v1/health` + алерты
- [ ] Политика: уникальный device key на плату, ротация при компрометации

## Что уже ужесточено в коде

| Область | Изменение |
|--------|-----------|
| Firmware | `TLS_INSECURE=0`, нет живых KEY/Wi‑Fi в git |
| Mobile | demo off, нет дефолтного developer-пароля |
| Backend | demo-парк не создаётся в production; `ensure-device` запрещён; `/v1/data` убран |
| Compose | MQTT только `127.0.0.1:1883` |
| Auth | пароль ≥10 + буква + цифра + спецсимвол |
| Rate limit | приоритет `X-Real-IP` (Caddy) |

Подробнее: `backend/SECURITY.md`.
