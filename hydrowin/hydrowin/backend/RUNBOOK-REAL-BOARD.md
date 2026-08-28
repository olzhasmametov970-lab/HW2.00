# HydroWin Runbook

Короткая инструкция: запуск backend, логи, MQTT, порты и проверка.

Подробная привязка платы: см. `BOARD-BINDING.md`.  
Восстановление из backup: см. `RESTORE.md` (`restore-from-backup.ps1`).

## 1. Запуск backend

```powershell
cd C:\Users\Admin2\Desktop\HW2.0\hydrowin\hydrowin\backend
docker compose up -d --build
docker compose ps
```

Проверка:

```powershell
curl.exe -s https://app.hydrowin.ru/v1/health
curl.exe -s https://app.hydrowin.ru/health
```

## 2. Логи

```powershell
docker compose logs --tail 100
docker compose logs -f api
docker compose logs -f mosquitto
docker compose logs -f caddy
```

## 3. Порты (Keenetic / firewall)

| Порт | Назначение |
|------|------------|
| `80/tcp` | Caddy / Let's Encrypt |
| `443/tcp` | HTTPS API |
| `1883/tcp` | MQTT для плат |
| `8090/tcp` | Legacy HTTP API (по необходимости) |

## 4. Проверка MQTT

```powershell
docker compose exec mosquitto mosquitto_sub -h localhost -u hydrowin-api -P "<MQTT_API_PASSWORD>" -t "hydrowin/telemetry/#" -v
docker compose logs -f api | Select-String MQTT
```

Ожидаемо в логах API:

```text
MQTT: accepted ESP32-...
```

## 5. Сценарий «с нуля»

1. Админ платформы создаёт производителя: `POST /v1/orgs/manufacturers`
2. Админ назначает машину: `POST /v1/machines/id/{id}/assign-manufacturer`
3. Производитель создаёт завод: `POST /v1/orgs/clients`
4. Производитель передаёт машину: `POST /v1/machines/id/{id}/transfer`
5. Завод создаёт плату: `POST /v1/machines/id/{id}/devices`
6. На плату через Serial: `DEVICE`, `MACHINE`, `KEY`, `API`, `WIFI`/`GSM`
7. Проверить MQTT publish и HTTP fallback `202`

## 6. Topic / fallback

- MQTT: `hydrowin/telemetry/{DEVICE_ID}`
- HTTP: `https://app.hydrowin.ru/v1/ingest/telemetry`

## 7. Результаты E2E (28.07.2026)

Прогнано через API:

- админ платформы: видит машины, `is_platform=true`
- производитель HydroMaker: после assign/transfer видит машину как `manufacturer_readonly`
- новый завод E2E: создан, видит 1 свою машину как `owner`
- создание устройства `ESP32-E2E-...`: OK
- HTTP ingest: `202`
- MQTT broker: принимает publish (плата `ESP32-HYDRO-01` реально коннектится к `:1883`)
- живая телеметрия сейчас активно идёт и через HTTP fallback (`POST /v1/ingest/telemetry 202`)

Файлы прогона: `backend/backups/e2e_latest/`
