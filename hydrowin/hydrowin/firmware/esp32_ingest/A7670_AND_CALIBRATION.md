# A7670G + калибровка датчиков

SIM900A **снят** с поддержки. LTE — **SIMCom A7670G** (`gsm_a7670.h`).

## Плата LILYGO T‑A7670G‑S3 (карта T‑SIM7670G‑S3, не STAN)

Прошивка: `firmware/full_ta7670/full_ta7670_ingest.ino`

На вашей плате AT заработал на пинах **T‑SIM7670G‑S3** (RX=10 TX=11), не на Standard STAN (5/4/46).

| Сигнал | GPIO | Примечание |
|--------|------|------------|
| Modem RX | `A7670_RX_PIN` **10** | ESP RX ← TX модема |
| Modem TX | `A7670_TX_PIN` **11** | ESP TX → RX модема |
| PWRKEY | `A7670_PWRKEY_PIN` **18** | импульс HIGH ~100 мс, idle LOW |
| DTR | `A7670_DTR_PIN` **9** | держать LOW (не sleep) |
| RESET | `A7670_RESET_PIN` **17** | inactive HIGH (level LOW) |
| GPS | L76K UART ESP RX=**45** TX=**48** | A7670G: GNSS **нет в модеме**. Антенна на разъём **GPS**, не LTE. |
| Baud | 115200 | Serial1 |

ADC датчиков: GPIO **1, 2, 6, 8, 14, 15**. Нельзя: 9/10/11/17/18.

Питание: USB часто не тянет LTE. Нужны **5 V на VIN** или LiPo 3.7 V. Антенна LTE обязательна.  
Полевая схема **24 В БП → DC‑DC → VIN + петли 4–20 мА**: [POWER_WIRING.md](../POWER_WIRING.md).

После прошивки в Serial: `A7670: готов к HTTPS` или `A7670: уже отвечает на AT`. Если снова нет AT — `GSMRETRY`.

## HTTPS на A7670

Модем использует:

- `AT+HTTPINIT` / `HTTPPARA` / `HTTPDATA` / `HTTPACTION=1`
- `AT+CSSLCFG="sslversion",0,3` (TLS 1.2)
- `AT+CSSLCFG="enableSNI",0,1`

При ошибке **715** (handshake): обновите прошивку модема LilyGO, проверьте APN/SIM, SNI.

### Keep-alive (трафик ≤100 МБ/мес)

По умолчанию `A7670_HTTP_KEEPALIVE=1`: сессия `HTTPINIT` **не** закрывается после каждого POST.
TLS handshake — при открытии сессии и после простоя ≥15 мин (`A7670_HTTP_SESSION_IDLE_MS`).

Интервалы (`config.h` / `telemetry_policy.h`):

| Режим | Условие | POST |
|--------|---------|------|
| ACTIVE | \|Δvalue\| > 2 или смена fault | каждые **30 с** |
| IDLE | стабильно ≥3 мин | каждые **5 мин** |

В Serial: `telem: IDLE …` / `telem: ACTIVE …`, команда **`TRAFFIC`**.

**SIM:** берите **IoT/M2M** с шагом тарификации **1 КБ**. Обычная «голосовая» часто округляет сессию до 10 КБ и съедает бюджет.

GPS в JSON (если `HYDROWIN_GEO_TELEMETRY=1`): только `lat`/`lon`, не чаще **раз в 30 мин**.

Время: `AT+CCLK?` кэшируется **раз в час** (`A7670_TIME_SYNC_MS`).

## Калибровка (как раньше)

Значения на выходе — **целые**:

```text
ZERO 0
ZERO 3
MATCH 1 22
SHOW
```

`SHOW`: `… | 9.0mA | 28 OK …` — ток с десятичной, value целое.

## Serial AT

```text
GSMAT AT+CPIN?
GSMAT AT+CSQ
GSMRETRY
```

## Classic ESP32 + внешний A7670

`esp32_ingest.ino` + пины `A7670_*` в `config.h` (17/16/15).  
`LINK gsm` / `LINK auto`.
