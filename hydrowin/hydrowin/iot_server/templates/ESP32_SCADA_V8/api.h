#ifndef API_H
#define API_H

#include <ArduinoJson.h>

extern float temperature;
extern float pressure;

extern AsyncWebSocket ws;

void initApi(AsyncWebServer &server)
{
    server.on("/api/data", HTTP_GET, [](AsyncWebServerRequest *request)
    {
        StaticJsonDocument<256> doc;

        doc["temperature"] = temperature;
        doc["pressure"] = pressure;
        doc["uptime"] = millis() / 1000;
        doc["ip"] = WiFi.localIP().toString();
        doc["rssi"] = WiFi.RSSI();

        String json;
        serializeJson(doc, json);

        request->send(200, "application/json", json);
    });

    server.on("/api/info", HTTP_GET, [](AsyncWebServerRequest *request)
    {
        StaticJsonDocument<256> doc;

        doc["project"] = "ESP32 SCADA";
        doc["version"] = VERSION;
        doc["chip"] = ESP.getChipModel();
        doc["cores"] = ESP.getChipCores();
        doc["flash"] = ESP.getFlashChipSize();

        String json;
        serializeJson(doc, json);

        request->send(200, "application/json", json);
    });
}

#endif