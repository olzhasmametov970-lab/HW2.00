#ifndef CALIBRATION_H
#define CALIBRATION_H

#include <Preferences.h>
#include <Arduino.h>
#include <math.h>

// Калибровка 4–20 мА → инженерные единицы хранится на ESP32 (NVS).
// Приложение задаёт scale_min / scale_max при настройке на объекте (USB или Wi‑Fi).
// Сервер получает уже готовые value — без пересчёта на бэкенде.

struct SensorCalibration {
    float scaleMin;
    float scaleMax;
    float offset;  // добавка после линейного преобразования
    bool enabled;
};

class CalibrationStore {
public:
    void begin()
    {
        _prefs.begin("hydrowin", false);
    }

    void load(
        uint8_t channel,
        float defaultMin,
        float defaultMax,
        bool defaultEnabled,
        SensorCalibration* out)
    {
        char keyMin[8];
        char keyMax[8];
        char keyOff[8];
        char keyEn[8];
        snprintf(keyMin, sizeof(keyMin), "s%u_min", channel);
        snprintf(keyMax, sizeof(keyMax), "s%u_max", channel);
        snprintf(keyOff, sizeof(keyOff), "s%u_off", channel);
        snprintf(keyEn, sizeof(keyEn), "s%u_en", channel);

        out->scaleMin = _prefs.getFloat(keyMin, defaultMin);
        out->scaleMax = _prefs.getFloat(keyMax, defaultMax);
        out->offset = _prefs.getFloat(keyOff, 0.0f);
        out->enabled = _prefs.getBool(keyEn, defaultEnabled);
    }

    bool save(
        uint8_t channel,
        float scaleMin,
        float scaleMax,
        float offset = 0.0f,
        bool enabled = true)
    {
        if (scaleMin >= scaleMax) return false;

        char keyMin[8];
        char keyMax[8];
        char keyOff[8];
        char keyEn[8];
        snprintf(keyMin, sizeof(keyMin), "s%u_min", channel);
        snprintf(keyMax, sizeof(keyMax), "s%u_max", channel);
        snprintf(keyOff, sizeof(keyOff), "s%u_off", channel);
        snprintf(keyEn, sizeof(keyEn), "s%u_en", channel);

        _prefs.putFloat(keyMin, scaleMin);
        _prefs.putFloat(keyMax, scaleMax);
        _prefs.putFloat(keyOff, offset);
        _prefs.putBool(keyEn, enabled);
        return true;
    }

    bool setEnabled(uint8_t channel, bool enabled)
    {
        char keyEn[8];
        snprintf(keyEn, sizeof(keyEn), "s%u_en", channel);
        _prefs.putBool(keyEn, enabled);
        return true;
    }

    bool resetChannel(
        uint8_t channel,
        float defaultMin,
        float defaultMax,
        bool defaultEnabled = true)
    {
        return save(channel, defaultMin, defaultMax, 0.0f, defaultEnabled);
    }

private:
    Preferences _prefs;
};

/** Линейный пересчёт 4–20 мА → float (для ZERO/MATCH). */
inline float applyCalibration(float currentMa, const SensorCalibration& cal)
{
    const float clamped = constrain(currentMa, 4.0f, 20.0f);
    const float ratio = (clamped - 4.0f) / 16.0f;
    float value = cal.scaleMin + ratio * (cal.scaleMax - cal.scaleMin) + cal.offset;
    // Давление и др. с scale_min >= 0: не уходить в минус из‑за ZERO/шума.
    if (cal.scaleMin >= 0.0f && value < 0.0f) {
        value = 0.0f;
    }
    return value;
}

/** Инженерное значение для телеметрии/BLE — целое. */
inline int32_t applyCalibrationInt(float currentMa, const SensorCalibration& cal)
{
    return (int32_t)lroundf(applyCalibration(currentMa, cal));
}

#endif
