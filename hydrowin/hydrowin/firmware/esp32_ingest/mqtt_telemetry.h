/*
 * MQTT publish телеметрии (Wi‑Fi). Только при TELEMETRY_TRANSPORT == 2.
 * GSM/A7670: HTTPS keep-alive (A7670_HTTP_KEEPALIVE), не MQTT.
 */

#ifndef MQTT_TELEMETRY_H
#define MQTT_TELEMETRY_H

#include <WiFi.h>
#include "config.h"
#include "runtime_config.h"

#if TELEMETRY_TRANSPORT == 2 && __has_include(<PubSubClient.h>)
#include <PubSubClient.h>
#define HYDROWIN_HAS_PUBSUBCLIENT 1
#else
#define HYDROWIN_HAS_PUBSUBCLIENT 0
#if TELEMETRY_TRANSPORT == 2
#warning "PubSubClient not installed — MQTT disabled"
#endif
#endif

#ifndef MQTT_HOST
#define MQTT_HOST API_HOST
#endif
#ifndef MQTT_PORT
#define MQTT_PORT 1883
#endif
#ifndef MQTT_USER
#define MQTT_USER "hydrowin-device"
#endif
#ifndef MQTT_PASSWORD
#define MQTT_PASSWORD "SET_VIA_SERVER_ENV"
#endif

#if HYDROWIN_HAS_PUBSUBCLIENT

static WiFiClient s_mqttWifi;
static PubSubClient s_mqtt(s_mqttWifi);
static char s_mqttHost[65] = MQTT_HOST;
static uint16_t s_mqttPort = MQTT_PORT;
static char s_mqttUser[33] = MQTT_USER;
static char s_mqttPass[65] = MQTT_PASSWORD;
static uint32_t s_mqttRetryAfterMs = 0;
static const uint32_t MQTT_RETRY_COOLDOWN_MS = 60UL * 1000UL;

inline void mqttSetBroker(const char* host, uint16_t port)
{
    if (host == nullptr || host[0] == '\0') return;
    strncpy(s_mqttHost, host, sizeof(s_mqttHost) - 1);
    s_mqttHost[sizeof(s_mqttHost) - 1] = '\0';
    if (port > 0) s_mqttPort = port;
}

inline void mqttSetAuth(const char* user, const char* pass)
{
    if (user && user[0]) {
        strncpy(s_mqttUser, user, sizeof(s_mqttUser) - 1);
        s_mqttUser[sizeof(s_mqttUser) - 1] = '\0';
    }
    if (pass && pass[0]) {
        strncpy(s_mqttPass, pass, sizeof(s_mqttPass) - 1);
        s_mqttPass[sizeof(s_mqttPass) - 1] = '\0';
    }
}

inline bool mqttEnsureConnected()
{
    if (WiFi.status() != WL_CONNECTED) return false;
    if (s_mqtt.connected()) return true;
    if (millis() < s_mqttRetryAfterMs) return false;

    s_mqtt.setServer(s_mqttHost, s_mqttPort);
    s_mqtt.setBufferSize(2048);
    s_mqtt.setKeepAlive(30);
    s_mqtt.setSocketTimeout(8);

    char clientId[40];
    snprintf(clientId, sizeof(clientId), "hw-%s", rtConfig().deviceId);
    Serial.printf("MQTT connect %s:%u as %s...\n", s_mqttHost, s_mqttPort, s_mqttUser);
    const bool ok = s_mqtt.connect(clientId, s_mqttUser, s_mqttPass);
    Serial.println(ok ? "MQTT OK" : "MQTT fail");
    if (!ok) {
        s_mqttRetryAfterMs = millis() + MQTT_RETRY_COOLDOWN_MS;
    } else {
        s_mqttRetryAfterMs = 0;
    }
    return ok;
}

inline String mqttTopic()
{
    String t = "hydrowin/telemetry/";
    t += rtConfig().deviceId;
    return t;
}

inline String mqttPayloadWithKey(const String& ingestBody)
{
    String body = ingestBody;
    body.trim();
    String out;
    out.reserve(body.length() + 80);
    out += "{\"device_key\":\"";
    out += rtConfig().deviceKey;
    out += "\",";
    if (body.startsWith("{")) {
        out += body.substring(1);
    } else {
        out += body;
        out += "}";
    }
    return out;
}

inline bool postTelemetryMqtt(const String& body)
{
    if (WiFi.status() != WL_CONNECTED) return false;
    if (!mqttEnsureConnected()) return false;

    const String topic = mqttTopic();
    const String payload = mqttPayloadWithKey(body);
    if (payload.length() + 16 > 2048) {
        Serial.println("MQTT: payload too large for buffer");
        return false;
    }
    const bool ok = s_mqtt.publish(topic.c_str(), payload.c_str(), false);
    Serial.printf("MQTT publish %s → %s\n", topic.c_str(), ok ? "OK" : "FAIL");
    if (ok) {
        digitalWrite(LED_PIN, LOW);
        delay(80);
        digitalWrite(LED_PIN, HIGH);
    }
    s_mqtt.loop();
    return ok;
}

inline void mqttLoop()
{
    if (s_mqtt.connected()) s_mqtt.loop();
}

#else // !HYDROWIN_HAS_PUBSUBCLIENT

inline void mqttSetBroker(const char*, uint16_t) {}
inline void mqttSetAuth(const char*, const char*) {}
inline bool postTelemetryMqtt(const String&) { return false; }
inline void mqttLoop() {}

#endif

#endif
