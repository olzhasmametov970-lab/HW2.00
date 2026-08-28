# HydroWin API (backend)

REST API для облачного режима приложения. Реализует контракт `api/openapi.yaml`.

## Быстрый старт (Docker)

```powershell
cd backend
copy .env.example .env
# Отредактируйте JWT_SECRET и DEFAULT_DEVICE_KEY
docker compose up -d --build
```

- API: http://localhost:8090/v1/docs  
- Health: http://localhost:8090/health  

## Демо-данные (создаются при первом запуске)

| | |
|---|---|
| Email | `admin@hydrowin.ru` (Админ платформы) |
| Пароль | `HydroWin2026!` |
| Ключ устройства | значение `DEFAULT_DEVICE_KEY` из `.env` |

## Ingest телеметрии

Промышленный JSON (плата → API):

```bash
curl -X POST http://localhost:8090/v1/ingest/telemetry \
  -H "Content-Type: application/json" \
  -H "X-Device-Key: <device_key>" \
  -d '{"d":[[1718204001,0.12,28.17,29.05,-0.04]]}'
```

Строка: `[unix_ts, p0, t1, t2, p1]` (CH0–CH3). Можно пакет: несколько строк в `d`.  
`device` / `machine` берутся из ключа. Verbose JSON (message_id/sensors) ещё принимается.

Полная инструкция развёртывания: `docs/DEPLOY-SYSTEM.md`
