# MQTT для HydroWin (опционально)

**Продакшен:** пакетный **HTTPS** `POST /v1/ingest/telemetry` раз в 30–60 с
(Wi‑Fi и GSM, один JSON). MQTT **не нужен** — только опционально для LAN.

| Канал | Назначение |
|--------|------------|
| **HTTPS** | приложение + телеметрия плат (рекомендуется) |
| **MQTT :1883** | опционально, только LAN (`MQTT_ENABLED=true`, прошивка `TELEMETRY_TRANSPORT 2`) |

По умолчанию в `.env` / `config.py`: `MQTT_ENABLED=false`.

## Включить MQTT (LAN)

1. В `.env` задайте длинные уникальные пароли (≥16, не `change-me-*`):
   ```text
   MQTT_ENABLED=true
   MQTT_API_PASSWORD=...
   MQTT_DEVICE_PASSWORD=...
   ```
2. `docker compose up -d --build mosquitto api`
3. В прошивке `config.h`: `TELEMETRY_TRANSPORT 2`, `MQTT_HOST` = IP брокера в LAN, `MQTT_PASSWORD` = `MQTT_DEVICE_PASSWORD`.
4. PubSubClient (Nick O'Leary) в Arduino Library Manager.

## Топик и payload

```text
Topic:   hydrowin/telemetry/{device_id}
QoS:     1 (subscribe) / 0–1 (publish)
```

JSON как у `POST /v1/ingest/telemetry` (промышленный `{"d":[[ts,p0,t1,t2,p1]]}` или verbose), плюс `device_key` (= X-Device-Key).

| User | Роль |
|------|------|
| `hydrowin-api` | subscribe `hydrowin/telemetry/#` |
| `hydrowin-device` | publish `hydrowin/telemetry/#` |

```powershell
docker compose exec mosquitto mosquitto_sub -h localhost -u hydrowin-api -P "<MQTT_API_PASSWORD>" -t "hydrowin/telemetry/#" -v
```

## TLS MQTT (8883)

Для предприятий с MQTT в WAN лучше **не** открывать 1883, а либо остаться на HTTPS, либо поднять Mosquitto с сертификатами на **8883**. В текущем стеке выбран HTTPS — проще и уже есть у GSM.
