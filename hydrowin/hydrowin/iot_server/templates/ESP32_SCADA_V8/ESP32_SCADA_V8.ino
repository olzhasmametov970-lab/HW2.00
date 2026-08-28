#include "sensors.h"
#include <WiFi.h>
#include <ESPAsyncWebServer.h>
#include <AsyncTCP.h>

#include "config.h"
#include "web.h"
#include "websocket.h"
#include "api.h"
AsyncWebServer server(HTTP_PORT);
AsyncWebSocket ws("/ws");
float temperature = 0.0f;
float pressure = 0.0f;      
void setup()
{
    Serial.begin(115200);

initSensors();

    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

    Serial.print("Connecting");

    while (WiFi.status() != WL_CONNECTED)
    {
        Serial.print(".");
        delay(500);
    }

    Serial.println();
    Serial.println("WiFi connected");
    Serial.print("IP: ");
    Serial.println(WiFi.localIP());

    initWeb(server);
    initWebSocket(server);
    initApi(server);

    server.begin();

    Serial.println("SCADA V8 started");
}
void loop()
{
    updateSensors();
    updateWebSocket();
}