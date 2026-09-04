/*
 * RAM-буфер телеметрии: раз в SAMPLE_MS пишем строку
 * [ts, ch0..ch5, faultMask], раз в BATCH_MS — один HTTPS POST {"d":[...]}.
 * Значения каналов — целые (бар / °C); при обрыве/КЗ — ток мА (целый).
 * faultMask: uint16, 2 бита × канал (CH0–CH5) → 12 бит.
 */
#ifndef TELEMETRY_BUFFER_H
#define TELEMETRY_BUFFER_H

#include <Arduino.h>
#include <time.h>
#include <string.h>
#include <stdio.h>

#include "config.h"
#include "sensors.h"
#include "telemetry_policy.h"

#ifndef HYDROWIN_GPS_ENABLED
#define HYDROWIN_GPS_ENABLED 0
#endif

#if HYDROWIN_GPS_ENABLED
extern bool g_gpsValid;
extern double g_gpsLat;
extern double g_gpsLon;
extern double g_gpsAcc;
extern bool g_cellValid;
extern int g_cellMcc;
extern int g_cellMnc;
extern uint32_t g_cellLac;
extern uint32_t g_cellCid;
extern char g_cellRadio[8];
#endif

#ifndef TELEMETRY_SAMPLE_MS
#define TELEMETRY_SAMPLE_MS 1000UL
#endif
// Интервал отправки задаёт telemetryBatchMs() в hydrowin_ingest.h.
// TELEMETRY_BATCH_WIFI_MS / TELEMETRY_BATCH_GSM_MS — единственные «живые» define.
#ifndef TELEMETRY_BUF_MAX
#define TELEMETRY_BUF_MAX 60
#endif

/** Число каналов в industrial JSON (совпадает с BLE / MAX_SENSORS). */
#ifndef TELEMETRY_CHANNELS
#define TELEMETRY_CHANNELS 6
#endif

struct TelemetryRow {
    uint32_t ts;       // unix; 0 = нет NTP
    int32_t v[TELEMETRY_CHANNELS];  // CH0–CH5 (при обрыве/КЗ — ток мА, целый)
    uint8_t mask;      // бит i = значение валидно / есть fault (6 бит)
    uint16_t faultMask; // 2 бита на канал: 0=ok, 1=open, 2=short (до CH5)
};

static TelemetryRow s_telemBuf[TELEMETRY_BUF_MAX];
static uint16_t s_telemCount = 0;
static uint16_t s_telemHead = 0; // кольцевой буфер

#if HYDROWIN_GPS_ENABLED && HYDROWIN_GEO_TELEMETRY
static uint32_t s_lastGpsTelemMs = 0;

inline bool telemetryShouldIncludeGps()
{
    if (!g_gpsValid) return false;
    const uint32_t now = millis();
    if (s_lastGpsTelemMs == 0 ||
        (now - s_lastGpsTelemMs) >= HYDROWIN_GPS_TELEM_INTERVAL_MS) {
        s_lastGpsTelemMs = now;
        return true;
    }
    return false;
}
#else
inline bool telemetryShouldIncludeGps() { return false; }
#endif

inline uint16_t telemetryBufferCount() { return s_telemCount; }

inline void telemetryBufferClear()
{
    s_telemCount = 0;
    s_telemHead = 0;
}

inline bool telemetryBufferFull() { return s_telemCount >= TELEMETRY_BUF_MAX; }

inline void telemetryBufferPushSample()
{
    if (!g_sensorsSettled) return;

    time_t now = time(nullptr);
    const uint32_t ts = (now >= 1700000000) ? (uint32_t)now : 0;

    auto fillRow = [&](TelemetryRow& row) {
        row.ts = ts;
        row.mask = 0;
        row.faultMask = 0;
        for (uint8_t ch = 0; ch < TELEMETRY_CHANNELS; ch++) {
            row.v[ch] = 0;
            const SensorRuntime* s = findSensorByChannel(ch);
            if (s == nullptr || !s->cal.enabled) continue;
            if (!s->reading.valid && s->reading.fault == LOOP_OK) continue;

            if (s->reading.fault == LOOP_OPEN) {
                row.v[ch] = s->reading.value;
                row.faultMask |= (uint16_t)(1u << (ch * 2));
            } else if (s->reading.fault == LOOP_SHORT) {
                row.v[ch] = s->reading.value;
                row.faultMask |= (uint16_t)(2u << (ch * 2));
            } else {
                row.v[ch] = s->reading.value;
            }
            row.mask |= (uint8_t)(1u << ch);
        }
    };

    // Покой: одна строка в буфере (не раздуваем батч и не flush каждые 60 с).
    if (telemetryIsIdle() && s_telemCount > 0) {
        const uint16_t idx =
            (uint16_t)((s_telemHead + s_telemCount - 1) % TELEMETRY_BUF_MAX);
        fillRow(s_telemBuf[idx]);
        return;
    }

    if (s_telemCount >= TELEMETRY_BUF_MAX) {
        // Переполнение: сдвигаем голову (кольцо), теряем самую старую секунду
        s_telemHead = (uint16_t)((s_telemHead + 1) % TELEMETRY_BUF_MAX);
        s_telemCount = TELEMETRY_BUF_MAX - 1;
    }

    const uint16_t idx =
        (uint16_t)((s_telemHead + s_telemCount) % TELEMETRY_BUF_MAX);
    fillRow(s_telemBuf[idx]);

    s_telemCount++;
}

/** Собрать промышленный JSON без кучи временных String. */
inline String telemetryBufferBuildJson()
{
    // 60 × ~80 байт было избыточно; актив ≤32 строк × ~50 B ≈ 2 КБ + gps
    char* buf = (char*)malloc(4096);
    if (buf == nullptr) {
        return String("{\"d\":[]}");
    }
    size_t pos = 0;
    const size_t cap = 4095;

    auto append = [&](const char* s) {
        const size_t n = strlen(s);
        if (pos + n >= cap) return;
        memcpy(buf + pos, s, n);
        pos += n;
        buf[pos] = '\0';
    };
    auto appendInt = [&](long v) {
        char tmp[16];
        snprintf(tmp, sizeof(tmp), "%ld", v);
        append(tmp);
    };

    append("{\"d\":[");
    for (uint16_t i = 0; i < s_telemCount; i++) {
        if (i) append(",");
        const uint16_t idx =
            (uint16_t)((s_telemHead + i) % TELEMETRY_BUF_MAX);
        const TelemetryRow& r = s_telemBuf[idx];
        append("[");
        appendInt((long)r.ts);
        for (uint8_t ch = 0; ch < TELEMETRY_CHANNELS; ch++) {
            append(",");
            if (r.mask & (1u << ch)) {
                appendInt((long)r.v[ch]);
            } else {
                append("null");
            }
        }
        append(",");
        appendInt((long)r.faultMask);
        append("]");
    }
    append("]");

#if HYDROWIN_GPS_ENABLED
    if (telemetryShouldIncludeGps()) {
        char gps[64];
        snprintf(
            gps,
            sizeof(gps),
            ",\"gps\":{\"lat\":%.5f,\"lon\":%.5f}",
            g_gpsLat,
            g_gpsLon);
        append(gps);
    }
#endif

    append("}");
    String out(buf);
    free(buf);
    return out;
}

#endif // TELEMETRY_BUFFER_H
