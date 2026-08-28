/*
 * HydroWin ESP32 — конфигурация блока
 *
 * Связь: Wi‑Fi (офис) или LTE A7670G (производство, T‑A7670G‑S3).
 * Калибровка 4–20 мА — в NVS (CAL / ZERO / MATCH).
 * Инженерные значения датчиков — целые (бар, °C).
 */

#ifndef CONFIG_H
#define CONFIG_H

#define VERSION "HydroWin-V10.0"

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
#define DEVICE_KEY     "TsL4bIW-IBjXrJp1tVTteTsT2p4Sv82gQBKKzAu_F70"
#endif
#define DEVICE_ID      "HW-HYDRO-04"
/** Пока MACHINE не задан (UUID 36 символов) — ingest запрещён. */
#define MACHINE_ID     "8ff52953-d03d-4228-a263-367a6e631e63"

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
#ifndef TELEMETRY_BATCH_GSM_MS
#define TELEMETRY_BATCH_GSM_MS  5000UL
#endif
#ifndef TELEMETRY_BUF_MAX
#define TELEMETRY_BUF_MAX   60
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
