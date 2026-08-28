/*
 * HydroWin ESP32 — датчики из SCADA V8 (iot_server) + HTTP POST в облако
 *
 * Структура как у коллеги:
 *   config.h           — Wi‑Fi, API, MACHINE_ID
 *   sensors.h          — 4–20 мА → °C / бар (пины 34/35)
 *   hydrowin_ingest.h  — POST /v1/ingest/telemetry
 *
 * Arduino IDE: Board → ESP32 Dev Module
 * Библиотеки: только ESP32 core (WiFi, HTTPClient) — без AsyncWebServer
 *
 * Перед прошивкой заполни config.h (Wi‑Fi + MACHINE_ID).
 */

#include <WiFi.h>

#include "config.h"
#include "sensors.h"
#include "hydrowin_ingest.h"

uint32_t lastSendMs = 0;
uint32_t lastDiagMs = 0;

void setup()
{
    Serial.begin(115200);
    delay(300);
    Serial.println();
    Serial.printf("HydroWin ESP32 %s\n", VERSION);

    initSensors();

    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    Serial.printf("Connecting to %s", WIFI_SSID);
    while (WiFi.status() != WL_CONNECTED) {
        Serial.print(".");
        delay(500);
    }
    Serial.println();
    Serial.print("WiFi OK IP=");
    Serial.println(WiFi.localIP());

    initNtp();
    Serial.println("Ready — sensors + HydroWin ingest");
}

void loop()
{
    updateSensors();

    // Диагностика в Serial как у коллеги (~2 Гц)
    if (millis() - lastDiagMs >= 500) {
        lastDiagMs = millis();
        printSensorsDiag();
    }

    if (millis() - lastSendMs >= SEND_INTERVAL_MS) {
        lastSendMs = millis();
        if (!postTelemetry()) {
            Serial.println("ingest failed — retry next cycle");
        }
    }
}
