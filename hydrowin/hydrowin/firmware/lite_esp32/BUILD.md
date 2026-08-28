# HydroWin — lite_esp32 (ESP32 classic)

**Схема:** датчики (ADC1) → BLE v2 Nordic UART → приложение.

## Требования
1. Arduino IDE
2. Библиотека NimBLE-Arduino (h2zero)
3. Arduino library `esp32_ingest`:
   1) Создайте папку `C:\Users\<USER>\Documents\Arduino\libraries\esp32_ingest` (или вашу, где лежат библиотеки).
   2) Скопируйте содержимое `firmware/esp32_ingest/` целиком в эту папку.
   3) Название папки должно быть `esp32_ingest`, чтобы работали include `#include <esp32_ingest/...>`.

## Как собирать
1. Откройте файл `lite_esp32_ingest.ino`
2. Board: **ESP32 Dev Module**
3. Соберите и прошейте

## Особенности
- Wi‑Fi/GSM/HTTPS не используются
- Значения датчиков — **целые** (бар / °C)
- Калибровка через BLE: сначала `AUTH <PIN>` (хвост MAC из Serial), затем `CAL/ENABLE/...`
- `HYDROWIN_FORCE_SENSOR_TABLE_ENABLED=1`: при старте `enabled` из `SENSOR_TABLE`
- Питание датчиков 4–20 мА: **24 V** на петлю; ESP32 — **5 V** (см. [POWER_WIRING.md](../POWER_WIRING.md))

После правки `.h` скопируйте в Arduino library:
`Documents\Arduino\libraries\esp32_ingest\`

