# HydroWin — full_ta7670_sim7670g_internal_gps
## (Старая отладочная плата **LILYGO T‑SIM7670G‑S3 16МБ H707** — ЧЁРНАЯ PCB)

Прошивка для **чёрной платы LILYGO T‑SIM7670G‑S3 H707** (Первая фотография пользователя):
- **PCB ЧЁРНАЯ, 1× USB-C + 1 micro-USB** (ESP + Modem отдельные порты)
- ESP32-S3 16MB Flash / 8MB PSRAM (N16R8)
- **SIM7670G LTE Cat.1** — **GNSS ВНУТРИ МОДЕМА** (GPS/ГЛОНАСС/Galileo/BeiDou)
- Отдельного GPS-чипа L76K на плате **НЕТ** (чип L76K физически отсутствует!)
- Связь: **по умолчанию Wi-Fi first** (LINK_WIFI) → опционально auto / gsm

---

## Как ОТЛИЧИТЬ от A7670G-Standard (фото-подсказка)

| Характеристика | T-SIM7670G-S3 H707 → **ЧЁРНАЯ** ← эта прошивка | T-A7670G-S3 Standard → ЗЕЛЁНАЯ |
|---|---|---|
| Цвет платы | ⬛ **Чёрный PCB** | 🟩 **Зелёный PCB** |
| USB-порты | 1 USB-C + 1 **Micro-USB** | **Два USB-C** |
| Модем | **SIM7670G** (наклейка с надписью) | **A7670G** (надпись на модеме) |
| Отдельный L76K чип сверху | ❌ НЕТ | ✅ ЕСТЬ + зелёная керамическая антенна |
| Антенные разъёмы IPEX | 2 шт: **«MAIN» LTE + «GNSS»** | 2 шт: «MAIN» LTE + «GPS» |
| Наша прошивка | ✅ эта папка | `_a7670g_external_l76k/` |

---

## Распиновка T‑SIM7670G‑S3 H707 (ЧЁРНАЯ)

По [gsm_a7670.h:L545](file:///c:/Users/Admin2/Desktop/HW2.0/hydrowin/hydrowin/firmware/esp32_ingest/gsm_a7670.h#L545) карта `SIM7670-S3` и официальный `utilities.h:LILYGO_T_SIM7670G_S3`.

| Интерфейс | Сигнал | GPIO ESP32-S3 | Примечание |
|---|---|---|---|
| **LTE SIM7670G** (Serial1) | RX ESP ← TX модема | **10** | 115200 8N1 |
| | TX ESP → RX модема | **11** | |
| | PWRKEY | **18** | LOW импульс 100 мс, idle LOW |
| | DTR (не спать) | **9** | Постоянно LOW |
| | RESET | **17** | LOW-активный |
| | RING | **3** | |
| **GNSS** | — | через UART модема | AT+CGNSSPWR → AT+CGNSSINFO, NMEA внутри модема |
| **GNSS antenna power** | AUXVDD | GPIO 4 внутри модема | AT+CGDRT=4,1 или AT+CGSETV=4,1 |
| **Датчики 4–20 мА** | CH0 давление **P0** | **01** (GPIO1) | ✅ уже под датчик; шунт 150 Ω → GND |
| | CH1 температура T1 | **02** | выкл |
| | CH2 температура T2 | **06** | выкл |
| | CH3 давление P1 | **08** | выкл |
| | CH4 | **15** | выкл |
| | CH5 | **16** | выкл |
| LED статусный | LED / EN | **12** | ⚠️ активный LOW |
| **ADC питания** | BAT_ADC | **04** | ❌ не датчик |
| | SOLAR / ADC | **05** | ❌ не датчик |
| **SD Card** (не исп.) | CS / MOSI / MISO / SCK | 13 / 14 / 47 / 21 | не для датчиков |

⚠️ **Не паять датчики на:** 03 (RING), **04**, **05**, 09 (DTR), 10/11 (модем), **12**, 13/14/21/47 (SD), 17/18.

---

## Arduino — сборка и прошивка

1. Откройте [full_ta7670_sim7670g_internal_gps.ino](file:///c:/Users/Admin2/Desktop/HW2.0/hydrowin/hydrowin/firmware/full_ta7670/full_ta7670_sim7670g_internal_gps/full_ta7670_sim7670g_internal_gps.ino)
2. **Board**: `ESP32S3 Dev Module`
3. **Flash Size**: **16MB (128Mb)** (на плате 16МБ!)
4. **Partition Scheme**: `16M Flash (3MB APP/9.9MB FATFS)` или `Huge APP ... 1MB SPIFFS`
5. **PSRAM**: `OPI PSRAM` или если не даёт — Disabled (не критично)
6. USB CDC On Boot: Enable, USB Mode: Hardware CDC and JTAG
7. Upload Speed 921600, кабель в **USB-C ESP** (не micro-USB модема)
8. Если не прошивается — зажать **BOOT** на плате перед Upload.

Библиотека `esp32_ingest` из `firmware/esp32_ingest/` — в `Documents/Arduino/libraries/esp32_ingest/` (обязательно `gsm_a7670.h`).

**Питание в поле:** VIN **5 В ≥ 2 А** (USB ПК LTE не тянет). Схема **24 В БП → DC‑DC → VIN + петли 4–20 мА**: [POWER_WIRING.md](../../POWER_WIRING.md).

---

## Первый запуск (Serial 115200 бод, CRLF/NL)

Плата загрузится, попытается включить модем с указанными пинами, а если не прокатит — автоподбор из [gsm_a7670.h:L539-L574](file:///c:/Users/Admin2/Desktop/HW2.0/hydrowin/hydrowin/firmware/esp32_ingest/gsm_a7670.h#L539-L574) попробует 8 карт.

```
WIFI СЕТЬ_2.4ГГЦ|ПАРОЛЬ              # 5ГГЦ ESP32-S3 НЕ ВИДИТ!
GSM internet|mts|mts                   # APN / LOGIN / PASS
MACHINE 00000000-0000-0000-0000-000000000000
KEY ваш_длинный_ключ_устройства
LINK auto                              # или link wifi / gsm
CFG                                    # печать всего конфига
```

Через 2–3 минуты на открытом небе в диагностике появится:
```
GPS mode: modem-gnss (SIM7670G internal, GPS+GLONASS+BeiDou)
GPS: 55.12345, 37.54321  acc=15 m
```

Разъёмы антенн: **MAIN = LTE**, **GNSS = встроенный GPS-чип**.
