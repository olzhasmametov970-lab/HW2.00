#ifndef SENSORS_H
#define SENSORS_H

#include <Arduino.h>
#include "config.h"
#include "calibration.h"

struct SensorReading {
    uint8_t channel;
    float value;
    float currentMa;
    bool valid;
};

struct SensorRuntime {
    SensorDef def;
    SensorCalibration cal;
    float filteredAdc;
    SensorReading reading;
};

static SensorRuntime g_sensors[MAX_SENSORS];
static uint8_t g_sensorCount = 0;

static CalibrationStore g_calStore;

inline CalibrationStore& calStore() { return g_calStore; }

#define ADC_SAMPLES 32
#define EMA_ALPHA   0.15f
#define ADC_MAX     4095.0f
#define ADC_VREF    3.3f

inline float readAdcAvg(uint8_t pin)
{
    uint32_t sum = 0;
    for (int i = 0; i < ADC_SAMPLES; i++) {
        sum += analogRead(pin);
    }
    return (float)sum / ADC_SAMPLES;
}

inline float adcToCurrentMa(float adc)
{
    const float voltage = adc * ADC_VREF / ADC_MAX;
    const float amps = voltage / ADC_SHUNT_OHM;
    return constrain(amps * 1000.0f, 0.0f, 25.0f);
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

    static const SensorDef defaults[] = { SENSOR_TABLE };
    const uint8_t tableSize = sizeof(defaults) / sizeof(defaults[0]);
    g_sensorCount = tableSize > MAX_SENSORS ? MAX_SENSORS : tableSize;

    g_calStore.begin();

    for (uint8_t i = 0; i < g_sensorCount; i++) {
        g_sensors[i].def = defaults[i];
        analogSetPinAttenuation(g_sensors[i].def.pin, ADC_11db);
        g_sensors[i].filteredAdc = readAdcAvg(g_sensors[i].def.pin);

        g_calStore.load(
            g_sensors[i].def.channel,
            g_sensors[i].def.scaleMin,
            g_sensors[i].def.scaleMax,
            g_sensors[i].def.enabled,
            &g_sensors[i].cal);

        g_sensors[i].reading.channel = g_sensors[i].def.channel;
        g_sensors[i].reading.valid = g_sensors[i].cal.enabled;
        g_sensors[i].reading.value = 0.0f;
        g_sensors[i].reading.currentMa = 0.0f;
    }
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
    s->reading.valid = enabled;
    return true;
}

inline void updateSensors()
{
    for (uint8_t i = 0; i < g_sensorCount; i++) {
        if (!g_sensors[i].cal.enabled) {
            g_sensors[i].reading.valid = false;
            continue;
        }

        const float raw = readAdcAvg(g_sensors[i].def.pin);
        g_sensors[i].filteredAdc +=
            EMA_ALPHA * (raw - g_sensors[i].filteredAdc);

        const float currentMa = adcToCurrentMa(g_sensors[i].filteredAdc);
        const float value = applyCalibration(currentMa, g_sensors[i].cal);

        g_sensors[i].reading.channel = g_sensors[i].def.channel;
        g_sensors[i].reading.value = value;
        g_sensors[i].reading.currentMa = currentMa;
        g_sensors[i].reading.valid = true;
    }
}

inline uint8_t sensorCount() { return g_sensorCount; }

inline const SensorRuntime* sensorAt(uint8_t index)
{
    if (index >= g_sensorCount) return nullptr;
    return &g_sensors[index];
}

inline void printSensorsDiag()
{
    for (uint8_t i = 0; i < g_sensorCount; i++) {
        const SensorRuntime& s = g_sensors[i];
        const float voltage = s.filteredAdc * ADC_VREF / ADC_MAX;
        Serial.printf(
            "CH%u %-8s pin=%u en=%u | ADC=%4.0f | %.2fV | %.2fmA | %.2f (%.1f..%.1f)\n",
            s.def.channel,
            s.def.label,
            s.def.pin,
            s.cal.enabled ? 1 : 0,
            s.filteredAdc,
            voltage,
            s.reading.currentMa,
            s.reading.value,
            s.cal.scaleMin,
            s.cal.scaleMax);
    }
}

#endif
