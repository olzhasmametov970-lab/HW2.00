# Привязка новой платы

Пошаговая процедура: backend + Serial.

> В приложении: **Настройки → Зарегистрировать плату** (или пустой парк) —
> создаёт машину + `device_key` и сразу показывает блок в парке.
> Ниже — тот же сценарий через API.

## Что нужно заранее

- backend поднят (`docker compose up -d`)
- открыты порты: `80`, `443`, `1883` (+ `8090` при необходимости)
- в `.env` заданы:
  - `MQTT_DEVICE_PASSWORD`
  - `MQTT_API_PASSWORD`
  - `JWT_SECRET`

## 1. Backend: создать/назначить машину

1. Войти как **Админ платформы**.
2. Создать производителя при необходимости:

```http
POST /v1/orgs/manufacturers
{
  "name": "HydroMaker",
  "admin_name": "Админ производителя",
  "admin_email": "maker@example.com",
  "admin_password": "StrongPass123!"
}
```

3. Назначить машину производителю:

```http
POST /v1/machines/id/{machine_id}/assign-manufacturer
{
  "manufacturer_organization_id": "<maker_org_uuid>"
}
```

4. Производитель создаёт завод и передаёт машину:

```http
POST /v1/orgs/clients
POST /v1/machines/id/{machine_id}/transfer
```

## 2. Backend: создать устройство (плату)

Владелец машины (завод или производитель, если ещё на складе):

```http
POST /v1/machines/id/{machine_id}/devices
{
  "device_id": "ESP32-HYDRO-03"
}
```

Ответ (сохранить сразу!):

| Поле | Куда дальше |
|------|-------------|
| `device_id` | Serial: `DEVICE ...` |
| `machine_id` | Serial: `MACHINE ...` |
| `device_key` | Serial: `KEY ...` (один раз!) |
| `mqtt_topic` | `hydrowin/telemetry/{device_id}` |

## 3. Где что задаётся

| Параметр | Где задаётся | Примечание |
|----------|--------------|------------|
| `DEVICE_ID` | Serial `DEVICE` или `config.h` | После Serial живёт в NVS |
| `MACHINE_ID` | Serial `MACHINE` или `config.h` | UUID машины из backend |
| `KEY` / `device_key` | Serial `KEY` | Из ответа create device |
| `MQTT_PASSWORD` | `config.h` = `MQTT_DEVICE_PASSWORD` из `.env` | Пароль брокера, не device_key |
| `MQTT_USER` | `config.h` обычно `hydrowin-device` | |
| Topic | автоматически | `hydrowin/telemetry/{DEVICE_ID}` |
| HTTP fallback | `API host\|443` | `https://.../v1/ingest/telemetry` |

## 4. Serial-команды на плату

USB Serial Monitor, 115200:

```text
DEVICE ESP32-HYDRO-03
MACHINE ********-****-****-****-************
KEY <device_key_из_ответа_API>
API app.hydrowin.ru|443
LINK wifi
WIFI <ssid>|<password>
CFG
```

Для GSM:

```text
GSM <apn>|<user>|<pass>
LINK gsm
```

или универсально:

```text
LINK auto
```

## 5. PowerShell: создать устройство через API

```powershell
$base = 'https://app.hydrowin.ru/v1'
$login = Invoke-RestMethod -Method Post -Uri "$base/auth/login" -ContentType 'application/json' -Body (@{
  email = 'admin@hydrowin.ru'
  password = '<password>'
} | ConvertTo-Json)

$hdr = @{ Authorization = "Bearer $($login.access_token)" }
$machineId = '<machine_uuid>'
$device = Invoke-RestMethod -Method Post -Uri "$base/machines/id/$machineId/devices" `
  -Headers $hdr -ContentType 'application/json' `
  -Body (@{ device_id = 'ESP32-HYDRO-03' } | ConvertTo-Json)

$device | Format-List device_id, machine_id, device_key, mqtt_topic
```

## 6. Проверка после прошивки

Ожидаемо в Serial:

```text
MQTT connect ... OK
MQTT publish hydrowin/telemetry/ESP32-HYDRO-03 → OK
```

Если MQTT недоступен (`TELEMETRY_TRANSPORT 2`):

```text
MQTT fail → HTTP
HTTP(Wi-Fi) 202
```

В backend:

```powershell
docker compose logs -f api
# MQTT: accepted ESP32-HYDRO-03 ...
# или POST /v1/ingest/telemetry 202
```

## 7. Реестр плат (обязательно)

Храните вне git:

```text
device_id | machine_id | device_key | mqtt_topic | owner | date
```

В PostgreSQL есть только `api_key_hash`, не plain-text ключ.
