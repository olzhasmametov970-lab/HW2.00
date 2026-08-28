/*
 * HydroWin ESP32 — конфигурация блока
 *
 * Связь: Wi‑Fi (офис) или GSM SIM900A (производство).
 * Калибровка 4–20 мА — в NVS на плате (команды CAL через USB, см. GSM_AND_CALIBRATION.md).
 * Сервер получает готовые value по каналам ingest.
 */

#ifndef CONFIG_H
#define CONFIG_H

#define VERSION "HydroWin-V9.0"

// ── Режим связи ─────────────────────────────────────────────────────────────
#define LINK_WIFI 0
#define LINK_GSM  1

// Офис: LINK_WIFI | Производство без Wi‑Fi: LINK_GSM
#ifndef LINK_MODE
#define LINK_MODE LINK_WIFI
#endif

// ── Wi‑Fi (если LINK_MODE == LINK_WIFI) ─────────────────────────────────────
#define WIFI_SSID      "SVEXC"
#define WIFI_PASSWORD  "kam0123456789"

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
#define SIM_UART_BAUD    9600 // стабильно для коротких проводов без внешних подтяжек

#define SIM_PWRKEY_MS    1800 // длительность LOW при включении (1.5–2 с)

#define GSM_APN          "internet"   // APN оператора SIM
#define GSM_APN_USER     ""
#define GSM_APN_PASS     ""

// ── HydroWin API ────────────────────────────────────────────────────────────
#define API_HOST       "5.165.27.141"
#define API_PORT       8090
#define API_BASE       "http://5.165.27.141:8090"

#define DEVICE_KEY     "e7xoBRCMKKawHc9jR1pTourGhrbDFBxfSZQRdHt3pA4"
#define DEVICE_ID      "ESP32-HYDRO-01"
#define MACHINE_ID     "f4c32e25-bbdb-4d89-bb9d-9ac30573606c"

#define SEND_INTERVAL_MS  5000
#define LED_PIN           2

// ── Датчики 4–20 мА (ADC1, не конфликтуют с Wi‑Fi) ───────────────────────────
// channel = номер канала в ingest / приложении (0, 1, 2…)
// scaleMin/Max — заводские значения; перезаписываются из NVS после калибровки.

#define MAX_SENSORS 4

struct SensorDef {
    uint8_t pin;
    uint8_t channel;
    float scaleMin;
    float scaleMax;
    const char* label;
    bool enabled;
};

#define SENSOR_TABLE \
    { 35, 0,   0.0f, 250.0f, "pressure", true }, \
    { 34, 1, -50.0f, 200.0f, "temp",     true }

// Шунт на входе 4–20 мА (Ом) — проверь плату
#define ADC_SHUNT_OHM   150.0f

#endif
