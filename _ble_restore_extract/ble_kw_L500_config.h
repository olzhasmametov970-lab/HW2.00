/*
 * Несколько ESP32 на ОДНОЙ станции (одном MACHINE_ID):
 *
 * Плата 1 — давление/температура, каналы 0 и 1
 * Плата 2 — другие датчики, каналы 2 и 3 (и т.д.)
 *
 * 1) Создай ключ: POST /v1/machines/id/{MACHINE_ID}/devices
 * 2) Впиши device_key → DEVICE_KEY, device_id → DEVICE_ID
 * 3) MACHINE_ID одинаковый у всех плат станции
 * 4) В sensors.h / отправке шлите только свои channel
 *
 * Не используй ensure-device с общим DEFAULT_DEVICE_KEY для второй платы —
 * он перезапишет привязку первой.
 */

#ifndef CONFIG_H
#define CONFIG_H

#define VERSION "HydroWin-V8.2"

// ── Wi‑Fi ───────────────────────────────────────────────────────────────────
#define WIFI_SSID      "SVEXC"
#define WIFI_PASSWORD  "kam0123456789"

// ── HydroWin API ────────────────────────────────────────────────────────────
#define API_BASE       "http://5.165.27.141:8090"

// Ключ ЭТОЙ платы (из POST .../devices → device_key). У каждой платы свой!
#define DEVICE_KEY     "PASTE-DEVICE-KEY-FROM-API"

// Метка платы (из API → device_id), напр. ESP32-HYDRO-01
#define DEVICE_ID      "ESP32-HYDRO-01"

// UUID станции — ОДИНАКОВЫЙ у всех плат этой машины
#define MACHINE_ID     "f4c32e25-bbdb-4d89-bb9d-9ac30573606c"

#define SEND_INTERVAL_MS  5000

#endif
