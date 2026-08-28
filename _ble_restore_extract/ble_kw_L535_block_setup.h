#ifndef BLOCK_SETUP_H
#define BLOCK_SETUP_H

#include <Arduino.h>
#include "calibration.h"
#include "sensors.h"

// Настройка блока через USB (Serial Monitor, 115200 бод).
// Калибровка совпадает с scale_min / scale_max в приложении HydroWin.
//
// Команды:
//   HELP
//   SHOW                         — все каналы и калибровка
//   CAL <ch> <min> <max> [off]   — сохранить в NVS, ch = channel ingest
//   RESET <ch>                   — сброс к заводским из config.h
//
// Пример: CAL 0 0 380
//         CAL 1 -50 80

extern CalibrationStore g_calStore;

inline void printSetupHelp()
{
    Serial.println();
    Serial.println("=== HydroWin block setup (USB) ===");
    Serial.println("CAL <ch> <min> <max> [offset]  — калибровка канала");
    Serial.println("SHOW                           — текущие значения");
    Serial.println("RESET <ch>                     — заводская калибровка");
    Serial.println("HELP                           — эта справка");
    Serial.println();
}

inline void handleBlockSetupSerial()
{
    if (!Serial.available()) return;

    String line = Serial.readStringUntil('\n');
    line.trim();
    if (line.length() == 0) return;

    if (line.equalsIgnoreCase("HELP")) {
        printSetupHelp();
        return;
    }

    if (line.equalsIgnoreCase("SHOW")) {
        printSensorsDiag();
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
        if (!g_calStore.save((uint8_t)ch, minV, maxV, off)) {
            Serial.println("ERR min must be < max");
            return;
        }
        reloadSensorCalibration((uint8_t)ch);
        Serial.printf("OK CAL ch=%d %.2f..%.2f off=%.2f\n", ch, minV, maxV, off);
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
            g_calStore.resetChannel((uint8_t)ch, s->def.scaleMin, s->def.scaleMax);
            reloadSensorCalibration((uint8_t)ch);
            Serial.printf("OK RESET ch=%d\n", ch);
            return;
        }
        Serial.println("ERR channel not in SENSOR_TABLE");
        return;
    }

    Serial.printf("ERR unknown: %s (type HELP)\n", line.c_str());
}

#endif
