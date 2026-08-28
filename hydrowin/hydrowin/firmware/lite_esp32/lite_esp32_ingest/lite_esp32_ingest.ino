/*
 * HydroWin — lite_esp32
 * ESP32 classic: датчики + BLE (Nordic UART), без Wi‑Fi / GSM.
 *
 * Семейство: lite (эта) | esp32_ingest (Wi‑Fi+BLE) | full_ta7670 (LTE+GPS).
 * Цель: стабильный Bluetooth. Облако не нужно — приложение Lite.
 */

#ifndef HYDROWIN_GPS_ENABLED
#define HYDROWIN_GPS_ENABLED 0
#endif

// Включённые каналы только из SENSOR_TABLE — без «залипших» ENABLE из NVS.
#ifndef HYDROWIN_FORCE_SENSOR_TABLE_ENABLED
#define HYDROWIN_FORCE_SENSOR_TABLE_ENABLED 1
#endif

#include <Arduino.h>
// Явно подтягиваем NimBLE, чтобы Arduino IDE добавила include-пути NimBLE в сборку.
// Иначе __has_include(<NimBLEDevice.h>) в ble_config.h может сработать как "BLE off".
#include <NimBLEDevice.h>

#include <config.h>
#include <runtime_config.h>
#include <sensors.h>

// BLE должен идти после блока с командами (processSetupLine + CFG/OK).
#include <block_setup.h>
#include <ble_config.h>

// Для диагностики CH0..CH5: только если включено HYDROWIN_SERIAL_DIAG=1 в config.h.
static uint32_t s_lastDiagMs = 0;

void setup()
{
    Serial.begin(115200);
    delay(300);

    loadRuntimeConfig();

    Serial.println();
    Serial.printf(" HydroWin %s (lite)\n", VERSION);
    Serial.printf(" Link: BLE-only\n");
    Serial.println();

    printSetupHelp();

    initSensors();

    // BLE — локально, без initLink().
    bleBegin();
}

void loop()
{
    handleBlockSetupSerial();
    updateSensors();
    bleLoop();

    const uint32_t now = millis();
#if HYDROWIN_SERIAL_DIAG
    if (now - s_lastDiagMs >= HYDROWIN_SERIAL_DIAG_MS) {
        s_lastDiagMs = now;
        printSensorsDiag();
    }
#endif
}

