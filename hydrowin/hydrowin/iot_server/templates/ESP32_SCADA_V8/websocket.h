#ifndef WEBSOCKET_H
#define WEBSOCKET_H

#include <ESPAsyncWebServer.h>
#include <ArduinoJson.h>
#include <WiFi.h>

extern AsyncWebSocket ws;

extern float temperature;
extern float pressure;

//------------------------------------------------------------

void notifyClients()
{
    StaticJsonDocument<256> doc;

    doc["temperature"] = temperature;
    doc["pressure"] = pressure;

    doc["uptime"] = millis() / 1000;

    doc["ip"] = WiFi.localIP().toString();

    doc["rssi"] = WiFi.RSSI();

    String json;
    serializeJson(doc, json);

    ws.textAll(json);
}

//------------------------------------------------------------

void onWsEvent(
    AsyncWebSocket *server,
    AsyncWebSocketClient *client,
    AwsEventType type,
    void *arg,
    uint8_t *data,
    size_t len)
{
    switch (type)
    {
        case WS_EVT_CONNECT:

            Serial.printf(
                "WebSocket Client #%u connected\n",
                client->id());

            break;

        case WS_EVT_DISCONNECT:

            Serial.printf(
                "WebSocket Client #%u disconnected\n",
                client->id());

            break;

        default:
            break;
    }
}

//------------------------------------------------------------

void initWebSocket(AsyncWebServer &server)
{
    ws.onEvent(onWsEvent);

    server.addHandler(&ws);
}

//------------------------------------------------------------

void updateWebSocket()
{
    static uint32_t last = 0;

    if (millis() - last >= 500)
    {
        last = millis();

        notifyClients();
    }

    ws.cleanupClients();
}

#endif