/*
 * HydroWin ESP32 — BLE (NimBLE Nordic UART)
 *
 * Advertise: HydroWinN (короткое имя)
 * GATT: Nordic UART UUIDs (см. config.h / mobile ble_uuids.dart)
 * RX (write): ASCII-команды как USB Serial (WIFI / API / LINK / CFG / …)
 * TX (notify): текстовые ack + бинарный пакет 21 байт (BLE v2, CH0–CH5)
 *
 * Библиотека: NimBLE-Arduino (Library Manager).
 * Без библиотеки — заглушки, сборка как раньше (Wi‑Fi/GSM/MQTT).
 */

#ifndef BLE_CONFIG_H
#define BLE_CONFIG_H

#include <Arduino.h>
#include <math.h>
#include <string.h>
#include <esp_mac.h>
#include "config.h"
#include "sensors.h"
#include "runtime_config.h"

#if __has_include(<NimBLEDevice.h>)
#include <NimBLEDevice.h>
#define HYDROWIN_HAS_NIMBLE 1
#else
#define HYDROWIN_HAS_NIMBLE 0
#warning "NimBLE-Arduino not installed — BLE disabled. Install: Library Manager → NimBLE-Arduino"
#endif

#ifndef BLE_TELEMETRY_MS
#define BLE_TELEMETRY_MS 1000
#endif

#ifndef BLE_SERVICE_UUID
#define BLE_SERVICE_UUID "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#endif
#ifndef BLE_RX_UUID
#define BLE_RX_UUID "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#endif
#ifndef BLE_TX_UUID
#define BLE_TX_UUID "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
#endif

/** BLE v2: CH0–CH5 (макс. ADC1), 21 байт. */
#ifndef BLE_TELEMETRY_CHANNELS
#define BLE_TELEMETRY_CHANNELS 6
#endif
#ifndef BLE_TELEMETRY_PACKET_LEN
#define BLE_TELEMETRY_PACKET_LEN 21
#endif
#ifndef BLE_TELEMETRY_PROTO
#define BLE_TELEMETRY_PROTO 0x02
#endif

// Нужен processSetupLine() из block_setup.h — подключайте block_setup.h до ble_config.h.

inline uint8_t bleCrc8Maxim(const uint8_t* data, size_t len)
{
    uint8_t crc = 0;
    for (size_t i = 0; i < len; i++) {
        crc ^= data[i];
        for (int b = 0; b < 8; b++) {
            if (crc & 1) {
                crc = (uint8_t)((crc >> 1) ^ 0x8C);
            } else {
                crc >>= 1;
            }
        }
    }
    return crc;
}

/**
 * Собрать 21-байтный пакет v2 (proto=0x02, ch0..ch5 ×0.1, CRC-8/MAXIM).
 *
 * | Off | Size | Field |
 * | 0   | 1    | proto = 0x02 |
 * | 1   | 1    | flags |
 * | 2   | 4    | timestamp uint32 LE (uptime sec) |
 * | 6   | 12   | ch0..ch5 int16 LE ×10 |
 * | 18  | 2    | status: 2 бита × 6 каналов |
 * | 20  | 1    | CRC-8/MAXIM по байтам 0..19 |
 *
 * status: 0=ok, 1=warning, 2=short (КЗ), 3=open (обрыв)
 */
inline void bleBuildTelemetryPacket(uint8_t out[BLE_TELEMETRY_PACKET_LEN])
{
    memset(out, 0, BLE_TELEMETRY_PACKET_LEN);
    out[0] = BLE_TELEMETRY_PROTO;

    const uint32_t ts = (uint32_t)(millis() / 1000UL);
    out[2] = (uint8_t)(ts & 0xFF);
    out[3] = (uint8_t)((ts >> 8) & 0xFF);
    out[4] = (uint8_t)((ts >> 16) & 0xFF);
    out[5] = (uint8_t)((ts >> 24) & 0xFF);

    uint16_t status = 0;
    for (uint8_t i = 0; i < BLE_TELEMETRY_CHANNELS; i++) {
        const SensorRuntime* s = findSensorByChannel(i);
        float value = 0.0f;
        uint8_t level = 0;
        if (s != nullptr && s->cal.enabled) {
            if (s->reading.fault == LOOP_OPEN) {
                level = 3;
                value = s->reading.currentMa;
            } else if (s->reading.fault == LOOP_SHORT) {
                level = 2;
                value = s->reading.currentMa;
            } else if (s->reading.valid) {
                value = (float)s->reading.value;
            }
        }
        // int16 ×10 → ±3276.7; иначе wrap и мусор в приложении.
        value = constrain(value, -3276.7f, 3276.7f);
        const int16_t raw = (int16_t)lroundf(value * 10.0f);
        const uint16_t u = (uint16_t)raw;
        const uint8_t off = (uint8_t)(6 + i * 2);
        out[off] = (uint8_t)(u & 0xFF);
        out[off + 1] = (uint8_t)((u >> 8) & 0xFF);
        status |= (uint16_t)((level & 0x3) << (i * 2));
    }
    out[18] = (uint8_t)(status & 0xFF);
    out[19] = (uint8_t)((status >> 8) & 0xFF);
    out[20] = bleCrc8Maxim(out, 20);
}

#if HYDROWIN_HAS_NIMBLE

static NimBLEServer* s_bleServer = nullptr;
static NimBLECharacteristic* s_bleTx = nullptr;
static NimBLECharacteristic* s_bleRx = nullptr;
static bool s_bleConnected = false;
static bool s_bleReady = false;
static uint32_t s_bleLastTelemetryMs = 0;
/** Сессия BLE: после AUTH <pin> можно менять KEY/WIFI/… */
static bool s_bleAuthed = false;
static char s_blePin[8] = "";

inline bool bleSetupLineAllowed(const String& line)
{
    String cmd = line;
    cmd.trim();
    int sp = cmd.indexOf(' ');
    String head = sp > 0 ? cmd.substring(0, sp) : cmd;
    head.toUpperCase();
    if (head == "AUTH" || head == "CFG" || head == "HELP" || head == "SHOW") {
        return true;
    }
    return s_bleAuthed;
}

inline void bleNotifyRaw(const uint8_t* data, size_t len)
{
    if (!s_bleReady || !s_bleConnected || s_bleTx == nullptr || data == nullptr || len == 0) {
        return;
    }
    s_bleTx->setValue(data, len);
    s_bleTx->notify();
}

inline void bleNotifyText(const char* text)
{
    if (text == nullptr) return;
    bleNotifyRaw(reinterpret_cast<const uint8_t*>(text), strlen(text));
}

inline void bleNotifyCfgSummary()
{
    char buf[192];
    snprintf(buf,
             sizeof(buf),
             "CFG LINK=%s WIFI=%s API=%s DEVICE=%s\n",
             linkModeName(rtConfig().linkMode),
             rtConfig().wifiSsid,
             rtApiBase().c_str(),
             rtConfig().deviceId);
    bleNotifyText(buf);
}

class HydroBleServerCallbacks : public NimBLEServerCallbacks {
    void onConnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo) override
    {
        (void)pServer;
        (void)connInfo;
        s_bleConnected = true;
        s_bleAuthed = false;
        Serial.println("BLE: connected (AUTH <pin> for config writes)");
    }

    void onDisconnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo, int reason) override
    {
        (void)pServer;
        (void)connInfo;
        (void)reason;
        s_bleConnected = false;
        s_bleAuthed = false;
        Serial.println("BLE: disconnected — advertising");
        NimBLEDevice::startAdvertising();
    }
};

class HydroBleRxCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* pCharacteristic, NimBLEConnInfo& connInfo) override
    {
        (void)connInfo;
        std::string value = pCharacteristic->getValue();
        if (value.empty()) return;

        String line;
        line.reserve((unsigned)value.size());
        for (size_t i = 0; i < value.size(); i++) {
            const char c = value[i];
            if (c == '\0') break;
            if (c == '\r' || c == '\n') {
                if (line.length() > 0) {
                    String trimmed = line;
                    trimmed.trim();
                    if (trimmed.startsWith("AUTH ") || trimmed.startsWith("auth ")) {
                        String pin = trimmed.substring(5);
                        pin.trim();
                        if (pin == String(s_blePin)) {
                            s_bleAuthed = true;
                            bleNotifyText("OK AUTH\n");
                            Serial.println("BLE: AUTH ok");
                        } else {
                            bleNotifyText("ERR AUTH\n");
                        }
                    } else if (!bleSetupLineAllowed(trimmed)) {
                        bleNotifyText("ERR AUTH required\n");
                    } else {
                        processSetupLine(line);
                        if (line.equalsIgnoreCase("CFG")) {
                            bleNotifyCfgSummary();
                        } else {
                            bleNotifyText("OK\n");
                        }
                    }
                    line = "";
                }
                continue;
            }
            line += c;
        }
        if (line.length() > 0) {
            String trimmed = line;
            trimmed.trim();
            if (trimmed.startsWith("AUTH ") || trimmed.startsWith("auth ")) {
                String pin = trimmed.substring(5);
                pin.trim();
                if (pin == String(s_blePin)) {
                    s_bleAuthed = true;
                    bleNotifyText("OK AUTH\n");
                } else {
                    bleNotifyText("ERR AUTH\n");
                }
            } else if (!bleSetupLineAllowed(trimmed)) {
                bleNotifyText("ERR AUTH required\n");
            } else {
                processSetupLine(line);
                if (line.equalsIgnoreCase("CFG")) {
                    bleNotifyCfgSummary();
                } else {
                    bleNotifyText("OK\n");
                }
            }
        }
    }
};

static HydroBleServerCallbacks s_bleServerCb;
static HydroBleRxCallbacks s_bleRxCb;

inline void bleBegin()
{
    // Уникальное имя в эфире: HydroWin-9D42 (хвост BT MAC) —
    // две платы с DEVICE HW-1 больше не выглядят одинаково.
    char name[24];
    uint8_t mac[6] = {0};
    esp_read_mac(mac, ESP_MAC_BT);
    snprintf(name, sizeof(name), "HydroWin-%02X%02X", mac[4], mac[5]);
    // PIN для BLE-конфига = хвост MAC (4 hex), печатается в Serial.
    snprintf(s_blePin, sizeof(s_blePin), "%02X%02X", mac[4], mac[5]);
    s_bleAuthed = false;

    NimBLEDevice::init(name);
    NimBLEDevice::setPower(ESP_PWR_LVL_P9);

    s_bleServer = NimBLEDevice::createServer();
    s_bleServer->setCallbacks(&s_bleServerCb);

    NimBLEService* svc = s_bleServer->createService(BLE_SERVICE_UUID);

    s_bleTx = svc->createCharacteristic(
        BLE_TX_UUID,
        NIMBLE_PROPERTY::NOTIFY);

    s_bleRx = svc->createCharacteristic(
        BLE_RX_UUID,
        NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
    s_bleRx->setCallbacks(&s_bleRxCb);

    svc->start();

    NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
    adv->addServiceUUID(BLE_SERVICE_UUID);
    adv->setName(name);
    adv->start();

    s_bleReady = true;
    s_bleLastTelemetryMs = 0;
    Serial.printf(
        "BLE: MAC %02X:%02X:%02X:%02X:%02X:%02X → advertising as %s (CH0–CH5 packet v2)\n",
        mac[0],
        mac[1],
        mac[2],
        mac[3],
        mac[4],
        mac[5],
        name);
    Serial.printf("BLE: setup PIN (AUTH) = %s\n", s_blePin);
}

inline void bleLoop()
{
    if (!s_bleReady || !s_bleConnected) return;

    const uint32_t now = millis();
    if (now - s_bleLastTelemetryMs < (uint32_t)BLE_TELEMETRY_MS) return;
    s_bleLastTelemetryMs = now;

    uint8_t pkt[BLE_TELEMETRY_PACKET_LEN];
    bleBuildTelemetryPacket(pkt);
    bleNotifyRaw(pkt, sizeof(pkt));
}

#else // !HYDROWIN_HAS_NIMBLE

inline void bleBegin()
{
    Serial.println("BLE: off (install NimBLE-Arduino to enable)");
}

inline void bleLoop() {}

#endif // HYDROWIN_HAS_NIMBLE

#endif // BLE_CONFIG_H
