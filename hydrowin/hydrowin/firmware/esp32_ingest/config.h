/*
 * HydroWin ESP32 — конфигурация блока
 *
 * Связь: Wi‑Fi (офис) или LTE A7670G (производство, T‑A7670G‑S3).
 * Калибровка 4–20 мА — в NVS (CAL / ZERO / MATCH).
 * Инженерные значения датчиков — целые (бар, °C).
 */

#ifndef CONFIG_H
#define CONFIG_H

#define VERSION "HydroWin-V10.1"

// ── Режим связи ─────────────────────────────────────────────────────────────
#define LINK_WIFI 0
#define LINK_GSM  1   // LTE A7670G
#define LINK_AUTO 2

#ifndef LINK_MODE
#define LINK_MODE LINK_AUTO
#endif

// ── Wi‑Fi (завод: Serial WIFI / BLE; не коммитить пароли) ───────────────────
#define WIFI_SSID      ""
#define WIFI_PASSWORD  ""

// ── A7670G LTE (LINK_GSM / AUTO) ────────────────────────────────────────────
// Пины по умолчанию — classic ESP32 + внешний A7670.
// LILYGO T‑A7670G‑S3: переопределите в full_ta7670_ingest.ino.
#ifndef A7670_RX_PIN
#define A7670_RX_PIN     17
#endif
#ifndef A7670_TX_PIN
#define A7670_TX_PIN     16
#endif
#ifndef A7670_PWRKEY_PIN
#define A7670_PWRKEY_PIN 15
#endif
#ifndef A7670_BAUD
#define A7670_BAUD       115200
#endif
#ifndef A7670_PWRKEY_MS
#define A7670_PWRKEY_MS  1000
#endif

#define GSM_APN "internet.beeline.ru"
#define GSM_APN_USER "beeline"
#define GSM_APN_PASS "beeline"

// ── HydroWin API ────────────────────────────────────────────────────────────
#define API_HOST       "app.hydrowin.ru"
#define API_PORT       443
#define API_BASE       "https://app.hydrowin.ru"

// Проверка сертификата сервера (ISRG Root X1 в tls_certs.h).
// Лаборатория: -DTLS_INSECURE=1 при сборке Arduino (MITM-риск — только LAN).
#ifndef TLS_INSECURE
#define TLS_INSECURE 0
#endif
#if TLS_INSECURE
#warning "TLS_INSECURE=1 — проверка сертификата сервера ОТКЛЮЧЕНА (не для продакшена)"
#endif

// ── MQTT (только LAN-отладка: TELEMETRY_TRANSPORT 2) ────────────────────────
#define MQTT_HOST "192.168.1.50"
#define MQTT_PORT 1883
#define MQTT_USER "hydrowin-device"
#ifndef MQTT_PASSWORD
#define MQTT_PASSWORD "SET_VIA_SERVER_ENV"
#endif

#ifndef TELEMETRY_TRANSPORT
#define TELEMETRY_TRANSPORT 0
#endif

// DEVICE_KEY / DEVICE_ID / MACHINE — только Serial/BLE/NVS (не коммитить живыми).
#ifndef DEVICE_KEY
#define DEVICE_KEY     ""
#endif
#define DEVICE_ID      ""
/** Пока MACHINE не задан (UUID 36 символов) — ingest запрещён. */
#define MACHINE_ID     ""

// Периодический вывод каналов в Serial (ток мА + значение + fault).
#ifndef HYDROWIN_SERIAL_DIAG
#define HYDROWIN_SERIAL_DIAG 0
#endif
#ifndef HYDROWIN_SERIAL_DIAG_MS
#define HYDROWIN_SERIAL_DIAG_MS 1000UL
#endif
#ifndef HYDROWIN_SERIAL_TELEMETRY
#define HYDROWIN_SERIAL_TELEMETRY 0
#endif

#ifndef EMA_ALPHA
#define EMA_ALPHA 0.45f
#endif

#ifndef HYDROWIN_FORCE_SENSOR_TABLE_ENABLED
#define HYDROWIN_FORCE_SENSOR_TABLE_ENABLED 0
#endif

#ifndef TELEMETRY_SAMPLE_MS
#define TELEMETRY_SAMPLE_MS 1000UL
#endif
// Wi‑Fi HTTPS: реже POST = реже полный TLS handshake (проверка серта на каждое новое соединение).
#ifndef TELEMETRY_BATCH_WIFI_MS
#define TELEMETRY_BATCH_WIFI_MS 5000UL
#endif
// ── Трафик LTE (цель ≤100 МБ/мес) ───────────────────────────────────────────
// Актив: POST каждые 30 с. Покой (≥3 мин стабильности): каждые 5 мин.
// Keep-alive HTTP: TLS не на каждый POST. GPS lat/lon редко (если geo on).
// SIM: IoT/M2M с шагом 1 КБ (не «голосовая» с округлением 10 КБ).
#ifndef TELEMETRY_BATCH_GSM_MS
#define TELEMETRY_BATCH_GSM_MS  30000UL
#endif
/** GSM/LTE: интервал POST при стабильных датчиках (покой). */
#ifndef TELEMETRY_BATCH_GSM_IDLE_MS
#define TELEMETRY_BATCH_GSM_IDLE_MS (5UL * 60UL * 1000UL)
#endif
/** Wi‑Fi: интервал POST при покое (опционально). */
#ifndef TELEMETRY_BATCH_WIFI_IDLE_MS
#define TELEMETRY_BATCH_WIFI_IDLE_MS (60UL * 1000UL)
#endif
/** Сколько секунд подряд значения стабильны → режим покоя. */
#ifndef TELEMETRY_IDLE_STABLE_SEC
#define TELEMETRY_IDLE_STABLE_SEC 180U
#endif
/**
 * Порог |Δvalue| (бар / °C) для выхода из покоя.
 * 2: шум АЦП ±1 не держит блок в ACTIVE 24/7 (критично для 100 МБ).
 */
#ifndef TELEMETRY_IDLE_VALUE_THRESH
#define TELEMETRY_IDLE_VALUE_THRESH 2
#endif
/** A7670: держать HTTP(S)-сессию открытой между батчами (без TLS на каждый POST). */
#ifndef A7670_HTTP_KEEPALIVE
#define A7670_HTTP_KEEPALIVE 1
#endif
/**
 * Закрыть HTTP-сессию после простоя.
 * ≥ idle POST (5 мин) + запас: иначе каждый idle POST = новый TLS.
 */
#ifndef A7670_HTTP_SESSION_IDLE_MS
#define A7670_HTTP_SESSION_IDLE_MS (15UL * 60UL * 1000UL)
#endif
/** Геолокация в телеметрии (full_ta7670: 1). Только lat/lon, редко. */
#ifndef HYDROWIN_GEO_TELEMETRY
#define HYDROWIN_GEO_TELEMETRY 0
#endif
/** GPS в JSON не чаще раза в N мс (экономия; 30 мин под 100 МБ). */
#ifndef HYDROWIN_GPS_TELEM_INTERVAL_MS
#define HYDROWIN_GPS_TELEM_INTERVAL_MS (30UL * 60UL * 1000UL)
#endif
/** Активный батч ≤30 с × 1 Гц → 30 строк; 32 с запасом. */
#ifndef TELEMETRY_BUF_MAX
#define TELEMETRY_BUF_MAX   32
#endif
#ifndef SEND_INTERVAL_MS
#define SEND_INTERVAL_MS TELEMETRY_SAMPLE_MS
#endif
#ifndef LED_PIN
#define LED_PIN           2
#endif

// ── BLE ─────────────────────────────────────────────────────────────────────
#define BLE_TELEMETRY_MS  1000
#define BLE_SERVICE_UUID  "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define BLE_RX_UUID       "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define BLE_TX_UUID       "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

// ── Каналы 4–20 мА (макс. 6 = ADC1) ─────────────────────────────────────────
#define MAX_SENSORS 6

#define OFFLINE_QUEUE_MAX_FILES   120
#define OFFLINE_FLUSH_BATCH         8

struct SensorDef {
    uint8_t pin;
    uint8_t channel;
    float scaleMin;
    float scaleMax;
    const char* label;
    bool enabled;
};

// channel → GPIO (ADC1 classic): 0:35 1:34 2:33 3:32 4:36 5:39
// На ESP32-S3 переопределите SENSOR_TABLE в sketch ДО #include <config.h>.
#ifndef SENSOR_TABLE
#define SENSOR_TABLE \
    { 35, 0,   0.0f, 250.0f, "P0", true  }, \
    { 34, 1, -50.0f, 200.0f, "T1", false }, \
    { 33, 2, -50.0f, 200.0f, "T2", false  }, \
    { 32, 3,   0.0f, 250.0f, "P1", false  }, \
    { 36, 4,   0.0f, 250.0f, "ch4", false }, \
    { 39, 5,   0.0f, 250.0f, "ch5", false }
#endif

#define ADC_SHUNT_OHM   150.0f

#ifndef ADC_MA_GAIN
#define ADC_MA_GAIN     1.0f
#endif

#endif
