/*
 * HydroWin — full_ta7670 для LILYGO T‑SIM7670G‑S3 ESP32-S3 16МБ
 *          (СТАРАЯ РЕВИЗИЯ H707 — ЧЁРНАЯ ПЛАТА, 1× USB-C + micro-USB)
 *
 * Отладочная плата LILYGO T-SIM7670G-S3 H707:
 *   - ESP32-S3 16MB Flash / 8MB PSRAM (N16R8)
 *   - Модем SIM7670G LTE Cat.1 4G (SimCom) — ВНУТРИ МОДЕМА ЕСТЬ GNSS:
 *     GPS/ГЛОНАСС/Galileo/BeiDou. Отдельного внешнего L76K НЕТ!
 *   - Слот micro-SIM. USB-C ESP-USB + micro-USB Modem-USB.
 *
 * Пины UART SIM7670G — карта «SIM7670-S3» из gsm_a7670.h и LILYGO utilities.h:
 *   ESP RX = GPIO 10 ← TX модема
 *   ESP TX = GPIO 11 → RX модема
 *   PWRKEY = GPIO 18   (LOW 100 мс, idle LOW)
 *   DTR    = GPIO 9    (LOW чтобы модем не спал)
 *   RESET  = GPIO 17   (LOW)
 *   RING   = GPIO 3
 *   LED    = GPIO 12   (LOW active!)
 *   BAT_ADC= GPIO 4    (делитель напряжения батареи)
 *   SOLAR  = GPIO 5    (ADC солнечной панели)
 *   SD-CARD: CS=13 MOSI=14 MISO=47 SCK=21
 *   GNSS ANTENNA POWER: MODEM_GPS_ENABLE_GPIO=4 (AUXVDD pin)
 *
 * Пины GNSS — ВСТРОЕННЫЙ В МОДЕМ SIM7670G (AT+CGNSSPWR, AT+CGNSSINFO,
 *   NMEA через UART1 модема). Внешний GPS UART2 на этой плате не используется.
 *
 * Связь по умолчанию: LINK_WIFI — Wi-Fi first, GSM LTE fallback.
 *   Меняется: LINK wifi / LINK gsm / LINK auto
 */

#ifndef HYDROWIN_GPS_ENABLED
#define HYDROWIN_GPS_ENABLED 1
#endif

// Для отладочных стендов — Wi-Fi first, удобно.
// Для установки в поле: поменяйте на LINK auto или LINK gsm.
#ifndef LINK_MODE
#define LINK_MODE LINK_WIFI
#endif

// У этой платы (H707) внешнего L76K нет.
// Используем ТОЛЬКО встроенный GNSS модема SIM7670G через AT+CGNSS.
#ifndef A7670_FORCE_EXTERNAL_GPS
#define A7670_FORCE_EXTERNAL_GPS 0
#endif

#ifndef BAT_ADC_PIN
#define BAT_ADC_PIN 4
#endif
#ifndef SOLAR_ADC_PIN
#define SOLAR_ADC_PIN 5
#endif

// ─── UART SIM7670G (Serial1) — карта «SIM7670-S3» (gsm_a7670.h:L545) ─────────
#ifndef A7670_RX_PIN
#define A7670_RX_PIN 10
#endif
#ifndef A7670_TX_PIN
#define A7670_TX_PIN 11
#endif
#ifndef A7670_PWRKEY_PIN
#define A7670_PWRKEY_PIN 18
#endif
#ifndef A7670_DTR_PIN
#define A7670_DTR_PIN 9
#endif
#ifndef A7670_POWER_SAVE_PIN
#define A7670_POWER_SAVE_PIN -1
#endif
#ifndef A7670_RESET_PIN
#define A7670_RESET_PIN 17
#endif
#ifndef A7670_RESET_LEVEL
#define A7670_RESET_LEVEL LOW
#endif
#ifndef A7670_PWRKEY_IDLE
#define A7670_PWRKEY_IDLE LOW
#endif
#ifndef A7670_PWRKEY_MS
#define A7670_PWRKEY_MS 100
#endif
#ifndef A7670_BAUD
#define A7670_BAUD 115200
#endif

// ─── Внешний GPS L76K (на H707 ОТСУТСТВУЕТ) ─────────────────────────────────
// Пины legacy для совместимости — реально не используются.
#ifndef GPS_RX_PIN
#define GPS_RX_PIN 48
#endif
#ifndef GPS_TX_PIN
#define GPS_TX_PIN 45
#endif
#ifndef GPS_WAKEUP_PIN
#define GPS_WAKEUP_PIN 0
#endif
#ifndef GPS_BAUD
#define GPS_BAUD 9600
#endif

// ─── 6 каналов 4–20 мА (ADC) — T‑SIM7670G‑S3 H707, подписи GPIO на краю ─────
// Занято платой / модемом — НЕ паять датчики:
//   03=RING  04=BAT_ADC  05=SOLAR  09=DTR  10=modem RX  11=modem TX
//   12=LED   13=SD_CS    17=RESET  18=PWRKEY  21=SD_SCK  47=SD_MISO
// Свободные на разъёме (правый/левый ряд): 01, 02, 06, 07, 08, 15, 16, …
// GPIO14 = SD MOSI (прошивка SD не трогает; лучше без карты в слоте).
//
// CH0 = GPIO01 — уже разведён под давление (шунт 150 Ω → GND).
#ifndef SENSOR_TABLE
#define SENSOR_TABLE \
    { 1,  0,   0.0f, 250.0f, "P0",  true  }, \
    { 2,  1, -50.0f, 200.0f, "T1",  false }, \
    { 6,  2, -50.0f, 200.0f, "T2",  false }, \
    { 8,  3,   0.0f, 250.0f, "P1",  false }, \
    { 15, 4,   0.0f, 250.0f, "ch4", false }, \
    { 16, 5,   0.0f, 250.0f, "ch5", false }
#endif

#include <Arduino.h>
#include <NimBLEDevice.h>
#include <math.h>
#include <string.h>
#include <WiFi.h>

#include <config.h>
#include <runtime_config.h>
#include <sensors.h>
#include <telemetry_buffer.h>
#include <offline_queue.h>
#include <hydrowin_ingest.h>
#include <block_setup.h>
#include <ble_config.h>

// LED_PIN = GPIO 12, активный уровень LOW (светится когда GND)
#ifndef LED_PIN
#define LED_PIN 12
#endif

bool g_gpsValid = false;
double g_gpsLat = 0.0;
double g_gpsLon = 0.0;
double g_gpsAcc = 0.0;
uint32_t g_gpsNmeaBytes = 0;
bool g_cellValid = false;
int g_cellMcc = 0;
int g_cellMnc = 0;
uint32_t g_cellLac = 0;
uint32_t g_cellCid = 0;
char g_cellRadio[8] = "lte";

static double _nmeaToDecimal(const String& ddmm)
{
    if (ddmm.length() == 0) return 0.0;
    const double v = ddmm.toDouble();
    const double degPart = floor(v / 100.0);
    const double minPart = v - (degPart * 100.0);
    return degPart + (minPart / 60.0);
}

static bool _parseGprmc(const String& sentence)
{
    int asterisk = sentence.indexOf('*');
    String core = asterisk >= 0 ? sentence.substring(0, asterisk) : sentence;

    String fields[7];
    int fieldIdx = 0;
    int lastComma = -1;
    for (int i = 0; i <= core.length(); i++) {
        if (i == core.length() || core.charAt(i) == ',') {
            if (fieldIdx < 7) {
                fields[fieldIdx] = core.substring(lastComma + 1, i);
            }
            fieldIdx++;
            lastComma = i;
        }
    }
    if (fieldIdx < 7) return false;
    if (!fields[2].equalsIgnoreCase("A")) return false;

    double lat = _nmeaToDecimal(fields[3]);
    double lon = _nmeaToDecimal(fields[5]);
    if (fields[4].equalsIgnoreCase("S")) lat = -lat;
    if (fields[6].equalsIgnoreCase("W")) lon = -lon;
    if (fabs(lat) < 0.001 && fabs(lon) < 0.001) return false;
    g_gpsLat = lat;
    g_gpsLon = lon;
    g_gpsAcc = 10.0;
    g_gpsValid = true;
    return true;
}

static bool _parseGpgga(const String& sentence)
{
    int asterisk = sentence.indexOf('*');
    String core = asterisk >= 0 ? sentence.substring(0, asterisk) : sentence;

    String fields[8];
    int fieldIdx = 0;
    int lastComma = -1;
    for (int i = 0; i <= core.length(); i++) {
        if (i == core.length() || core.charAt(i) == ',') {
            if (fieldIdx < 8) {
                fields[fieldIdx] = core.substring(lastComma + 1, i);
            }
            fieldIdx++;
            lastComma = i;
        }
    }
    if (fieldIdx < 7) return false;
    if (fields[6].toInt() < 1) return false;

    double lat = _nmeaToDecimal(fields[2]);
    double lon = _nmeaToDecimal(fields[4]);
    if (fields[3].equalsIgnoreCase("S")) lat = -lat;
    if (fields[5].equalsIgnoreCase("W")) lon = -lon;
    if (fabs(lat) < 0.001 && fabs(lon) < 0.001) return false;
    g_gpsLat = lat;
    g_gpsLon = lon;
    g_gpsAcc = 10.0;
    g_gpsValid = true;
    return true;
}

// Внешний GPS по UART2 — здесь НЕ ИСПОЛЬЗУЕТСЯ (встроенный GNSS модема).
static HardwareSerial& GPS_SERIAL = Serial2;

static void _gpsLoop()
{
    static String line;
    while (GPS_SERIAL.available()) {
        const char c = (char)GPS_SERIAL.read();
        if (c == '\r') continue;
        if (c == '\n') {
            if (line.startsWith("$GPRMC") || line.startsWith("$GNRMC")) {
                _parseGprmc(line);
            } else if (
                line.startsWith("$GPGGA") || line.startsWith("$GNGGA")) {
                _parseGpgga(line);
            }
            line = "";
        } else if (line.length() < 120) {
            line += c;
            g_gpsNmeaBytes++;
        }
    }
}

static uint32_t s_lastSampleMs = 0;
static uint32_t s_lastFlushMs = 0;
static uint32_t s_lastDiagMs = 0;
static uint32_t s_lastGpsPollMs = 0;
static uint32_t s_lastCellMs = 0;

void setup()
{
    Serial.begin(115200);
    delay(300);

    pinMode(LED_PIN, OUTPUT);
    digitalWrite(LED_PIN, LOW);

    if (A7670_POWER_SAVE_PIN >= 0) {
        pinMode(A7670_POWER_SAVE_PIN, OUTPUT);
        digitalWrite(A7670_POWER_SAVE_PIN, HIGH);
    }
    if (A7670_DTR_PIN >= 0) {
        pinMode(A7670_DTR_PIN, OUTPUT);
        digitalWrite(A7670_DTR_PIN, LOW);
    }
    // Внешний GPS WAKE не трогаем — этой плате его нет.

    Serial.printf(
        "Pins: modem UART1 RX=%d TX=%d PWRKEY=%d | GNSS=embedded-in-SIM7670G\n",
        A7670_RX_PIN,
        A7670_TX_PIN,
        A7670_PWRKEY_PIN);
    Serial.println("A7670: при тишине ~1 мин будет авто-подбор 3-х карт пинов LilyGO.");

    loadRuntimeConfig();
    initOfflineQueue();

    Serial.println();
    Serial.printf(" HydroWin %s (T-SIM7670G-S3 internal GNSS SIM7670G)\n", VERSION);
    Serial.printf(" Link: %s | values: integer | GPS: internal modem GNSS\n",
                  linkModeName(rtConfig().linkMode));
    Serial.println();

    printSetupHelp();

    // Внешний L76K не запускаем.
    // Встроенный GNSS модема сам инициализируется при gsm.begin().

    initSensors();
    initLink();
    bleBegin();

    g_gpsValid = false;
    s_lastSampleMs = millis();
    s_lastFlushMs = millis();

    Serial.println("\nСистема готова (ESP32-S3 + SIM7670G LTE + built-in GNSS).\n");
}

void loop()
{
    handleBlockSetupSerial();
    updateSensors();
    bleLoop();

    // UART2 не подключён к L76K на этой плате — _gpsLoop() не вызываем.

    const uint32_t now = millis();

    const uint32_t batchMs = telemetryBatchMs();
    const bool willPost =
        telemetryBufferCount() > 0 &&
        ((now - s_lastFlushMs >= batchMs) || telemetryBufferFull());

    // Опрос встроенного GNSS (SIM7670G) и CELL данных —
    // ТОЛЬКО когда модем GSM isReady (требует AT-канал).
    if (!willPost && hydroGsmModem().isReady() &&
        (now - s_lastGpsPollMs >= 8000UL)) {
        s_lastGpsPollMs = now;

        if (!A7670_FORCE_EXTERNAL_GPS) {
            double lat = 0, lon = 0;
            if (hydroGsmModem().pollGnss(&lat, &lon)) {
                g_gpsLat = lat;
                g_gpsLon = lon;
                g_gpsAcc = 15.0;
                g_gpsValid = true;
            }
        }

        if (s_lastCellMs == 0 || now - s_lastCellMs >= 30000UL) {
            s_lastCellMs = now;
            int mcc = 0, mnc = 0;
            uint32_t lac = 0, cid = 0;
            char radio[8] = {0};
            if (hydroGsmModem().pollCell(&mcc, &mnc, &lac, &cid, radio, sizeof(radio))) {
                g_cellMcc = mcc;
                g_cellMnc = mnc;
                g_cellLac = lac;
                g_cellCid = cid;
                strncpy(g_cellRadio, radio[0] ? radio : "lte", sizeof(g_cellRadio) - 1);
                g_cellRadio[sizeof(g_cellRadio) - 1] = '\0';
                g_cellValid = true;
            }
        }
    }

#if HYDROWIN_SERIAL_DIAG
    if (now - s_lastDiagMs >= HYDROWIN_SERIAL_DIAG_MS) {
        s_lastDiagMs = now;
        printSensorsDiag();

        // Диагностика GPS — для встроенного в модем SIM7670G
        if (!hydroGsmModem().isReady()) {
            Serial.println("GPS: модем ещё инициализируется, статус GNSS пока не показателен.");
        } else {
            Serial.println("GPS mode: modem-gnss (SIM7670G internal, GPS+GLONASS+BeiDou)");
            if (g_gpsValid) {
                Serial.printf(
                    "GPS: %.5f, %.5f  acc=%.0f m\n",
                    g_gpsLat,
                    g_gpsLon,
                    g_gpsAcc);
            } else {
                Serial.printf(
                    "GPS: нет точки | GNSS в модеме=%s\n",
                    hydroGsmModem().hasModemGnss() ? "да (SIM7670G)" : "нет");
                if (hydroGsmModem().hasModemGnss()) {
                    Serial.println(
                        "  T-SIM7670G-S3: GNSS внутри модема. Антенна в разъём GNSS. "
                        "При первом старте открытое небо 5–15 минут.");
                }
                const String& raw = hydroGsmModem().lastGnssRaw();
                if (raw.length()) {
                    String one = raw;
                    one.replace('\r', ' ');
                    one.replace('\n', ' ');
                    if (one.length() > 160) one = one.substring(0, 160);
                    Serial.print("  GNSS AT: ");
                    Serial.println(one);
                }
                const String& lbs = hydroGsmModem().lastLbsRaw();
                if (lbs.length()) {
                    String one = lbs;
                    one.replace('\r', ' ');
                    one.replace('\n', ' ');
                    if (one.length() > 160) one = one.substring(0, 160);
                    Serial.print("  LBS: ");
                    Serial.println(one);
                } else {
                    Serial.println("  LBS: ещё не запрашивали (первый раз ~15 с после старта)");
                }
            }
        }

        // CELL данные
        if (hydroGsmModem().isReady()) {
            if (g_cellValid) {
                Serial.printf(
                    "CELL: %d-%d lac=%lu cid=%lu %s (OpenCellID LBS fallback)\n",
                    g_cellMcc,
                    g_cellMnc,
                    (unsigned long)g_cellLac,
                    (unsigned long)g_cellCid,
                    g_cellRadio);
            } else {
                Serial.println("CELL: ещё нет AT+CPSI? (через ~8 с после регистрации)");
            }
        } else {
            Serial.println("CELL: GSM-модем не готов — пропуск.");
        }
    }
#endif

    if (now - s_lastSampleMs >= TELEMETRY_SAMPLE_MS) {
        s_lastSampleMs = now;
        sampleTelemetry();
    }

    if ((now - s_lastFlushMs >= batchMs) || telemetryBufferFull()) {
        if (telemetryBufferCount() > 0) {
            s_lastFlushMs = now;
            postTelemetry();
        }
    }
}