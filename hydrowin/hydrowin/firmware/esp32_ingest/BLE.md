# HydroWin — Bluetooth (BLE)

Локальная настройка блока и живая телеметрия без облака: телефон ↔ плата по Nordic UART.

## Требования

1. Arduino Library Manager → **NimBLE-Arduino** (h2zero).
2. Без библиотеки прошивка **собирается**, BLE выключен (как MQTT без PubSubClient).
3. Мобильное приложение: экран «Подключить блок по Bluetooth» (`/ble/connect`).

## Advertise

Короткое имя: `HydroWinN` (N из `DEVICE_ID`).

Пример: `HydroWin1`, `HydroWin2`.

## GATT (Nordic UART)

| Роль | UUID |
|------|------|
| Service | `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` |
| RX (phone → ESP, Write) | `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` |
| TX (ESP → phone, Notify) | `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` |

Константы дублируются в `config.h` (`BLE_*_UUID`) и во Flutter `lib/core/ble/ble_uuids.dart`.

## Команды (RX, ASCII, как USB Serial)

Строки с `\n` (или `\r\n`), те же, что в `block_setup.h`:

```text
WIFI ssid|password
API host|port
LINK wifi
CFG
```

Ответ на TX: текст `OK\n` или краткий `CFG …` summary.

## Телеметрия (TX, бинарный пакет **v2**)

Максимум **6 каналов CH0–CH5** (все на **ADC1**). Каждые `BLE_TELEMETRY_MS` (по умолчанию 1000 мс) при активном соединении:

| Offset | Size | Поле |
|--------|------|------|
| 0 | 1 | proto = `0x02` |
| 1 | 1 | flags (bit0 = GPS valid; на блоке обычно 0) |
| 2 | 4 | timestamp (uint32 LE, сейчас — uptime sec) |
| 6 | 12 | ch0..ch5 value ×10 (int16 LE каждый) |
| 18 | 2 | status (2 бита × 6 каналов: 0 ok / 1 warn / 2 short / 3 open) |
| 20 | 1 | CRC-8/MAXIM по байтам 0..19 |

Итого **21 байт**. CRC и разбор — Flutter `crc8_maxim.dart` / `telemetry_packet.dart`.

Приложение ещё принимает legacy **v1** (14 байт, proto `0x01`, только CH0–CH2) со старых прошивок.

## Пины ADC1

| Канал | GPIO | Примечание |
|-------|------|------------|
| CH0 | 35 | ADC1 |
| CH1 | 34 | ADC1 |
| CH2 | 33 | ADC1 |
| CH3 | 32 | ADC1 |
| CH4 | 36 | ADC1, input-only |
| CH5 | 39 | ADC1, input-only |

## Wiring в прошивке

- `#include "ble_config.h"` после `block_setup.h`
- `bleBegin()` в `setup()` после `initLink()`
- `bleLoop()` в `loop()` (рядом с Serial/телеметрией)

## Версия

`VERSION` → `HydroWin-V9.7` (BLE v2 CH0–CH5 + Wi‑Fi/GSM/MQTT).
