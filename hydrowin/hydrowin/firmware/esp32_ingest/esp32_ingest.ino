/*
 * HydroWin — ESP32 classic: Wi‑Fi HTTPS + BLE (полное приложение).
 * Без GSM/A7670. Для LTE+GPS → firmware/full_ta7670/.
 * Для только BLE → firmware/lite_esp32/.
 *
 * Опрос 1 с → буфер → HTTPS пачкой (TELEMETRY_BATCH_WIFI_MS).
 */

// Жёстко Wi‑Fi only (LINK_WIFI=0). GSM/AUTO — только на T‑A7670.
#ifndef LINK_MODE
#define LINK_MODE 0
#endif

#include <WiFi.h>
#include <NimBLEDevice.h>

#include "config.h"
#include "runtime_config.h"
#include "sensors.h"
#include "offline_queue.h"
#include "hydrowin_ingest.h"
#include "block_setup.h"
#include "ble_config.h"

uint32_t lastSampleMs = 0;
uint32_t lastFlushMs = 0;
uint32_t lastDiagMs = 0;

void setup()
{
    Serial.begin(115200);
    delay(300);

    pinMode(LED_PIN, OUTPUT);
    digitalWrite(LED_PIN, LOW);

    loadRuntimeConfig();
    // На этой плате GSM нет — даже если в NVS остался auto/gsm.
    if (rtConfig().linkMode != LINK_WIFI) {
        saveLinkMode(LINK_WIFI);
    }
    initOfflineQueue();

    Serial.println("\n==========================================");
    Serial.printf(" HydroWin ESP32 %s (Wi‑Fi + BLE)\n", VERSION);
    Serial.printf(" Link: %s (GSM отключён на этой сборке)\n",
                  linkModeName(rtConfig().linkMode));
    Serial.printf(" Sample %lu ms → batch HTTPS Wi‑Fi %lu\n",
                  (unsigned long)TELEMETRY_SAMPLE_MS,
                  (unsigned long)TELEMETRY_BATCH_WIFI_MS);
    Serial.println(" Values: integer (bar / °C)");
    Serial.println("==========================================");

    printSetupHelp();

    initSensors();
    initLink();
    bleBegin();

    if (offlineQueueCount() > 0) {
        Serial.printf("offline: при старте в очереди %u\n",
                      (unsigned)offlineQueueCount());
        flushOfflineQueue([](const String& queued) {
            const String fixed = rewriteQueuedTelemetryIds(
                queued, rtConfig().machineId, rtConfig().deviceId);
            return deliverTelemetry(fixed);
        });
    }

    Serial.println("\nСистема готова.\n");
}

void loop()
{
    handleBlockSetupSerial();
    updateSensors();
    bleLoop();

    const uint32_t now = millis();

#if HYDROWIN_SERIAL_DIAG
    if (now - lastDiagMs >= HYDROWIN_SERIAL_DIAG_MS) {
        lastDiagMs = now;
        printSensorsDiag();
    }
#endif

    if (now - lastSampleMs >= TELEMETRY_SAMPLE_MS) {
        lastSampleMs = now;
        sampleTelemetry();
    }

    const uint32_t batchMs = telemetryBatchMs();
    if ((now - lastFlushMs >= batchMs) || telemetryBufferFull()) {
        if (telemetryBufferCount() > 0) {
            lastFlushMs = now;
            postTelemetry();
        }
    }
}
