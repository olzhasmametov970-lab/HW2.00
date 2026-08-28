# Две платы → две машины (актуальная привязка)

| | **Плата 1** | **Плата 2** |
|---|-------------|-------------|
| `DEVICE_ID` | `ESP32-HYDRO-01` | `ESP32-HYDRO-02` |
| `MACHINE_ID` | `f4c32e25-bbdb-4d89-bb9d-9ac30573606c` | `2253cd6d-2804-49a4-9bb4-8b4d0083eea2` |
| `machine_code` | `1783422691603` (лучше переименовать в `001`) | `002` |
| `DEVICE_KEY` | **не хранить в git** — из `POST /machines/id/{id}/devices` (один раз) или NVS | то же |
| Header | `X-Device-Key` | `X-Device-Key` |

В парке: плата 1 → UUID `f4c32e25-…`, плата 2 → **002**.

> Если ключи светились в чате/репо — **ротируйте**: новое устройство в админке → Serial `KEY …` → удалите старый device.

---

## Serial (USB 115200, NL) — **по одной строке**

### Плата 1

```text
MACHINE f4c32e25-bbdb-4d89-bb9d-9ac30573606c
DEVICE ESP32-HYDRO-01
KEY <paste-device-key-once>
CFG
```

### Плата 2

```text
MACHINE 2253cd6d-2804-49a4-9bb4-8b4d0083eea2
DEVICE ESP32-HYDRO-02
KEY <paste-device-key-once>
CFG
```

После `CFG` проверьте `MACHINE` / `DEVICE` / `KEY`, затем Reset (**EN**).

**Не коммитьте живые `DEVICE_KEY`.** Задавайте через Serial после прошивки (NVS важнее `config.h`).

См. [GSM_AND_CALIBRATION.md](GSM_AND_CALIBRATION.md).
