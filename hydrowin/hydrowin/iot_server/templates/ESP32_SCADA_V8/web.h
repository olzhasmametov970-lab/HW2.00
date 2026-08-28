#ifndef WEB_H
#define WEB_H

#include <ESPAsyncWebServer.h>

const char INDEX_HTML[] PROGMEM = R"rawliteral(
<!DOCTYPE html>
<html lang="ru">

<head>

<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">

<title>ESP32 SCADA V8 Enterprise</title>

<style>

*{
    margin:0;
    padding:0;
    box-sizing:border-box;
    font-family:Arial,Helvetica,sans-serif;
}

body{
    background:#1b1f24;
    color:white;
}

header{
    background:#0d6efd;
    padding:18px;
    text-align:center;
    font-size:28px;
    font-weight:bold;
}

.container{
    max-width:1200px;
    margin:30px auto;
    display:flex;
    flex-wrap:wrap;
    justify-content:center;
    gap:20px;
}

.card{

    width:260px;

    background:#2b3138;

    border-radius:12px;

    padding:20px;

    box-shadow:0px 0px 15px rgba(0,0,0,.35);

    text-align:center;

}

.card h2{

    margin-bottom:20px;

}

.value{

    font-size:46px;

    color:#00e5ff;

}

.info{

    width:100%;

    margin-top:20px;

    background:#2b3138;

    border-radius:12px;

    padding:20px;

    text-align:center;

    line-height:2;

}

.online{

    color:#00ff55;

    font-weight:bold;

}

.offline{

    color:red;

    font-weight:bold;

}

</style>

</head>

<body>

<header>

ESP32 SCADA V8 Enterprise

</header>

<div class="container">

<div class="card">

<h2>🌡 Температура</h2>

<div id="temp" class="value">--.- °C</div>

</div>

<div class="card">

<h2>⚙ Давление</h2>

<div id="press" class="value">--.- bar</div>

</div>

<div class="info">

<div>
IP:
<b id="ip">-</b>
</div>

<div>
WiFi:
<b id="rssi">-</b> dBm
</div>

<div>
Uptime:
<b id="uptime">0</b> sec
</div>

<div>

Status:

<span id="status" class="offline">

Disconnected

</span>

</div>

</div>

</div>

<script>

let socket;

function connect()
{
    socket = new WebSocket("ws://" + location.host + "/ws");

    socket.onopen = function()
    {
        document.getElementById("status").innerHTML="Connected";
        document.getElementById("status").className="online";
    };

    socket.onclose = function()
    {
        document.getElementById("status").innerHTML="Disconnected";
        document.getElementById("status").className="offline";

        setTimeout(connect,2000);
    };

    socket.onmessage = function(event)
    {
        let d = JSON.parse(event.data);

        document.getElementById("temp").innerHTML =
            Number(d.temperature).toFixed(2) + " °C";

        document.getElementById("press").innerHTML =
            Number(d.pressure).toFixed(2) + " bar";

        document.getElementById("uptime").innerHTML =
            d.uptime;

        document.getElementById("ip").innerHTML =
            d.ip;

        document.getElementById("rssi").innerHTML =
            d.rssi;
    };
}

connect();

</script>

</body>

</html>
)rawliteral";

void initWeb(AsyncWebServer &server)
{
    server.on("/", HTTP_GET,
    [](AsyncWebServerRequest *request)
    {
        request->send_P(200, "text/html", INDEX_HTML);
    });
}

#endif