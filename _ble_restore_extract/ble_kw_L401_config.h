#ifndef CONFIG_H
#define CONFIG_H

// HydroWin ESP32 ingest — на базе SCADA V8 (iot_server) + POST в облако
#define VERSION "HydroWin-V8.1"

// ── Wi‑Fi предприятия ───────────────────────────────────────────────────────
#define WIFI_SSID      "YOUR_WIFI_SSID"
#define WIFI_PASSWORD  "YOUR_WIFI_PASSWORD"

// ── HydroWin API ────────────────────────────────────────────────────────────
// Без слэша в конце. Прод:
#define API_BASE       "http://5.165.27.141:8090"

// backend/.env → DEFAULT_DEVICE_KEY (должен быть привязан к MACHINE_ID)
#define DEVICE_KEY     "hydro-demo-device-key-change-me"

// Произвольная метка платы (для логов)
#define DEVICE_ID      "ESP32-HYDRO-01"

// UUID машины из приложения / GET /v1/machines — обязательно свой на каждую плату
#define MACHINE_ID     "PASTE-MACHINE-UUID-HERE"

// Как часто слать на сервер (мс). Чтение датчиков чаще — в loop.
#define SEND_INTERVAL_MS  2000

#endif
