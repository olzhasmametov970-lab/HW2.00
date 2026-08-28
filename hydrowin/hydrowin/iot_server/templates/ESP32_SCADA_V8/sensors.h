#ifndef SENSORS_H
#define SENSORS_H

#include <Arduino.h>

// Эти переменные используются WebSocket и API
extern float temperature;
extern float pressure;

// -------------------------
// Настройки
// -------------------------

#define TEMP_PIN   34
#define PRESS_PIN  35

#define ADC_SAMPLES 32
#define EMA_ALPHA   0.15f

#define ADC_MAX     4095.0f
#define ADC_VREF    3.3f

#define SHUNT       150.0f

// Диапазоны датчиков
#define TEMP_MIN   -50.0f
#define TEMP_MAX    200.0f

#define PRESS_MIN    0.0f
#define PRESS_MAX   25.0f

// -------------------------

float tempFiltered = 0.0f;
float pressFiltered = 0.0f;

//------------------------------------------------

float readADC(uint8_t pin)
{
    uint32_t sum = 0;

    for (int i = 0; i < ADC_SAMPLES; i++)
    {
        sum += analogRead(pin);
    }

    return (float)sum / ADC_SAMPLES;
}

//------------------------------------------------

void initSensors()
{
    analogReadResolution(12);

    analogSetPinAttenuation(TEMP_PIN, ADC_11db);
    analogSetPinAttenuation(PRESS_PIN, ADC_11db);

    tempFiltered = readADC(TEMP_PIN);
    pressFiltered = readADC(PRESS_PIN);
}

//------------------------------------------------

void updateSensors()
{
    // Усреднение
    float rawTemp = readADC(TEMP_PIN);
    float rawPress = readADC(PRESS_PIN);

    // EMA фильтр
    tempFiltered += EMA_ALPHA * (rawTemp - tempFiltered);
    pressFiltered += EMA_ALPHA * (rawPress - pressFiltered);

    // ADC -> Напряжение
    float tempVoltage = tempFiltered * ADC_VREF / ADC_MAX;
    float pressVoltage = pressFiltered * ADC_VREF / ADC_MAX;

    // Напряжение -> Ток
    float tempCurrent = tempVoltage / SHUNT;
    float pressCurrent = pressVoltage / SHUNT;

    // Ограничение диапазона 4-20 мА
    tempCurrent = constrain(tempCurrent, 0.004f, 0.020f);
    pressCurrent = constrain(pressCurrent, 0.004f, 0.020f);

    // 4-20 мА -> Температура
    temperature =
        TEMP_MIN +
        ((tempCurrent - 0.004f) / 0.016f) *
        (TEMP_MAX - TEMP_MIN);

    // 4-20 мА -> Давление
    pressure =
        PRESS_MIN +
        ((pressCurrent - 0.004f) / 0.016f) *
        (PRESS_MAX - PRESS_MIN);

    // Диагностика
    Serial.printf(
        "ADC T=%4.0f | %.2fV | %.2fmA | %6.2fC   ||   "
        "ADC P=%4.0f | %.2fV | %.2fmA | %6.2fbar\n",
        tempFiltered,
        tempVoltage,
        tempCurrent * 1000.0f,
        temperature,
        pressFiltered,
        pressVoltage,
        pressCurrent * 1000.0f,
        pressure
    );
}

#endif