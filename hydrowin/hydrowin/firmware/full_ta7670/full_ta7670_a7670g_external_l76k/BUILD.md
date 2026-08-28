# HydroWin — full_ta7670_a7670g_external_l76k
## (Плата LILYGO T‑A7670G‑S3 ESP32-S3 — ВНЕШНИЙ GPS L76K + SIM-слот)

Прошивка для **модуля беспроводной связи LILYGO T‑A7670G‑S3 с GPS L76K**:
- 6 каналов датчиков 4–20 мА
- BLE v2 (AUTH PIN) + настройка через Serial/BLE
- **Внешний GPS L76K по UART2** (ESP RX=**45** ← TX L76K, ESP TX=**48** → RX L76K)
- **У модема A7670G нет встроенного GNSS** — только внешний L76K на плате
- GPS работает **НЕЗАВИСИМО от LTE/SIM** — координаты есть даже без SIM!
- Связь LINK_AUTO по умолчанию: LTE A7670G first → fallback Wi-Fi
- HTTPS ingest + offline-очередь LittleFS на 120 пакетов

Плата: **T‑A7670G‑S3 Standard** (шелк. `IOxx` = GPIO). Не путать с T‑SIM7670G‑S3 (H707).

---

## Распиновка T‑A7670G‑S3 Standard (+ L76K)

| Интерфейс | Сигнал | Подпись / GPIO | Примечание |
|---|---|---|---|
| **LTE A7670G** (Serial1) | RX (← TX модема) | **IO05** | 115200 8N1 |
| | TX (→ RX модема) | **IO04** | |
| | PWRKEY | **IO46** | |
| | DTR | **IO07** | idle LOW |
| | RING | **IO06** | |
| **GPS L76K** (Serial2) | RX (← TX L76K) | **IO45** | уже на PCB |
| | TX (→ RX L76K) | **IO48** | уже на PCB |
| | WAKE | **IO00** | |
| | Антенна | разъём **GPS** | не MAIN LTE |
| **Датчики 4–20 мА** | CH0 давление P0 | **IO01** | вкл, шунт 150 Ω → GND |
| | CH1 температура T1 | **IO09** | выкл |
| | CH2 температура T2 | **IO14** | выкл |
| | CH3 давление P1 | **IO15** | выкл |
| | CH4 | **IO16** | выкл |
| I2C (не датчики) | SCL / SDA | **IO02 / IO03** | ❌ I2C/Qwiic |
| LED / SD SCK | | **IO12** | не для датчика |
| Battery ADC | | **IO08** | ❌ не датчик |
| Solar ADC | | **IO18** | ❌ не датчик |

⚠️ На ESP32-S3 АЦП только **GPIO 1…20**. Пины **IO35+** для датчиков нельзя — будет reboot (`LoadProhibited`).  
⚠️ **Не паять датчики на:** **IO02**, **IO03**, IO04–IO08, IO10–IO13, IO17, IO18, IO35+, IO42, IO45, IO46, IO48.

---

## Arduino library `esp32_ingest`

Папка: `Documents/Arduino/libraries/esp32_ingest`  
Внутри — заголовки из `firmware/esp32_ingest/`. Используется **`gsm_a7670.h`** (SIM900A удалён).

---

## Сборка в Arduino IDE

1. Откройте [full_ta7670_a7670g_external_l76k.ino](file:///c:/Users/Admin2/Desktop/HW2.0/hydrowin/hydrowin/firmware/full_ta7670/full_ta7670_a7670g_external_l76k/full_ta7670_a7670g_external_l76k.ino)
2. **Tools** (T‑A7670G‑S3 Standard = 16MB Flash + **2MB QSPI PSRAM**):

| Параметр | Значение |
|---|---|
| Board | **ESP32S3 Dev Module** |
| USB CDC On Boot | **Enabled** |
| CPU Frequency | 240MHz (WiFi) |
| Flash Mode | **QIO 80MHz** |
| Flash Size | **16MB (128Mb)** |
| Partition Scheme | Huge APP (3MB No OTA / 1MB SPIFFS) или 16M Flash (3MB APP/9.9MB FATFS) |
| **PSRAM** | **QSPI PSRAM** (не OPI!) |
| Upload Speed | 921600 (при сбоях — 115200) |
| USB Mode | Hardware CDC and JTAG |

⚠️ Если в логе `octal_psram: PSRAM chip is not connected` — в Tools стоит **OPI PSRAM**. Смените на **QSPI PSRAM** и залейте снова.

3. Кабель USB в порт **ESP-USB** (программирование), не Modem.
4. Питание VIN **5 В ≥ 2 А** или LiPo 3.7В. От USB ПК LTE часто не тянет.  
   Полевая схема **24 В БП → DC‑DC → VIN + петли 4–20 мА**: [POWER_WIRING.md](../../POWER_WIRING.md).

---

## Первый запуск (Serial Monitor 115200 бод, NL/CRLF)

Отправляйте построчно:
```
WIFI СЕТЬ_2.4GHZ|ПАРОЛЬ                         # 5 ГГц ESP32 НЕ ПОДДЕРЖИВАЕТ!
GSM internet|mts|mts                             # APN / LOGIN / PASS оператора
MACHINE 00000000-0000-0000-0000-000000000000     # UUID из админки
KEY ваш_длинный_ключ_устройства__________________
LINK auto                                         # сначала LTE → при ошибке Wi-Fi
CFG                                               # печать всего конфига в NVS
```

⚠️ Без `MACHINE <uuid>` и `KEY <device_key>` запрос на ingest backend **не отправляется** — данные накапливаются в `LittleFS:/q/` и отправятся пачкой, как только появится связь.

---

## Проверка работы

| Что | Как выглядит успех |
|---|---|
| **GPS L76K (даже без SIM!)** | `GPS mode: external-l76k | UART2 RX=45 ← TX L76K … NMEA=… B`<br>`GPS: 55.12345, 37.54321  acc≈10 m (L76K)`<br>Первый фикс: **30–120 сек на открытом небе**. |
| **LTE** | `A7670: SIM READY` → `A7670: готов к HTTPS` → `A7670 HTTP 200` |
| **Wi-Fi fallback** | `Wi-Fi OK  IP=192.168.x.x  RSSI=-52` → `HTTPS(Wi-Fi) 200 OK` |
| **Датчики 4–20 мА** | `SHOW` → токи **4.0–20.0 мА**; 0.01=OPEN (обрыв), >21.0=SHORT (КЗ) |
| **Offline очередь** | Нет связи → `offline: saved /q/NNNNN.json queue=X` <br> Связь появилась → `offline: flush batch=8 … queue=0` |

GPS-антенна — в разъём с маркировкой **«GPS»** (не MAIN LTE!).

---

## Полезные Serial-команды

Команда | Описание
---|---
`HELP` | Список всех команд
`CFG` | Текущий конфиг
`WIFI SCAN` | Сканирование сетей 2.4 ГГц (список + RSSI)
`SHOW` | Датчики 4–20 мА
`GSMAT AT+CSQ` | Уровень сигнала LTE: 99=нет, 0..31=где ≥12 хорошо
`GSMAT AT+CPIN?` | Готовность SIM
`GSMAT AT+CPSI?` | Текущая сотая (LAC/CID/MCC/MNC)
`GSMRETRY` | Рестарт GSM-модема после смены SIM
`QUEUE CLEAR` | Очистить оффлайн-очередь
`RESET 0` … `RESET 5` | Сброс калибровки одного канала датчика
