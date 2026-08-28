#ifndef SENSORS_H
#define SENSORS_H

#include <Arduino.h>
#include <math.h>
#include "config.h"
#include "calibration.h"

/** Неисправность петли 4–20 мА (ниже/выше рабочего диапазона). */
enum SensorLoopFault : uint8_t {
    LOOP_OK = 0,
    LOOP_OPEN = 1,   // < LOOP_OPEN_MA: обрыв / датчик не отвечает
    LOOP_SHORT = 2,  // > LOOP_SHORT_MA: короткое замыкание / перегруз
};

struct SensorReading {
    uint8_t channel;
    int32_t value;       // инженерные единицы (бар, °C) — целое
    float currentMa;     // ток петли для диагностики / fault
    bool valid;
    SensorLoopFault fault;
};

struct SensorRuntime {
    SensorDef def;
    SensorCalibration cal;
    float filteredAdc; // отфильтрованные мВ
    SensorReading reading;
    /** Debounce OPEN/SHORT: сколько тиков подряд кандидатный fault. */
    uint8_t faultStreak;
    SensorLoopFault pendingFault;
};

// Гистерезис вокруг 4…20 мА.
// 3.2: не ловить ложный OPEN из‑за занижения АЦП у низа шкалы (~4 мА → 3.1–3.5).
#ifndef LOOP_OPEN_MA
#define LOOP_OPEN_MA  3.2f
#endif
#ifndef LOOP_SHORT_MA
#define LOOP_SHORT_MA 21.0f
#endif
/** Сколько подряд тиков updateSensors() нужно для смены LOOP_OK ↔ OPEN/SHORT. */
#ifndef LOOP_FAULT_DEBOUNCE
#define LOOP_FAULT_DEBOUNCE 3
#endif

inline SensorRuntime g_sensors[MAX_SENSORS];
inline uint8_t g_sensorCount = 0;
inline CalibrationStore g_calStore;
inline bool g_sensorsSettled = false;

inline CalibrationStore& calStore() { return g_calStore; }

#define ADC_SAMPLES 16

#ifndef EMA_ALPHA
#define EMA_ALPHA 0.45f
#endif

inline float readAdcMilliVoltsAvg(uint8_t pin)
{
    uint32_t sum = 0;
    for (int i = 0; i < ADC_SAMPLES; i++) {
        sum += analogReadMilliVolts(pin);
    }
    return (float)sum / (float)ADC_SAMPLES;
}

inline float adcMilliVoltsToCurrentMa(float milliVolts)
{
    if (ADC_SHUNT_OHM <= 0.0f) return 0.0f;
    const float ma = (milliVolts / (float)ADC_SHUNT_OHM) * (float)ADC_MA_GAIN;
    return constrain(ma, 0.0f, 25.0f);
}

inline SensorRuntime* findSensorByChannel(uint8_t channel)
{
    for (uint8_t i = 0; i < g_sensorCount; i++) {
        if (g_sensors[i].def.channel == channel) return &g_sensors[i];
    }
    return nullptr;
}

inline void initSensors()
{
    analogReadResolution(12);
    g_sensorsSettled = false;

    static const SensorDef defaults[] = { SENSOR_TABLE };
    const uint8_t tableSize = sizeof(defaults) / sizeof(defaults[0]);
    g_sensorCount = tableSize > MAX_SENSORS ? MAX_SENSORS : tableSize;

    g_calStore.begin();

    for (uint8_t i = 0; i < g_sensorCount; i++) {
        g_sensors[i].def = defaults[i];
        analogSetPinAttenuation(g_sensors[i].def.pin, ADC_11db);

        g_sensors[i].filteredAdc = readAdcMilliVoltsAvg(g_sensors[i].def.pin);

        g_calStore.load(
            g_sensors[i].def.channel,
            g_sensors[i].def.scaleMin,
            g_sensors[i].def.scaleMax,
            g_sensors[i].def.enabled,
            &g_sensors[i].cal);

#if HYDROWIN_FORCE_SENSOR_TABLE_ENABLED
        if (g_sensors[i].cal.enabled != g_sensors[i].def.enabled) {
            g_calStore.setEnabled(
                g_sensors[i].def.channel,
                g_sensors[i].def.enabled);
        }
        g_sensors[i].cal.enabled = g_sensors[i].def.enabled;
#endif

        g_sensors[i].reading.channel = g_sensors[i].def.channel;
        // До первого updateSensors() — не слать «фантомные» нули как OK.
        g_sensors[i].reading.valid = false;
        g_sensors[i].reading.value = 0;
        g_sensors[i].reading.currentMa = 0.0f;
        g_sensors[i].reading.fault = LOOP_OK;
        g_sensors[i].faultStreak = 0;
        g_sensors[i].pendingFault = LOOP_OK;
    }

#if HYDROWIN_FORCE_SENSOR_TABLE_ENABLED
    Serial.println("Sensors: enabled from SENSOR_TABLE (NVS en overridden)");
#endif
}

inline void reloadSensorCalibration(uint8_t channel)
{
    SensorRuntime* s = findSensorByChannel(channel);
    if (s == nullptr) return;
    g_calStore.load(
        channel,
        s->def.scaleMin,
        s->def.scaleMax,
        s->def.enabled,
        &s->cal);
}

inline bool setSensorEnabled(uint8_t channel, bool enabled)
{
    SensorRuntime* s = findSensorByChannel(channel);
    if (s == nullptr) return false;
    g_calStore.setEnabled(channel, enabled);
    s->cal.enabled = enabled;
    if (!enabled) {
        s->reading.valid = false;
        s->reading.fault = LOOP_OK;
        s->faultStreak = 0;
        s->pendingFault = LOOP_OK;
    }
    return true;
}

inline SensorLoopFault _instantLoopFault(float currentMa)
{
    if (currentMa < LOOP_OPEN_MA) return LOOP_OPEN;
    if (currentMa > LOOP_SHORT_MA) return LOOP_SHORT;
    return LOOP_OK;
}

inline void updateSensors()
{
    for (uint8_t i = 0; i < g_sensorCount; i++) {
        if (!g_sensors[i].cal.enabled) {
            g_sensors[i].reading.valid = false;
            g_sensors[i].reading.fault = LOOP_OK;
            g_sensors[i].faultStreak = 0;
            g_sensors[i].pendingFault = LOOP_OK;
            continue;
        }

        const float rawMilliVolts = readAdcMilliVoltsAvg(g_sensors[i].def.pin);
        g_sensors[i].filteredAdc +=
            EMA_ALPHA * (rawMilliVolts - g_sensors[i].filteredAdc);

        const float currentMa = adcMilliVoltsToCurrentMa(g_sensors[i].filteredAdc);
        g_sensors[i].reading.channel = g_sensors[i].def.channel;
        g_sensors[i].reading.currentMa = currentMa;

        const SensorLoopFault instant = _instantLoopFault(currentMa);
        SensorLoopFault& pending = g_sensors[i].pendingFault;
        uint8_t& streak = g_sensors[i].faultStreak;
        SensorLoopFault& applied = g_sensors[i].reading.fault;

        if (instant == pending) {
            if (streak < 255) streak++;
        } else {
            pending = instant;
            streak = 1;
        }

        // Debounce: подтверждаем OPEN/SHORT и возврат в OK.
        if (streak >= LOOP_FAULT_DEBOUNCE) {
            applied = pending;
        }

        if (applied == LOOP_OPEN || applied == LOOP_SHORT) {
            g_sensors[i].reading.valid = false;
            // В value при fault кладём округлённый ток (мА) для телеметрии/BLE.
            g_sensors[i].reading.value = (int32_t)lroundf(currentMa);
            continue;
        }

        g_sensors[i].reading.value = applyCalibrationInt(currentMa, g_sensors[i].cal);
        g_sensors[i].reading.fault = LOOP_OK;
        g_sensors[i].reading.valid = true;
    }
    g_sensorsSettled = true;
}

inline uint8_t sensorCount() { return g_sensorCount; }

inline const SensorRuntime* sensorAt(uint8_t index)
{
    if (index >= g_sensorCount) return nullptr;
    return &g_sensors[index];
}

inline const char* loopFaultLabel(SensorLoopFault f)
{
    switch (f) {
    case LOOP_OPEN:  return "OPEN";
    case LOOP_SHORT: return "SHORT";
    default:         return "OK";
    }
}

inline void printSensorsDiag()
{
    Serial.println("--- sensors ---");
    for (uint8_t i = 0; i < g_sensorCount; i++) {
        const SensorRuntime& s = g_sensors[i];
        if (!s.cal.enabled) {
            Serial.printf("CH%u %-6s OFF\n", s.def.channel, s.def.label);
            continue;
        }
        const char* st = !s.reading.valid ? "WAIT"
            : loopFaultLabel(s.reading.fault);
        Serial.printf(
            "CH%u %-6s pin=%u | %4.0f mV | ток %5.2f mA | val=%ld %s"
            "  (scale %.0f..%.0f off=%+.0f)\n",
            s.def.channel,
            s.def.label,
            s.def.pin,
            s.filteredAdc,
            s.reading.currentMa,
            (long)s.reading.value,
            st,
            s.cal.scaleMin,
            s.cal.scaleMax,
            s.cal.offset);
    }
}

#endif
