/*
 * HydroWin ESP32 — конфигурация блока
 *
 * Связь: Wi‑Fi (офис) или GSM SIM900A (производство).
 * Калибровка 4–20 мА — в NVS на плате (команды CAL через USB, см. GSM_AND_CALIBRATION.md).
 * Сервер получает готовые value по каналам ingest.
 */

#ifndef CONFIG_H
#define CONFIG_H

#define VERSION "HydroWin-V9.5"

// ── Режим связи ─────────────────────────────────────────────────────────────
#define LINK_WIFI 0
#define LINK_GSM  1
#define LINK_AUTO 2  // Wi‑Fi ↔ GSM: нет одного — пробуем другой

// Офис: LINK_WIFI | Только SIM: LINK_GSM | Универсально: LINK_AUTO
#ifndef LINK_MODE
#define LINK_MODE LINK_AUTO
#endif

// ── Wi‑Fi (если LINK_MODE == LINK_WIFI) ─────────────────────────────────────
#define WIFI_SSID      "R2D2"
#define WIFI_PASSWORD  "1234567890"

// ── SIM900A (если LINK_MODE == LINK_GSM) ────────────────────────────────────
// Проводка (6 проводов, см. GSM_AND_CALIBRATION.md):
//   ESP32 GND  ↔ GND DC‑DC
//   ESP32 GPIO16 (RX2) ↔ SIMTx
//   ESP32 GPIO17 (TX2) ↔ SIMRx  (Open Drain)
//   ESP32 GPIO5        ↔ RESTART (Open Drain, импульс включения)
//   DC‑DC +5V/GND      ↔ белый разъём питания SIM900A (+470 мкФ на питании)

#define SIM_RX_PIN       16   // RX2 ← SIMTx
#define SIM_TX_PIN       17   // TX2 → SIMRx (Open Drain)
#define SIM_PWRKEY_PIN   5    // RESTART / PWRKEY (Open Drain)
#define SIM_UART_BAUD    9600 // заводская скорость SIM900A (не 57600!)

#define SIM_PWRKEY_MS    1800 // длительность LOW при включении (1.5–2 с)

#define GSM_APN          "internet.mts.ru"   // APN оператора SIM
#define GSM_APN_USER     "mts"
#define GSM_APN_PASS     "mts"

// ── HydroWin API ────────────────────────────────────────────────────────────
#define API_HOST       "5.165.27.141"
#define API_PORT       8090
#define API_BASE       "http://5.165.27.141:8090"

#define DEVICE_KEY     "e7xoBRCMKKawHc9jR1pTourGhrbDFBxfSZQRdHt3pA4"
#define DEVICE_ID      "ESP32-HYDRO-01"
#define MACHINE_ID     "f4c32e25-bbdb-4d89-bb9d-9ac30573606c"

#define SEND_INTERVAL_MS  5000
#define LED_PIN           2

// ── Универсальные каналы 4–20 мА (до 10 входов) ─────────────────────────────
// ADC1 (нормально с Wi‑Fi): GPIO35, 34, 33, 32
// ADC2 (на классическом ESP32 при Wi‑Fi часто ЛОМАЕТСЯ): 25, 26, 27, 14, 12, 13
// GPIO12 — strapping-пин: не тяните HIGH при старте.
// Неиспользуемые каналы: DISABLE <ch> через USB (по умолчанию ch3..ch9 выкл).

#define MAX_SENSORS 10

struct SensorDef {
    uint8_t pin;
    uint8_t channel;
    float scaleMin;
    float scaleMax;
    const char* label;
    bool enabled;
};

// channel → GPIO: 0:35 1:34 2:33 3:32 4:25 5:26 6:27 7:14 8:12 9:13
#define SENSOR_TABLE \
    { 35, 0,   0.0f, 250.0f, "ch0", true  }, \
    { 34, 1, -50.0f, 200.0f, "ch1", true  }, \
    { 33, 2,   0.0f, 250.0f, "ch2", true  }, \
    { 32, 3,   0.0f, 250.0f, "ch3", false }, \
    { 25, 4,   0.0f, 250.0f, "ch4", false }, \
    { 26, 5,   0.0f, 250.0f, "ch5", false }, \
    { 27, 6,   0.0f, 250.0f, "ch6", false }, \
    { 14, 7,   0.0f, 250.0f, "ch7", false }, \
    { 12, 8,   0.0f, 250.0f, "ch8", false }, \
    { 13, 9,   0.0f, 250.0f, "ch9", false }

// Шунт на входе 4–20 мА (Ом) — проверь плату
#define ADC_SHUNT_OHM   150.0f

#endif
