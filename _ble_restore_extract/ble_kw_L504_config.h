/*
 * Одна плата = одна машина в приложении.
 *
 * Плата 1 → MACHINE_ID_A + DEVICE_KEY_A + каналы 0,1
 * Плата 2 → MACHINE_ID_B + DEVICE_KEY_B + каналы 0,1
 *
 * Ключ создаётся: POST /v1/machines/id/{MACHINE_ID}/devices
 * (не используй ensure-device для второй платы — он двигает общий ключ)
 */

#ifndef CONFIG_H
#define CONFIG_H

#define VERSION "HydroWin-V8.2"

// ── Wi‑Fi ───────────────────────────────────────────────────────────────────
#define WIFI_SSID      "SVEXC"
#define WIFI_PASSWORD  "kam0123456789"

// ── HydroWin API ────────────────────────────────────────────────────────────
#define API_BASE       "http://5.165.27.141:8090"

// Ключ ЭТОЙ платы (device_key из API). У каждой платы свой!
#define DEVICE_KEY     "PASTE-DEVICE-KEY-FROM-API"

// Метка платы (device_id из API)
#define DEVICE_ID      "ESP32-HYDRO-01"

// UUID машины ЭТОЙ платы (у второй платы — другой UUID)
#define MACHINE_ID     "f4c32e25-bbdb-4d89-bb9d-9ac30573606c"

// Каналы датчиков на этой плате (обычно 0 и 1)
#define CHANNEL_PRESSURE  0
#define CHANNEL_TEMP      1

#define SEND_INTERVAL_MS  5000

#endif
