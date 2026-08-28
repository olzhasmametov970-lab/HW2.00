#ifndef HYDROWIN_INGEST_H
#define HYDROWIN_INGEST_H

#include <WiFi.h>
#include <HTTPClient.h>
#include <WiFiClient.h>
#include <time.h>

#include "config.h"

extern float temperature;
extern float pressure;

static uint32_t s_msgCounter = 0;

inline String makeMessageId()
{
    char buf[48];
    snprintf(buf, sizeof(buf), "esp32-%08lx-%lu",
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

inline bool ensureWifi()
{
    if (WiFi.status() == WL_CONNECTED) return true;

    Serial.printf("WiFi: reconnect %s ...\n", WIFI_SSID);
    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

    uint32_t start = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - start < 20000) {
        delay(250);
        Serial.print(".");
    }
    Serial.println();

    if (WiFi.status() != WL_CONNECTED) {
        Serial.println("WiFi: FAIL");
        return false;
    }
    Serial.print("WiFi: OK IP=");
    Serial.println(WiFi.localIP());
    return true;
}

inline void initNtp()
{
    configTime(0, 0, "pool.ntp.org", "time.nist.gov");
    for (int i = 0; i < 20 && time(nullptr) < 1700000000; i++) {
        delay(250);
    }
}

/// POST /v1/ingest/telemetry — channel 0 pressure, channel 1 temperature
inline bool postTelemetry()
{
    if (!ensureWifi()) return false;

    String url = String(API_BASE) + "/v1/ingest/telemetry";

    String body;
    body.reserve(320);
    body += "{";
    body += "\"message_id\":\"" + makeMessageId() + "\",";
    body += "\"device_id\":\"" + String(DEVICE_ID) + "\",";
    body += "\"machine_id\":\"" + String(MACHINE_ID) + "\",";
    body += "\"ts\":\"" + utcNowIso() + "\",";
    body += "\"sensors\":[";
    body += "{\"channel\":0,\"value\":" + String(pressure, 2) + "},";
    body += "{\"channel\":1,\"value\":" + String(temperature, 2) + "}";
    body += "]}";

    HTTPClient http;
    WiFiClient client;
    http.begin(client, url);
    http.addHeader("Content-Type", "application/json");
    http.addHeader("X-Device-Key", DEVICE_KEY);
    http.setTimeout(8000);

    Serial.println(body);
    int code = http.POST(body);
    String resp = http.getString();
    http.end();

    Serial.printf("POST %s → %d\n", url.c_str(), code);
    if (resp.length()) Serial.println(resp);

    return code == 202 || code == 200 || code == 204;
}

#endif
