/*
 * Политика отправки телеметрии: покой по стабильности 4–20 мА.
 *
 * Цель ≤100 МБ/мес LTE: актив 30 с, покой 5 мин, keep-alive HTTP.
 * Стабильный OPEN/SHORT (отключённый канал) НЕ мешает покою — только смена.
 */
#ifndef TELEMETRY_POLICY_H
#define TELEMETRY_POLICY_H

#include <Arduino.h>
#include "config.h"
#include "sensors.h"

static bool s_telemIdle = false;
static bool s_telemIdleLogged = false;
static uint32_t s_telemStableSinceMs = 0;
static int32_t s_telemBaselineVal[MAX_SENSORS];
static SensorLoopFault s_telemBaselineFault[MAX_SENSORS];
static bool s_telemBaselineInit = false;

inline bool geoTelemetryEnabled()
{
#if HYDROWIN_GPS_ENABLED
    return HYDROWIN_GEO_TELEMETRY != 0;
#else
    return false;
#endif
}

inline void telemetryPolicySnapshotBaseline()
{
    for (uint8_t i = 0; i < g_sensorCount; i++) {
        s_telemBaselineVal[i] = g_sensors[i].reading.value;
        s_telemBaselineFault[i] = g_sensors[i].reading.fault;
    }
    s_telemBaselineInit = true;
    s_telemStableSinceMs = millis();
}

/** Есть ли значимое изменение относительно baseline (не «шум»). */
inline bool telemetrySensorsActive()
{
    if (!g_sensorsSettled) return true;
    if (!s_telemBaselineInit) return true;

    for (uint8_t i = 0; i < g_sensorCount; i++) {
        const SensorRuntime& s = g_sensors[i];
        if (!s.cal.enabled) continue;

        // Смена fault (OK↔OPEN/SHORT) — сразу активный режим.
        if (s.reading.fault != s_telemBaselineFault[i]) return true;

        // Стабильный OPEN/SHORT: канал «застыл» — не мешает покою.
        if (s.reading.fault == LOOP_OPEN || s.reading.fault == LOOP_SHORT) {
            continue;
        }

        if (!s.reading.valid) continue;

        const int32_t delta = s.reading.value - s_telemBaselineVal[i];
        const int32_t ad = delta < 0 ? -delta : delta;
        if (ad > (int32_t)TELEMETRY_IDLE_VALUE_THRESH) return true;
    }
    return false;
}

inline void telemetryPolicyTick()
{
    if (!s_telemBaselineInit) {
        telemetryPolicySnapshotBaseline();
        s_telemIdle = false;
        return;
    }

    if (telemetrySensorsActive()) {
        if (s_telemIdle) {
            Serial.println("telem: ACTIVE (датчик изменился) → POST каждые 30 с");
            s_telemIdleLogged = false;
        }
        s_telemIdle = false;
        s_telemStableSinceMs = millis();
        // Подтянуть baseline к текущим значениям, чтобы не «залипать» на старом.
        for (uint8_t i = 0; i < g_sensorCount; i++) {
            if (!g_sensors[i].cal.enabled) continue;
            s_telemBaselineVal[i] = g_sensors[i].reading.value;
            s_telemBaselineFault[i] = g_sensors[i].reading.fault;
        }
        return;
    }

    const uint32_t stableMs =
        (uint32_t)TELEMETRY_IDLE_STABLE_SEC * 1000UL;
    if ((millis() - s_telemStableSinceMs) >= stableMs) {
        if (!s_telemIdle) {
            Serial.printf(
                "telem: IDLE (≥%u с стабильно) → POST каждые %lu с\n",
                (unsigned)TELEMETRY_IDLE_STABLE_SEC,
                (unsigned long)(TELEMETRY_BATCH_GSM_IDLE_MS / 1000UL));
            s_telemIdleLogged = true;
        }
        s_telemIdle = true;
    }
}

inline bool telemetryIsIdle() { return s_telemIdle; }

inline bool telemetryForceFlush()
{
    if (!s_telemBaselineInit) return true;
    return telemetrySensorsActive();
}

/** После успешного POST: baseline = текущее; idle не сбрасываем. */
inline void telemetryPolicyOnFlush()
{
    for (uint8_t i = 0; i < g_sensorCount; i++) {
        s_telemBaselineVal[i] = g_sensors[i].reading.value;
        s_telemBaselineFault[i] = g_sensors[i].reading.fault;
    }
    s_telemBaselineInit = true;
    // Не трогаем s_telemStableSinceMs / s_telemIdle — иначе каждый POST
    // в покое заново ждал бы 3 мин до idle.
}

inline void printTelemetryPolicyStatus()
{
    const uint32_t stableSec = s_telemBaselineInit
        ? (millis() - s_telemStableSinceMs) / 1000UL
        : 0;
    Serial.println("--- telem policy (≤100 МБ/мес LTE) ---");
    Serial.printf(
        " mode=%s  flush=%lu s  (active %lu / idle %lu)\n",
        s_telemIdle ? "IDLE" : "ACTIVE",
        (unsigned long)(
            (s_telemIdle ? TELEMETRY_BATCH_GSM_IDLE_MS : TELEMETRY_BATCH_GSM_MS) /
            1000UL),
        (unsigned long)(TELEMETRY_BATCH_GSM_MS / 1000UL),
        (unsigned long)(TELEMETRY_BATCH_GSM_IDLE_MS / 1000UL));
    Serial.printf(
        " stable %lu / %u с  thresh=±%d  geo=%s  gps_every=%lu мин\n",
        (unsigned long)stableSec,
        (unsigned)TELEMETRY_IDLE_STABLE_SEC,
        (int)TELEMETRY_IDLE_VALUE_THRESH,
        geoTelemetryEnabled() ? "on" : "off",
        (unsigned long)(HYDROWIN_GPS_TELEM_INTERVAL_MS / 60000UL));
    Serial.printf(
        " HTTP keep-alive=%d  session_idle=%lu мин\n",
        (int)A7670_HTTP_KEEPALIVE,
        (unsigned long)(A7670_HTTP_SESSION_IDLE_MS / 60000UL));
    Serial.println(
        " SIM: используйте IoT/M2M (шаг тарификации 1 КБ), не обычную «голосовую».");
}

#endif
