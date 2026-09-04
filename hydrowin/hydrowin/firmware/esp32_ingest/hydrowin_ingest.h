#ifndef HYDROWIN_INGEST_H
#define HYDROWIN_INGEST_H

#include <WiFi.h>
#include <HTTPClient.h>
#include <WiFiClient.h>
#include <WiFiClientSecure.h>
#include <time.h>

#include "config.h"
#include "sensors.h"
#include "runtime_config.h"
#include "gsm_a7670.h"
#include "offline_queue.h"
#include "mqtt_telemetry.h"
#include "tls_certs.h"
#include "telemetry_buffer.h"
#include "telemetry_policy.h"

static uint32_t s_msgCounter = 0;
static A7670Modem s_modem;
static uint32_t s_wifiDisconnectedSinceMs = 0;

inline A7670Modem& hydroGsmModem() { return s_modem; }

inline bool deviceKeyConfigured() { return deviceKeyConfiguredRt(); }

inline String makeMessageId()
{
    char buf[48];
    snprintf(buf, sizeof(buf), "hw-%08lx-%lu",
             (unsigned long)esp_random(),
             (unsigned long)(++s_msgCounter));
    return String(buf);
}

inline String utcNowIso()
{
    time_t now = time(nullptr);
    if (now < 1700000000) {
        char buf[32];
        snprintf(buf, sizeof(buf), "1970-01-01T00:00:%02luZ",
                 (unsigned long)((millis() / 1000) % 60));
        return String(buf);
    }
    struct tm tm;
    gmtime_r(&now, &tm);
    char buf[32];
    strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", &tm);
    return String(buf);
}

inline String buildTelemetryJson()
{
    return telemetryBufferBuildJson();
}

inline void sampleTelemetry()
{
    telemetryBufferPushSample();
}

inline const char* wifiStatusName(wl_status_t st)
{
    switch (st) {
    case WL_IDLE_STATUS: return "IDLE";
    case WL_NO_SSID_AVAIL: return "NO_SSID (сеть не найдена — 5GHz/имя/дальность)";
    case WL_SCAN_COMPLETED: return "SCAN_DONE";
    case WL_CONNECTED: return "CONNECTED";
    case WL_CONNECT_FAILED: return "CONNECT_FAILED (часто неверный пароль)";
    case WL_CONNECTION_LOST: return "CONNECTION_LOST";
    case WL_DISCONNECTED: return "DISCONNECTED";
    default: return "OTHER";
    }
}

inline bool ensureWifi()
{
    if (WiFi.status() == WL_CONNECTED) {
        s_wifiDisconnectedSinceMs = 0;
        return true;
    }

    const RuntimeConfig& cfg = rtConfig();
    if (cfg.wifiSsid[0] == '\0') {
        Serial.println("Wi-Fi: SSID пустой");
        return false;
    }

    const wl_status_t cur = WiFi.status();
    if (s_wifiDisconnectedSinceMs == 0) {
        s_wifiDisconnectedSinceMs = millis();
    }
    const uint32_t downFor = millis() - s_wifiDisconnectedSinceMs;

    if ((cur == WL_IDLE_STATUS || cur == WL_DISCONNECTED) && downFor > 15000UL) {
        Serial.println("Wi-Fi: long disconnect → disconnect(false)+begin");
        WiFi.disconnect(false);
        delay(200);
        s_wifiDisconnectedSinceMs = millis();
    } else if (cur == WL_NO_SSID_AVAIL || cur == WL_CONNECT_FAILED ||
               cur == WL_CONNECTION_LOST) {
        WiFi.disconnect(false);
        delay(200);
    }

    Serial.printf("Wi-Fi: подключение к '%s' (pass_len=%u)...\n",
                  cfg.wifiSsid, (unsigned)strlen(cfg.wifiPass));

    WiFi.persistent(false);
    WiFi.setAutoReconnect(true);
    WiFi.mode(WIFI_STA);
    WiFi.setSleep(false);
#if defined(WIFI_POWER_19_5dBm)
    WiFi.setTxPower(WIFI_POWER_19_5dBm);
#endif
    WiFi.disconnect(false);
    delay(100);
    WiFi.begin(cfg.wifiSsid, cfg.wifiPass);

    const uint32_t start = millis();
    wl_status_t last = (wl_status_t)255;
    while (WiFi.status() != WL_CONNECTED && millis() - start < 25000) {
        const wl_status_t st = WiFi.status();
        if (st != last) {
            last = st;
            Serial.printf(" [%d=%s]", (int)st, wifiStatusName(st));
        }
        delay(250);
        digitalWrite(LED_PIN, !digitalRead(LED_PIN));
        Serial.print(".");
    }
    Serial.println();

    if (WiFi.status() != WL_CONNECTED) {
        digitalWrite(LED_PIN, LOW);
        const wl_status_t st = WiFi.status();
        Serial.printf("Wi-Fi: FAIL status=%d (%s)\n", (int)st, wifiStatusName(st));
        if (st == WL_NO_SSID_AVAIL) {
            Serial.println(
                "  → WIFI SCAN: нет SSID = роутер 5 GHz или другое имя.\n"
                "  → Сделайте отдельную сеть только 2.4 GHz.");
        } else if (st == WL_CONNECT_FAILED || st == WL_DISCONNECTED) {
            Serial.println(
                "  → Пароль / шифрование: WPA2-PSK (не WPA3-only).\n"
                "  → Питание VIN 5V 2A; отключите MAC-фильтр.");
        }
        return false;
    }

    s_wifiDisconnectedSinceMs = 0;
    digitalWrite(LED_PIN, HIGH);
    Serial.printf("Wi-Fi OK  IP=%s  RSSI=%d\n",
                  WiFi.localIP().toString().c_str(), WiFi.RSSI());
    return true;
}

inline void initNtp()
{
    Serial.print("NTP... ");
    configTime(0, 0, "pool.ntp.org", "time.nist.gov");
    for (int i = 0; i < 20 && time(nullptr) < 1700000000; i++) delay(250);
    Serial.println(time(nullptr) >= 1700000000 ? "OK" : "skip");
}

inline bool postTelemetryWifi(const String& body)
{
    if (!ensureWifi()) return false;
    if (!deviceKeyConfigured()) {
        Serial.println("HTTPS: нет DEVICE_KEY — Serial: KEY <value>");
        return false;
    }
    if (!machineIdConfigured()) {
        Serial.println("HTTPS: нет MACHINE — Serial: MACHINE <uuid>");
        return false;
    }

    const String url = rtApiBase() + "/v1/ingest/telemetry";
    const bool tls = url.startsWith("https://");

    HTTPClient http;
    WiFiClientSecure secure;
    http.setConnectTimeout(10000);
    http.setTimeout(20000);
    http.setReuse(false);

    bool begun = false;
    if (tls) {
#if TLS_INSECURE
        static bool s_tlsInsecureLogged = false;
        if (!s_tlsInsecureLogged) {
            Serial.println("HTTPS: TLS_INSECURE=1 (без проверки сертификата)");
            s_tlsInsecureLogged = true;
        }
        secure.setInsecure();
#else
        secure.setCACert(TLS_ROOT_CA_ISRG_X1);
#endif
        secure.setTimeout(20000);
        begun = http.begin(secure, url);
    } else {
        Serial.println("HTTPS: отказ — для Wi‑Fi нужен https:// (не http://)");
        return false;
    }
    if (!begun) return false;

    http.addHeader("Content-Type", "application/json");
    http.addHeader("X-Device-Key", rtConfig().deviceKey);
    // close: проще на ESP32; handshake реже за счёт TELEMETRY_BATCH_WIFI_MS.
    http.addHeader("Connection", "close");

    const int code = http.POST(body);
    const String resp = http.getString();
    http.end();
    secure.stop();

#if HYDROWIN_SERIAL_TELEMETRY
    if (code < 0) {
        Serial.printf("HTTPS(Wi-Fi) %d (транспорт/TLS/таймаут)\n", code);
    } else {
        Serial.printf("HTTPS(Wi-Fi) %d\n", code);
        if (resp.length()) Serial.println(resp);
    }
#else
    if (code < 0) {
        Serial.printf("HTTPS(Wi-Fi) fail code=%d url=%s\n", code, url.c_str());
    } else if (code != 200 && code != 202 && code != 204) {
        Serial.printf("HTTPS(Wi-Fi) HTTP %d\n", code);
    }
    (void)resp;
#endif

    if (code == 200 || code == 202 || code == 204) {
        digitalWrite(LED_PIN, LOW);
        delay(80);
        digitalWrite(LED_PIN, HIGH);
        return true;
    }
    if (code < 0) {
        Serial.println("HTTPS: транспорт сбой — Wi‑Fi оставляем, повтор позже");
    }
    return false;
}

inline bool ensureGsm()
{
    if (s_modem.isUnavailable()) return false;
    if (s_modem.isReady()) return true;
    return s_modem.begin();
}

inline bool postTelemetryGsm(const String& body)
{
    if (!ensureGsm()) return false;
    if (!deviceKeyConfigured()) {
        Serial.println("GSM: нет DEVICE_KEY — Serial: KEY <value>");
        return false;
    }
    if (!machineIdConfigured()) {
        Serial.println("GSM: нет MACHINE — Serial: MACHINE <uuid>");
        return false;
    }

    char url[160];
    snprintf(url, sizeof(url), "%s/v1/ingest/telemetry", rtApiBase().c_str());

    char headers[128];
    snprintf(headers, sizeof(headers),
             "X-Device-Key: %s",
             rtConfig().deviceKey);

    int code = -1;
    const bool ok = s_modem.httpPost(url, headers, body.c_str(), &code);
#if HYDROWIN_SERIAL_TELEMETRY
    Serial.printf("HTTP(GSM/A7670) %d\n", code);
#endif

    if (ok) {
        digitalWrite(LED_PIN, LOW);
        delay(80);
        digitalWrite(LED_PIN, HIGH);
    } else {
        s_modem.httpSessionClose();
    }
    return ok;
}

static uint8_t s_activeLink = 255;
static uint32_t s_gsmRetryAfterMs = 0;
static uint32_t s_wifiRetryAfterMs = 0;
static const uint32_t GSM_RETRY_COOLDOWN_MS = 5UL * 60UL * 1000UL;
static const uint32_t WIFI_RETRY_COOLDOWN_MS = 30UL * 1000UL;

inline const char* activeLinkName()
{
    if (s_activeLink == LINK_GSM) return "GSM/A7670";
    if (s_activeLink == LINK_WIFI) return "Wi-Fi";
    return "none";
}

inline uint32_t telemetryBatchMs()
{
    const uint8_t mode = rtConfig().linkMode;
    if (mode == LINK_GSM) return TELEMETRY_BATCH_GSM_MS;
    if (mode == LINK_WIFI) return TELEMETRY_BATCH_WIFI_MS;
    if (s_activeLink == LINK_GSM) return TELEMETRY_BATCH_GSM_MS;
    return TELEMETRY_BATCH_WIFI_MS;
}

inline uint32_t telemetryIdleBatchMs()
{
    const uint8_t mode = rtConfig().linkMode;
    if (mode == LINK_GSM) return TELEMETRY_BATCH_GSM_IDLE_MS;
    if (mode == LINK_WIFI) return TELEMETRY_BATCH_WIFI_IDLE_MS;
    if (s_activeLink == LINK_GSM) return TELEMETRY_BATCH_GSM_IDLE_MS;
    return TELEMETRY_BATCH_WIFI_IDLE_MS;
}

/** Интервал flush: 30 с актив / 5 мин покой (GSM). */
inline uint32_t telemetryFlushIntervalMs()
{
    return telemetryIsIdle() ? telemetryIdleBatchMs() : telemetryBatchMs();
}

inline bool telemetryShouldFlush(uint32_t sinceLastFlushMs)
{
    if (telemetryBufferCount() == 0) return false;
    if (telemetryBufferFull()) return true;
    if (telemetryForceFlush()) {
        return sinceLastFlushMs >= telemetryBatchMs();
    }
    return sinceLastFlushMs >= telemetryFlushIntervalMs();
}

inline bool tryPostWifi(const String& body)
{
    // Физически Wi‑Fi уже есть — сбрасываем cooldown (быстрее вернуться с GSM).
    if (WiFi.status() == WL_CONNECTED) {
        s_wifiRetryAfterMs = 0;
    }
    if (millis() < s_wifiRetryAfterMs) {
        Serial.printf("AUTO/try: Wi-Fi cooldown ещё %lu с\n",
                      (unsigned long)((s_wifiRetryAfterMs - millis()) / 1000));
        return false;
    }
    Serial.println("AUTO/try: Wi-Fi...");

#if TELEMETRY_TRANSPORT == 2
    bool ok = postTelemetryMqtt(body);
    if (!ok) {
        Serial.println("MQTT fail → HTTPS fallback");
        ok = postTelemetryWifi(body);
    }
#else
    const bool ok = postTelemetryWifi(body);
#endif

    if (ok) {
        s_activeLink = LINK_WIFI;
        s_wifiRetryAfterMs = 0;
        return true;
    }
    s_wifiRetryAfterMs = millis() + WIFI_RETRY_COOLDOWN_MS;
    Serial.println("AUTO: Wi-Fi fail → пауза 30 с перед повтором");
    return false;
}

inline bool tryPostGsm(const String& body)
{
    if (s_modem.isUnavailable()) {
        Serial.println("AUTO/try: A7670 недоступен — пропуск");
        return false;
    }
    if (millis() < s_gsmRetryAfterMs) {
        Serial.printf("AUTO/try: GSM cooldown ещё %lu с\n",
                      (unsigned long)((s_gsmRetryAfterMs - millis()) / 1000));
        return false;
    }
    Serial.println("AUTO/try: GSM/A7670...");
    if (postTelemetryGsm(body)) {
        s_activeLink = LINK_GSM;
        s_gsmRetryAfterMs = 0;
        return true;
    }
    if (!s_modem.isUnavailable()) {
        s_gsmRetryAfterMs = millis() + GSM_RETRY_COOLDOWN_MS;
        Serial.println("AUTO: GSM fail → пауза 5 мин перед повтором");
    }
    return false;
}

inline bool postTelemetryAuto(const String& body)
{
    if (s_activeLink == LINK_WIFI) {
        if (tryPostGsm(body)) return true;
        Serial.println("AUTO: GSM недоступен → Wi-Fi");
        if (tryPostWifi(body)) return true;
        return false;
    }
    if (s_activeLink == LINK_GSM) {
        if (tryPostGsm(body)) return true;
        Serial.println("AUTO: GSM упал → Wi-Fi");
        return tryPostWifi(body);
    }

    if (tryPostGsm(body)) return true;
    Serial.println("AUTO: GSM недоступен → Wi-Fi");
    return tryPostWifi(body);
}

inline bool initLink()
{
    printRuntimeConfig();
    const uint8_t mode = rtConfig().linkMode;

    if (mode == LINK_GSM) {
        Serial.println("Режим связи: GSM/LTE (A7670)");
        Serial.println("A7670: init отложен до первой телеметрии");
        s_activeLink = LINK_GSM;
        return true;
    }

    if (mode == LINK_AUTO) {
        Serial.println("Режим связи: AUTO (A7670 ↔ Wi-Fi, приоритет GSM)");
        s_activeLink = LINK_GSM;
        if (WiFi.status() == WL_CONNECTED || ensureWifi()) {
            initNtp();
            Serial.println("AUTO: Wi-Fi доступен, но старт/передача с приоритетом GSM");
        } else {
            Serial.println("AUTO: Wi-Fi недоступен — стартуем на A7670");
        }
        return true;
    }

    Serial.println("Режим связи: Wi-Fi");
    s_activeLink = LINK_WIFI;
    ensureWifi();
    initNtp();
    return true;
}

inline bool deliverTelemetry(const String& body)
{
    const uint8_t mode = rtConfig().linkMode;
    if (mode == LINK_AUTO) {
        Serial.printf("Link path: AUTO (active=%s)\n", activeLinkName());
        return postTelemetryAuto(body);
    }
    if (mode == LINK_GSM) return postTelemetryGsm(body);

#if TELEMETRY_TRANSPORT == 2
    if (postTelemetryMqtt(body)) return true;
    Serial.println("MQTT fail → HTTPS");
    return postTelemetryWifi(body);
#else
    return postTelemetryWifi(body);
#endif
}

inline bool postTelemetry()
{
    if (telemetryBufferCount() == 0) return true;

    if (!machineIdConfigured() || !deviceKeyConfigured()) {
        Serial.println("ingest: MACHINE/KEY не заданы — пакет в offline");
        const String body = buildTelemetryJson();
        enqueueOfflineTelemetry(body);
        telemetryBufferClear();
        return false;
    }

    const String body = buildTelemetryJson();
    const String base = rtApiBase();
    const uint16_t n = telemetryBufferCount();

#if HYDROWIN_SERIAL_TELEMETRY
    Serial.println("\n--- ingest batch ---");
    Serial.printf("rows=%u  ~%u bytes  mode=%s\n",
                  (unsigned)n,
                  (unsigned)body.length(),
                  telemetryIsIdle() ? "IDLE" : "ACTIVE");
    Serial.printf("HTTPS: %s/v1/ingest/telemetry\n", base.c_str());
#else
    (void)base;
    (void)n;
#endif

#if TELEMETRY_TRANSPORT == 2
    mqttLoop();
#endif
    const bool ok = deliverTelemetry(body);
    telemetryBufferClear();

    if (ok) {
        telemetryPolicyOnFlush();
        flushOfflineQueue([](const String& queued) {
            const String fixed = rewriteQueuedTelemetryIds(
                queued, rtConfig().machineId, rtConfig().deviceId);
            return deliverTelemetry(fixed);
        });
        return true;
    }

    enqueueOfflineTelemetry(body);
    printOfflineQueueStatus();
    return false;
}

#endif
