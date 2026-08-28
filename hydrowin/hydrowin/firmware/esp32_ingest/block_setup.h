#ifndef BLOCK_SETUP_H
#define BLOCK_SETUP_H

#include <Arduino.h>
#include <WiFi.h>
#include "calibration.h"
#include "sensors.h"
#include "runtime_config.h"
#include "offline_queue.h"
#include "hydrowin_ingest.h"

// USB Serial Monitor, 115200 бод.
//
// Датчики:
//   CAL <ch> <min> <max> [off]   — шкала + offset
//   ZERO <ch>                    — value=0 при текущем мА (давление в воздухе)
//   MATCH <ch> <value>           — value=эталон при текущем мА (температура)
//   ENABLE <ch> / DISABLE <ch> / RESET <ch> / SHOW
//
// Сеть (из приложения «Настройка блока и сети» → «Скопировать команды»):
//   WIFI ssid|password
//   GSM apn|user|pass
//   API host|port [|tls]         tls=1 → https на любом порту
//   LINK wifi | LINK gsm | LINK auto
//   CFG

/** Сырой NMEA в Serial Monitor (по умолчанию OFF — иначе топит --- sensors ---). */
inline bool& hydroGpsNmeaEcho()
{
    static bool echo = false;
    return echo;
}

inline void printSetupHelp()
{
    Serial.println();
    Serial.println("=== HydroWin block setup (USB) ===");
    Serial.println("CAL <ch> <min> <max> [off]  — шкала 4..20мА → ед.изм. (value целое)");
    Serial.println("ZERO <ch>                  — ноль при текущем токе (давл. в воздухе)");
    Serial.println("MATCH <ch> <value>         — подогнать к эталону (темп. по термометру)");
    Serial.println("ENABLE / DISABLE / RESET / SHOW");
    Serial.println("WIFI ssid|password                     — Wi-Fi");
    Serial.println("WIFI SCAN                              — список 2.4G сетей");
    Serial.println("WIFI TEST                              — сразу подключиться");
    Serial.println("GSM apn|user|pass                      — APN SIM (A7670)");
    Serial.println("API host|port [|tls]                   — 443 или tls=1 → HTTPS");
    Serial.println("LINK wifi | LINK gsm | LINK auto       — Wi-Fi / A7670 / AUTO");
    Serial.println("MACHINE <uuid>                         — UUID машины (обязательно)");
    Serial.println("DEVICE <id>                            — метка платы");
    Serial.println("KEY <device_key>                       — X-Device-Key");
    Serial.println("CFG                                    — показать сеть");
    Serial.println("QUEUE / QUEUE CLEAR                    — офлайн-очередь flash");
    Serial.println("GSMAT AT+CPIN?                         — AT прямо в A7670");
    Serial.println("GSMRETRY                               — снова init A7670");
    Serial.println("GPSRESET                               — холодный сброс L76K (UART2)");
    Serial.println("GPSTX $PMTK…                           — сырая команда в L76K");
    Serial.println("GPSNMEA ON|OFF                         — сырой NMEA в монитор");
    Serial.println("HELP");
    Serial.println();
    Serial.println("BLE: AUTH <PIN> (хвост MAC) перед KEY/WIFI/MACHINE");
    Serial.println();
}

inline bool _splitPipe(const String& s, String* parts, int maxParts, int* outCount)
{
    int count = 0;
    int start = 0;
    for (int i = 0; i <= (int)s.length() && count < maxParts; i++) {
        if (i == (int)s.length() || s[i] == '|') {
            parts[count++] = s.substring(start, i);
            start = i + 1;
        }
    }
    *outCount = count;
    return count > 0;
}

/** Вставка пачки без перевода строк: "DEVICE x MACHINE uuid KEY k …" */
inline int _indexOfNextSetupCmd(const String& s)
{
    static const char* k[] = {
        " MACHINE ", " DEVICE ", " KEY ", " GSM ", " WIFI ", " API ",
        " LINK ", " GSMAT ", " CAL ", " ZERO ", " MATCH ", " ENABLE ",
        " DISABLE ", " RESET ", " CFG", " HELP", " SHOW", " QUEUE",
        " GSMRETRY", " GPSRESET", " GPSTX ", " GPSNMEA ",
    };
    int best = -1;
    const int n = (int)(sizeof(k) / sizeof(k[0]));
    for (int i = 0; i < n; i++) {
        const int p = s.indexOf(k[i]);
        if (p > 0 && (best < 0 || p < best)) best = p;
    }
    return best;
}

inline void processSetupLine(String line)
{
    line.trim();
    // Убрать CR, если монитор шлёт CRLF одной строкой
    if (line.endsWith("\r")) line.remove(line.length() - 1);
    line.replace('\t', ' ');
    line.trim();
    if (line.length() == 0) return;

    const int nxt = _indexOfNextSetupCmd(line);
    if (nxt > 0) {
        String rest = line.substring(nxt);
        line.remove(nxt);
        processSetupLine(line);
        processSetupLine(rest);
        return;
    }

    if (line.equalsIgnoreCase("HELP")) {
        printSetupHelp();
        return;
    }

    if (line.equalsIgnoreCase("SHOW")) {
        printSensorsDiag();
        return;
    }

    if (line.equalsIgnoreCase("CFG")) {
        printRuntimeConfig();
        printOfflineQueueStatus();
        return;
    }

    if (line.equalsIgnoreCase("QUEUE") || line.equalsIgnoreCase("QUEUE STATUS")) {
        printOfflineQueueStatus();
        return;
    }
    if (line.equalsIgnoreCase("QUEUE CLEAR")) {
        clearOfflineQueue();
        return;
    }

    // Монитор порта (USB Serial) ≠ UART2 L76K — команды GPS шлём явно в Serial2.
    if (line.equalsIgnoreCase("GPSRESET")) {
        Serial2.print("$PMTK104*37\r\n");
        Serial.println(
            "OK GPSRESET → L76K ($PMTK104*37). Ответа от модуля обычно нет — "
            "смотрите, что NMEA продолжается; фикс 1–15 мин на открытом небе.");
        return;
    }
    if (line.startsWith("GPSTX ") || line.startsWith("gpstx ")) {
        String cmd = line.substring(6);
        cmd.trim();
        if (cmd.length() == 0) {
            Serial.println("ERR usage: GPSTX $PMTK104*37");
            return;
        }
        Serial2.print(cmd);
        if (!cmd.endsWith("\r") && !cmd.endsWith("\n")) Serial2.print("\r\n");
        Serial.println("OK GPSTX → L76K UART2");
        return;
    }
    if (line.equalsIgnoreCase("GPSNMEA") || line.equalsIgnoreCase("GPSNMEA ON") ||
        line.equalsIgnoreCase("GPSNMEA 1")) {
        hydroGpsNmeaEcho() = true;
        Serial.println("OK GPSNMEA ON — сырые $GNxxx в мониторе");
        return;
    }
    if (line.equalsIgnoreCase("GPSNMEA OFF") || line.equalsIgnoreCase("GPSNMEA 0")) {
        hydroGpsNmeaEcho() = false;
        Serial.println("OK GPSNMEA OFF");
        return;
    }

    // Проброс AT → A7670
    if (line.startsWith("GSMAT ") || line.startsWith("gsmat ")) {
        String cmd = line.substring(6);
        cmd.trim();
        if (cmd.length() == 0) {
            Serial.println("ERR usage: GSMAT AT+CPIN?");
            return;
        }
        String resp = hydroGsmModem().exchangeAt(cmd.c_str(), 8000);
        if (resp.length() == 0) Serial.println("ERR: A7670 not responding");
        return;
    }
    if (line.startsWith("AT") || line.startsWith("at")) {
        String cmd = line;
        const int sp = cmd.indexOf(' ');
        if (sp > 2) cmd = cmd.substring(0, sp);
        String resp = hydroGsmModem().exchangeAt(cmd.c_str(), 8000);
        if (resp.length() == 0) Serial.println("ERR: A7670 not responding");
        return;
    }

    if (line.equalsIgnoreCase("GSMRETRY")) {
        hydroGsmModem().clearLockout();
        Serial.println("OK GSMRETRY — init A7670 сейчас");
        if (hydroGsmModem().begin()) Serial.println("A7670: OK");
        else Serial.println("A7670: всё ещё нет AT");
        return;
    }

    if (line.equalsIgnoreCase("WIFI SCAN") || line.equalsIgnoreCase("SCAN")) {
        Serial.println("Wi-Fi scan 2.4 GHz...");
        WiFi.mode(WIFI_STA);
        WiFi.disconnect(true, true);
        delay(200);
        const int n = WiFi.scanNetworks(/*async=*/false, /*hidden=*/true);
        if (n <= 0) {
            Serial.println("SCAN: сетей не видно (антенна / только 5 GHz роутер?)");
        } else {
            for (int i = 0; i < n; i++) {
                Serial.printf("  %2d) '%s'  RSSI=%d  ch=%d  %s\n",
                              i + 1,
                              WiFi.SSID(i).c_str(),
                              WiFi.RSSI(i),
                              WiFi.channel(i),
                              (WiFi.encryptionType(i) == WIFI_AUTH_OPEN) ? "open"
                                                                         : "enc");
            }
        }
        WiFi.scanDelete();
        if (rtConfig().wifiSsid[0] != '\0') {
            WiFi.mode(WIFI_STA);
            WiFi.setAutoReconnect(true);
            WiFi.begin(rtConfig().wifiSsid, rtConfig().wifiPass);
            Serial.println("SCAN done — WiFi.begin(saved SSID)");
        }
        return;
    }

    if (line.equalsIgnoreCase("WIFI TEST") || line.equalsIgnoreCase("WIFITEST")) {
        Serial.println("WIFI TEST...");
        (void)ensureWifi();
        return;
    }

    if (line.startsWith("WIFI ")) {
        String rest = line.substring(5);
        rest.trim();
        String parts[2];
        int n = 0;
        if (!_splitPipe(rest, parts, 2, &n) || n < 1) {
            Serial.println("ERR usage: WIFI ssid|password");
            return;
        }
        if (!saveWifiConfig(parts[0].c_str(), n > 1 ? parts[1].c_str() : "")) {
            Serial.println("ERR empty SSID");
            return;
        }
        WiFi.setAutoReconnect(true);
        WiFi.mode(WIFI_STA);
        WiFi.disconnect(false);
        delay(100);
        Serial.printf("OK WIFI ssid=%s pass_len=%u — пробую сейчас...\n",
                      parts[0].c_str(),
                      (unsigned)(n > 1 ? parts[1].length() : 0));
        (void)ensureWifi();
        return;
    }

    if (line.startsWith("GSM ")) {
        String rest = line.substring(4);
        rest.trim();
        String parts[3];
        int n = 0;
        if (!_splitPipe(rest, parts, 3, &n) || n < 1) {
            Serial.println("ERR usage: GSM apn|user|pass");
            return;
        }
        if (!saveGsmConfig(
                parts[0].c_str(),
                n > 1 ? parts[1].c_str() : "",
                n > 2 ? parts[2].c_str() : "")) {
            Serial.println("ERR empty APN");
            return;
        }
        Serial.printf("OK GSM apn=%s\n", parts[0].c_str());
        return;
    }

    if (line.startsWith("API ")) {
        String rest = line.substring(4);
        rest.trim();
        String parts[3];
        int n = 0;
        if (!_splitPipe(rest, parts, 3, &n) || n < 1) {
            Serial.println("ERR usage: API host|port [|tls]");
            return;
        }
        const uint16_t port = n > 1 ? (uint16_t)parts[1].toInt() : 443;
        const bool tls =
            (n > 2 && (parts[2] == "1" || parts[2].equalsIgnoreCase("tls"))) ||
            port == 443;
        if (!saveApiConfig(parts[0].c_str(), port == 0 ? 443 : port, tls)) {
            Serial.println("ERR bad host/port");
            return;
        }
        Serial.printf("OK API %s\n", rtApiBase().c_str());
        return;
    }

    if (line.equalsIgnoreCase("LINK wifi") || line.equalsIgnoreCase("LINK WIFI")) {
        saveLinkMode(LINK_WIFI);
        Serial.println("OK LINK wifi (reboot recommended)");
        return;
    }
    if (line.equalsIgnoreCase("LINK gsm") || line.equalsIgnoreCase("LINK GSM")) {
        saveLinkMode(LINK_GSM);
        Serial.println("OK LINK gsm (reboot recommended)");
        return;
    }
    if (line.equalsIgnoreCase("LINK auto") || line.equalsIgnoreCase("LINK AUTO")) {
        saveLinkMode(LINK_AUTO);
        Serial.println("OK LINK auto (reboot recommended)");
        return;
    }

    if (line.startsWith("MACHINE ")) {
        String id = line.substring(8);
        id.trim();
        if (!saveMachineId(id.c_str())) {
            Serial.println("ERR usage: MACHINE <uuid>");
            return;
        }
        Serial.printf("OK MACHINE %s\n", rtConfig().machineId);
        return;
    }

    if (line.startsWith("DEVICE ")) {
        String id = line.substring(7);
        id.trim();
        if (!saveDeviceId(id.c_str())) {
            Serial.println("ERR usage: DEVICE <id>");
            return;
        }
        Serial.printf("OK DEVICE %s\n", rtConfig().deviceId);
        return;
    }

    if (line.startsWith("KEY ")) {
        String key = line.substring(4);
        key.trim();
        if (!saveDeviceKey(key.c_str())) {
            Serial.println("ERR usage: KEY <device_key>");
            return;
        }
        Serial.println("OK KEY saved");
        return;
    }

    if (line.startsWith("CAL ")) {
        int ch = -1;
        float minV = 0;
        float maxV = 0;
        float off = 0;
        const int parsed = sscanf(
            line.c_str(), "CAL %d %f %f %f", &ch, &minV, &maxV, &off);
        if (parsed < 3 || ch < 0) {
            Serial.println("ERR usage: CAL <ch> <min> <max> [offset]");
            return;
        }
        SensorRuntime* s = findSensorByChannel((uint8_t)ch);
        const bool enabled = s != nullptr ? s->cal.enabled : true;
        if (!calStore().save((uint8_t)ch, minV, maxV, off, enabled)) {
            Serial.println("ERR min must be < max");
            return;
        }
        reloadSensorCalibration((uint8_t)ch);
        Serial.printf("OK CAL ch=%d %.2f..%.2f off=%.2f\n", ch, minV, maxV, off);
        return;
    }

    // Обнулить инженерное value при текущем токе петли (манометр в воздухе → 0 бар).
    if (line.startsWith("ZERO ")) {
        int ch = -1;
        if (sscanf(line.c_str(), "ZERO %d", &ch) != 1 || ch < 0) {
            Serial.println("ERR usage: ZERO <ch>");
            return;
        }
        SensorRuntime* s = findSensorByChannel((uint8_t)ch);
        if (s == nullptr || !s->cal.enabled) {
            Serial.println("ERR channel not enabled");
            return;
        }
        if (s->reading.fault != LOOP_OK || !s->reading.valid) {
            Serial.printf(
                "ERR loop fault=%s — ZERO только при OK (4..20 мА)\n",
                loopFaultLabel(s->reading.fault));
            return;
        }

        const float ma = constrain(s->reading.currentMa, 4.0f, 20.0f);
        const float ratio = (ma - 4.0f) / 16.0f;
        const float rawEng =
            s->cal.scaleMin + ratio * (s->cal.scaleMax - s->cal.scaleMin);
        const float newOff = -rawEng; // value = rawEng + offset → 0
        const float was = (float)s->reading.value;

        if (!calStore().save(
                (uint8_t)ch,
                s->cal.scaleMin,
                s->cal.scaleMax,
                newOff,
                s->cal.enabled)) {
            Serial.println("ERR save failed");
            return;
        }
        reloadSensorCalibration((uint8_t)ch);
        Serial.printf(
            "OK ZERO ch=%d off=%+.2f (was %ld @ %.2fmA)\n",
            ch,
            newOff,
            (long)lroundf(was),
            s->reading.currentMa);
        return;
    }

    // Подогнать value к эталону при текущем токе (например температура по термометру).
    if (line.startsWith("MATCH ")) {
        int ch = -1;
        float target = 0;
        if (sscanf(line.c_str(), "MATCH %d %f", &ch, &target) != 2 || ch < 0) {
            Serial.println("ERR usage: MATCH <ch> <value>");
            return;
        }
        SensorRuntime* s = findSensorByChannel((uint8_t)ch);
        if (s == nullptr || !s->cal.enabled) {
            Serial.println("ERR channel not enabled");
            return;
        }
        if (s->reading.fault != LOOP_OK || !s->reading.valid) {
            Serial.printf(
                "ERR loop fault=%s — MATCH только при OK (4..20 мА)\n",
                loopFaultLabel(s->reading.fault));
            return;
        }

        const float ma = constrain(s->reading.currentMa, 4.0f, 20.0f);
        const float ratio = (ma - 4.0f) / 16.0f;
        const float rawEng =
            s->cal.scaleMin + ratio * (s->cal.scaleMax - s->cal.scaleMin);
        const float newOff = target - rawEng;
        const float was = (float)s->reading.value;

        if (!calStore().save(
                (uint8_t)ch,
                s->cal.scaleMin,
                s->cal.scaleMax,
                newOff,
                s->cal.enabled)) {
            Serial.println("ERR save failed");
            return;
        }
        reloadSensorCalibration((uint8_t)ch);
        Serial.printf(
            "OK MATCH ch=%d -> %.0f off=%+.2f (was %ld @ %.2fmA)\n",
            ch,
            target,
            newOff,
            (long)lroundf(was),
            s->reading.currentMa);
        return;
    }

    if (line.startsWith("ENABLE ")) {
        int ch = -1;
        if (sscanf(line.c_str(), "ENABLE %d", &ch) != 1 || ch < 0) {
            Serial.println("ERR usage: ENABLE <ch>");
            return;
        }
        if (!setSensorEnabled((uint8_t)ch, true)) {
            Serial.println("ERR channel not in SENSOR_TABLE");
            return;
        }
        Serial.printf("OK ENABLE ch=%d\n", ch);
        return;
    }

    if (line.startsWith("DISABLE ")) {
        int ch = -1;
        if (sscanf(line.c_str(), "DISABLE %d", &ch) != 1 || ch < 0) {
            Serial.println("ERR usage: DISABLE <ch>");
            return;
        }
        if (!setSensorEnabled((uint8_t)ch, false)) {
            Serial.println("ERR channel not in SENSOR_TABLE");
            return;
        }
        Serial.printf("OK DISABLE ch=%d\n", ch);
        return;
    }

    if (line.startsWith("RESET ")) {
        int ch = -1;
        if (sscanf(line.c_str(), "RESET %d", &ch) != 1 || ch < 0) {
            Serial.println("ERR usage: RESET <ch>");
            return;
        }
        for (uint8_t i = 0; i < sensorCount(); i++) {
            const SensorRuntime* s = sensorAt(i);
            if (s == nullptr || s->def.channel != (uint8_t)ch) continue;
            if (!calStore().resetChannel(
                    (uint8_t)ch,
                    s->def.scaleMin,
                    s->def.scaleMax,
                    s->def.enabled)) {
                Serial.println("ERR RESET save failed (check SENSOR_TABLE min<max)");
                return;
            }
            reloadSensorCalibration((uint8_t)ch);
            Serial.printf("OK RESET ch=%d\n", ch);
            return;
        }
        Serial.println("ERR channel not in SENSOR_TABLE");
        return;
    }

    Serial.printf("ERR unknown: %s (type HELP)\n", line.c_str());
}

inline void handleBlockSetupSerial()
{
    Serial.setTimeout(80);
    int guard = 0;
    while (Serial.available() && guard++ < 24) {
        String line = Serial.readStringUntil('\n');
        processSetupLine(line);
    }
}

#endif
