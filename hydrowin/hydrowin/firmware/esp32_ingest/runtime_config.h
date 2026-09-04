#ifndef RUNTIME_CONFIG_H
#define RUNTIME_CONFIG_H

#include <Arduino.h>
#include <Preferences.h>
#include <string.h>
#include "config.h"

// Рабочие настройки блока в NVS.
//   WIFI ssid|password
//   GSM apn|user|pass
//   API host|port [|tls]     tls=1 → https даже на порту ≠ 443
//   LINK wifi | LINK gsm | LINK auto
//   MACHINE <uuid>
//   DEVICE <device_id>
//   KEY <device_key>
//   CFG

struct RuntimeConfig {
    char wifiSsid[33];
    char wifiPass[65];
    char gsmApn[49];
    char gsmUser[33];
    char gsmPass[33];
    char apiHost[65];
    uint16_t apiPort;
    bool apiTls;  // true → https://
    uint8_t linkMode;
    char machineId[48];
    char deviceId[40];
    char deviceKey[64];
};

static RuntimeConfig g_rt;
static Preferences g_rtPrefs;

inline const RuntimeConfig& rtConfig() { return g_rt; }

inline void _rtCopy(char* dst, size_t n, const char* src)
{
    if (src == nullptr) src = "";
    strncpy(dst, src, n - 1);
    dst[n - 1] = '\0';
}

inline String rtApiBase()
{
    char buf[112];
    const bool tls = g_rt.apiTls || g_rt.apiPort == 443;
    if (tls) {
        if (g_rt.apiPort == 443) {
            snprintf(buf, sizeof(buf), "https://%s", g_rt.apiHost);
        } else {
            snprintf(
                buf, sizeof(buf), "https://%s:%u", g_rt.apiHost, g_rt.apiPort);
        }
    } else if (g_rt.apiPort == 80) {
        snprintf(buf, sizeof(buf), "http://%s", g_rt.apiHost);
    } else {
        snprintf(buf, sizeof(buf), "http://%s:%u", g_rt.apiHost, g_rt.apiPort);
    }
    return String(buf);
}

inline bool machineIdConfigured()
{
    const char* m = g_rt.machineId;
    if (m == nullptr || m[0] == '\0') return false;
    if (strcmp(m, "UNSET") == 0) return false;
    if (strncmp(m, "UNSET", 5) == 0) return false;
    return strlen(m) == 36;
}

inline bool deviceKeyConfiguredRt()
{
    const char* k = g_rt.deviceKey;
    if (k == nullptr || k[0] == '\0') return false;
    if (strcmp(k, "SET_VIA_SERIAL_KEY_COMMAND") == 0) return false;
    if (strcmp(k, "SET_VIA_SERVER_ENV") == 0) return false;
    return strlen(k) >= 8;
}

inline bool _nvsIsPlaceholderMachine(const char* m)
{
    if (m == nullptr || m[0] == '\0') return true;
    if (strcmp(m, "UNSET") == 0) return true;
    if (strncmp(m, "UNSET", 5) == 0) return true;
    return strlen(m) != 36;
}

inline bool _nvsIsPlaceholderKey(const char* k)
{
    if (k == nullptr || k[0] == '\0') return true;
    if (strcmp(k, "SET_VIA_SERIAL_KEY_COMMAND") == 0) return true;
    if (strcmp(k, "SET_VIA_SERVER_ENV") == 0) return true;
    return strlen(k) < 8;
}

inline bool _nvsIsPlaceholderDeviceId(const char* d)
{
    if (d == nullptr || d[0] == '\0') return true;
    if (strcmp(d, "SET_VIA_SERIAL_KEY_COMMAND") == 0) return true;
    if (strcmp(d, "UNSET") == 0) return true;
    return false;
}

inline void loadRuntimeConfig()
{
    g_rtPrefs.begin("hw_net", false);

    _rtCopy(g_rt.wifiSsid, sizeof(g_rt.wifiSsid),
            g_rtPrefs.getString("wifi_ssid", WIFI_SSID).c_str());
    _rtCopy(g_rt.wifiPass, sizeof(g_rt.wifiPass),
            g_rtPrefs.getString("wifi_pass", WIFI_PASSWORD).c_str());
    _rtCopy(g_rt.gsmApn, sizeof(g_rt.gsmApn),
            g_rtPrefs.getString("gsm_apn", GSM_APN).c_str());
    _rtCopy(g_rt.gsmUser, sizeof(g_rt.gsmUser),
            g_rtPrefs.getString("gsm_user", GSM_APN_USER).c_str());
    _rtCopy(g_rt.gsmPass, sizeof(g_rt.gsmPass),
            g_rtPrefs.getString("gsm_pass", GSM_APN_PASS).c_str());
    _rtCopy(g_rt.apiHost, sizeof(g_rt.apiHost),
            g_rtPrefs.getString("api_host", API_HOST).c_str());
    g_rt.apiPort = (uint16_t)g_rtPrefs.getUInt("api_port", API_PORT);
    g_rt.apiTls = g_rtPrefs.getBool("api_tls", API_PORT == 443);
    g_rt.linkMode = (uint8_t)g_rtPrefs.getUChar("link_mode", (uint8_t)LINK_MODE);
    _rtCopy(g_rt.machineId, sizeof(g_rt.machineId),
            g_rtPrefs.getString("machine_id", MACHINE_ID).c_str());
    _rtCopy(g_rt.deviceId, sizeof(g_rt.deviceId),
            g_rtPrefs.getString("device_id", DEVICE_ID).c_str());
    _rtCopy(g_rt.deviceKey, sizeof(g_rt.deviceKey),
            g_rtPrefs.getString("device_key", DEVICE_KEY).c_str());

    // NVS от старых прошивок (UNSET / SET_VIA_…) перекрывает config.h.
    // Если в прошивке уже прописаны живые MACHINE/KEY — берём их.
    if (_nvsIsPlaceholderMachine(g_rt.machineId) &&
        !_nvsIsPlaceholderMachine(MACHINE_ID)) {
        _rtCopy(g_rt.machineId, sizeof(g_rt.machineId), MACHINE_ID);
    }
    if (_nvsIsPlaceholderKey(g_rt.deviceKey) &&
        !_nvsIsPlaceholderKey(DEVICE_KEY)) {
        _rtCopy(g_rt.deviceKey, sizeof(g_rt.deviceKey), DEVICE_KEY);
    }
    if (_nvsIsPlaceholderDeviceId(g_rt.deviceId) &&
        !_nvsIsPlaceholderDeviceId(DEVICE_ID)) {
        _rtCopy(g_rt.deviceId, sizeof(g_rt.deviceId), DEVICE_ID);
    }
}

inline bool saveWifiConfig(const char* ssid, const char* pass)
{
    if (ssid == nullptr || strlen(ssid) == 0) return false;
    _rtCopy(g_rt.wifiSsid, sizeof(g_rt.wifiSsid), ssid);
    _rtCopy(g_rt.wifiPass, sizeof(g_rt.wifiPass), pass != nullptr ? pass : "");
    g_rtPrefs.putString("wifi_ssid", g_rt.wifiSsid);
    g_rtPrefs.putString("wifi_pass", g_rt.wifiPass);
    return true;
}

inline bool saveGsmConfig(const char* apn, const char* user, const char* pass)
{
    if (apn == nullptr || strlen(apn) == 0) return false;
    _rtCopy(g_rt.gsmApn, sizeof(g_rt.gsmApn), apn);
    _rtCopy(g_rt.gsmUser, sizeof(g_rt.gsmUser), user != nullptr ? user : "");
    _rtCopy(g_rt.gsmPass, sizeof(g_rt.gsmPass), pass != nullptr ? pass : "");
    g_rtPrefs.putString("gsm_apn", g_rt.gsmApn);
    g_rtPrefs.putString("gsm_user", g_rt.gsmUser);
    g_rtPrefs.putString("gsm_pass", g_rt.gsmPass);
    return true;
}

inline bool _rtHostSafe(const char* host)
{
    if (host == nullptr || host[0] == '\0') return false;
    for (const char* p = host; *p; ++p) {
        const unsigned char c = (unsigned char)*p;
        // AT+HTTPPARA URL: кавычки / CR/LF / backslash ломают AT-строку.
        if (c == '"' || c == '\'' || c == '\\' || c == '\r' || c == '\n' ||
            c == ' ' || c < 0x20) {
            return false;
        }
    }
    return true;
}

inline bool _rtDeviceKeySafe(const char* key)
{
    if (key == nullptr) return false;
    for (const char* p = key; *p; ++p) {
        const unsigned char c = (unsigned char)*p;
        if (c == '"' || c == '\'' || c == '\\' || c == '\r' || c == '\n' ||
            c == ' ' || c == '\t' || c < 0x20) {
            return false;
        }
    }
    return true;
}

inline bool saveApiConfig(const char* host, uint16_t port, bool tls = false)
{
    if (host == nullptr || strlen(host) == 0 || port == 0) return false;
    if (!_rtHostSafe(host)) return false;
    _rtCopy(g_rt.apiHost, sizeof(g_rt.apiHost), host);
    g_rt.apiPort = port;
    g_rt.apiTls = tls || (port == 443);
    g_rtPrefs.putString("api_host", g_rt.apiHost);
    g_rtPrefs.putUInt("api_port", g_rt.apiPort);
    g_rtPrefs.putBool("api_tls", g_rt.apiTls);
    return true;
}

inline const char* linkModeName(uint8_t mode)
{
    if (mode == LINK_GSM) return "gsm";
    if (mode == LINK_AUTO) return "auto";
    return "wifi";
}

inline bool saveLinkMode(uint8_t mode)
{
    if (mode != LINK_WIFI && mode != LINK_GSM && mode != LINK_AUTO) return false;
    g_rt.linkMode = mode;
    g_rtPrefs.putUChar("link_mode", g_rt.linkMode);
    return true;
}

inline bool saveMachineId(const char* machineId)
{
    if (machineId == nullptr) return false;
    char buf[48];
    _rtCopy(buf, sizeof(buf), machineId);
    for (char* p = buf; *p; ++p) {
        if (*p == ' ' || *p == '\t') {
            *p = '\0';
            break;
        }
    }
    if (strlen(buf) != 36) return false;
    int dashes = 0;
    for (const char* p = buf; *p; ++p) {
        if (*p == '-') dashes++;
    }
    if (dashes != 4) return false;

    _rtCopy(g_rt.machineId, sizeof(g_rt.machineId), buf);
    g_rtPrefs.putString("machine_id", g_rt.machineId);
    return true;
}

inline bool saveDeviceId(const char* deviceId)
{
    if (deviceId == nullptr || strlen(deviceId) == 0) return false;
    char buf[40];
    _rtCopy(buf, sizeof(buf), deviceId);
    for (char* p = buf; *p; ++p) {
        if (*p == ' ' || *p == '\t') {
            *p = '\0';
            break;
        }
    }
    if (buf[0] == '\0') return false;
    _rtCopy(g_rt.deviceId, sizeof(g_rt.deviceId), buf);
    g_rtPrefs.putString("device_id", g_rt.deviceId);
    return true;
}

inline bool saveDeviceKey(const char* deviceKey)
{
    if (deviceKey == nullptr || strlen(deviceKey) < 8) return false;
    if (strlen(deviceKey) > 63) return false;
    if (!_rtDeviceKeySafe(deviceKey)) return false;
    char buf[64];
    _rtCopy(buf, sizeof(buf), deviceKey);
    for (char* p = buf; *p; ++p) {
        if (*p == ' ' || *p == '\t') {
            *p = '\0';
            break;
        }
    }
    if (strlen(buf) < 8) return false;
    if (!_rtDeviceKeySafe(buf)) return false;
    _rtCopy(g_rt.deviceKey, sizeof(g_rt.deviceKey), buf);
    g_rtPrefs.putString("device_key", g_rt.deviceKey);
    return true;
}

inline void printRuntimeConfig()
{
    Serial.println("--- runtime config (NVS) ---");
    Serial.printf("LINK: %s\n", linkModeName(g_rt.linkMode));
    Serial.printf("WIFI: SSID='%s' pass_len=%u\n",
                  g_rt.wifiSsid, (unsigned)strlen(g_rt.wifiPass));
    Serial.printf("GSM:  APN=%s user=%s\n", g_rt.gsmApn, g_rt.gsmUser);
    Serial.printf("API:  %s (tls=%u)\n", rtApiBase().c_str(), g_rt.apiTls ? 1 : 0);
    Serial.printf("MACHINE: %s%s\n",
                  g_rt.machineId,
                  machineIdConfigured() ? "" : "  ← задайте MACHINE <uuid>");
    Serial.printf("DEVICE:  %s\n", g_rt.deviceId);
    Serial.printf("KEY:     %s\n",
                  deviceKeyConfiguredRt() ? "***(set)***" : "(empty)");
}

/** BLE setup PIN: 6 цифр в NVS, не из MAC и не в advertising name. */
#ifndef BLE_SETUP_PIN_LEN
#define BLE_SETUP_PIN_LEN 7  // 6 digits + NUL
#endif

static uint32_t g_blePinGeneration = 1;

inline uint32_t blePinGeneration() { return g_blePinGeneration; }

inline void _bleGeneratePinDigits(char* out, size_t n)
{
    if (out == nullptr || n < 7) return;
    // 100000..999999 — не совпадает с 4-hex хвостом MAC.
    const uint32_t v = 100000u + (esp_random() % 900000u);
    snprintf(out, n, "%06lu", (unsigned long)v);
}

inline bool _blePinLooksLegacyMacHex(const char* pin)
{
    if (pin == nullptr || strlen(pin) != 4) return false;
    for (int i = 0; i < 4; i++) {
        const char c = pin[i];
        const bool hex = (c >= '0' && c <= '9') || (c >= 'A' && c <= 'F') ||
                         (c >= 'a' && c <= 'f');
        if (!hex) return false;
    }
    return true;
}

/** Загрузить PIN из NVS или создать новый. Legacy MAC-hex (4 символа) ротируется. */
inline void loadOrCreateBleSetupPin(char* out, size_t n)
{
    if (out == nullptr || n < 7) return;
    Preferences p;
    p.begin("hw_ble", false);
    String stored = p.getString("pin", "");
    if (stored.length() >= 6 && stored.length() <= 8 &&
        !_blePinLooksLegacyMacHex(stored.c_str())) {
        _rtCopy(out, n, stored.c_str());
        p.end();
        return;
    }
    _bleGeneratePinDigits(out, n);
    p.putString("pin", out);
    g_blePinGeneration++;
    p.end();
}

inline void regenerateBleSetupPin(char* out, size_t n)
{
    if (out == nullptr || n < 7) return;
    Preferences p;
    p.begin("hw_ble", false);
    _bleGeneratePinDigits(out, n);
    p.putString("pin", out);
    g_blePinGeneration++;
    p.end();
}

#endif
