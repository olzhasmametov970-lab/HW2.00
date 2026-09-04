/*
 * HydroWin — full_ta7670 для LILYGO T‑A7670G‑S3 STANDARD ESP32-S3 (ЗЕЛЁНАЯ ПЛАТА)
 *
 * Модель: LILYGO T-A7670G-S3 Standard (S3 STAN rev H802/H803, зелёный PCB, 2× USB-C)
 *         МОДУЛЬ A7670G (SimCom LTE Cat.1, без внутреннего GNSS) +
 *         ВНЕШНИЙ GPS-приёмник L76K (UART2, зелёная керамическая антенна)
 *
 * Карта пинов модема — gsm_a7670.h: «STAN» (не SIM7670-S3 и не wiki-H707 17/18/9/10!)
 *   ESP32 RX = GPIO 5  ← TX модема
 *   ESP32 TX = GPIO 4  → RX модема
 *   PWRKEY    = GPIO 46   (LOW 100 мс)
 *   DTR       = GPIO 7    (постоянно LOW = не спать)
 *   POWER_SAVE= GPIO 42
 *   RING      = GPIO 6
 *   RESET     = GPIO 6?   (не документирован — пусть будет RING pin, active LOW)
 *
 * Внешний GPS L76K по UART2 (Serial2):
 *   На части ревизий A7670G+L76K рабочая пара: ESP RX=45 ← L76K TX, ESP TX=48 → L76K RX
 *   (у LilyGO в utilities.h имена MODEM_GPS_RX/TX=48/45 — на практике для NMEA
 *    часто нужен swap; при NMEA=0 пробуйте другую пару).
 *   WAKE = GPIO 0 HIGH
 *   ⚠️ GPS работает независимо от LTE/SIM.
 *
 * Связь LINK_AUTO: сначала LTE A7670G, при недоступности — Wi-Fi fallback.
 */

#ifndef HYDROWIN_GPS_ENABLED
#define HYDROWIN_GPS_ENABLED 1
#endif
#ifndef HYDROWIN_GEO_TELEMETRY
#define HYDROWIN_GEO_TELEMETRY 1
#endif

#ifndef LINK_MODE
#define LINK_MODE LINK_AUTO
#endif

// Периодическая таблица датчиков + статус GPS/CELL в Serial.
#ifndef HYDROWIN_SERIAL_DIAG
#define HYDROWIN_SERIAL_DIAG 1
#endif
#ifndef HYDROWIN_SERIAL_DIAG_MS
#define HYDROWIN_SERIAL_DIAG_MS 3000UL
#endif

// A7670G не имеет GNSS внутри — используется только внешний L76K.
#ifndef A7670_FORCE_EXTERNAL_GPS
#define A7670_FORCE_EXTERNAL_GPS 1
#endif

// ─── UART модема A7670G — карта «STAN» (gsm_a7670.h:L542) ───────────────────
#ifndef A7670_RX_PIN
#define A7670_RX_PIN 5
#endif
#ifndef A7670_TX_PIN
#define A7670_TX_PIN 4
#endif
#ifndef A7670_PWRKEY_PIN
#define A7670_PWRKEY_PIN 46
#endif
#ifndef A7670_DTR_PIN
#define A7670_DTR_PIN 7
#endif
#ifndef A7670_POWER_SAVE_PIN
#define A7670_POWER_SAVE_PIN 42
#endif
#ifndef A7670_RESET_PIN
#define A7670_RESET_PIN 6
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

// ─── Внешний GPS L76K UART2 (Serial2) ───────────────────────────────────────
// Рабочая пара для HydroWin на T‑A7670G‑S3 + L76K (NMEA идёт при RX=45):
#ifndef GPS_RX_PIN
#define GPS_RX_PIN 45
#endif
#ifndef GPS_TX_PIN
#define GPS_TX_PIN 48
#endif
#ifndef GPS_WAKEUP_PIN
#define GPS_WAKEUP_PIN 0
#endif
#ifndef GPS_BAUD
#define GPS_BAUD 9600
#endif

// ─── Каналы 4–20 мА — T‑A7670G‑S3 Standard ──────────────────────────────────
// ESP32-S3 АЦП только GPIO 1…10 (ADC1) и 11…20 (ADC2).
// IO35/36/37/38/39/40/41/47 — НЕ АЦП → analog* на них = LoadProhibited / reboot.
// Занято: IO02/03 I2C, IO04–07 модем, IO08 BAT, IO10–13 SD, IO17 PPS,
//         IO18 SOLAR, IO45/48 GPS, IO46 PWRKEY.
// Свободные АЦП на разъёме: IO01, IO09, IO14, IO15, IO16 (макс. 5 каналов).
#ifndef SENSOR_TABLE
#define SENSOR_TABLE \
    { 1,  0,   0.0f, 250.0f, "P0",  true  }, \
    { 9,  1, -50.0f, 200.0f, "T1",  false }, \
    { 14, 2, -50.0f, 200.0f, "T2",  false }, \
    { 15, 3,   0.0f, 250.0f, "P1",  false }, \
    { 16, 4,   0.0f, 250.0f, "ch4", false }
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
#include <telemetry_policy.h>

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

static HardwareSerial& GPS_SERIAL = Serial2;
static String g_lastGsv;
static String g_lastGga;

static void _gpsLoop()
{
    static String line;
    while (GPS_SERIAL.available()) {
        const char c = (char)GPS_SERIAL.read();
        if (c == '\r') continue;
        if (c == '\n') {
            if (hydroGpsNmeaEcho()) Serial.println(line);
            if (line.startsWith("$GPRMC") || line.startsWith("$GNRMC")) {
                _parseGprmc(line);
            } else if (line.startsWith("$GPGGA") || line.startsWith("$GNGGA")) {
                _parseGpgga(line);
                g_lastGga = line;
            } else if (line.startsWith("$GPGSV") || line.startsWith("$GLGSV") ||
                       line.startsWith("$GNGSV")) {
                g_lastGsv = line;
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
    // Геолокация: L76K только при HYDROWIN_GEO_TELEMETRY (экономия UART/питания).
    if (geoTelemetryEnabled() && A7670_FORCE_EXTERNAL_GPS && GPS_WAKEUP_PIN >= 0) {
        pinMode(GPS_WAKEUP_PIN, OUTPUT);
        digitalWrite(GPS_WAKEUP_PIN, HIGH);
        delay(200);  // L76K: дать питание до открытия UART
    }

    Serial.printf(
        "Pins: modem UART1 RX=%d TX=%d PWRKEY=%d | GPS L76K UART2 RX=%d TX=%d WAKE=%d\n",
        A7670_RX_PIN,
        A7670_TX_PIN,
        A7670_PWRKEY_PIN,
        GPS_RX_PIN,
        GPS_TX_PIN,
        GPS_WAKEUP_PIN);
    Serial.println("A7670: при тишине ~1 мин — авто-подбор 3-х карт пинов LilyGO.");

    loadRuntimeConfig();
    initOfflineQueue();

    Serial.println();
    Serial.printf(" HydroWin %s (T-A7670G-S3 + external L76K GPS)\n", VERSION);
    Serial.printf(" Link: %s | batch %lu s (idle %lu s) | geo=%s\n",
                  linkModeName(rtConfig().linkMode),
                  (unsigned long)(TELEMETRY_BATCH_GSM_MS / 1000UL),
                  (unsigned long)(TELEMETRY_BATCH_GSM_IDLE_MS / 1000UL),
                  geoTelemetryEnabled() ? "on" : "off");
    Serial.println();

    printSetupHelp();

    if (geoTelemetryEnabled() && A7670_FORCE_EXTERNAL_GPS) {
        GPS_SERIAL.begin(GPS_BAUD, SERIAL_8N1, GPS_RX_PIN, GPS_TX_PIN);
        Serial.printf(
            "L76K: UART2 %d бод (geo telemetry, lat/lon каждые %lu мин)\n",
            GPS_BAUD,
            (unsigned long)(HYDROWIN_GPS_TELEM_INTERVAL_MS / 60000UL));
    }

    initSensors();
    initLink();
    bleBegin();

    g_gpsValid = false;
    s_lastSampleMs = millis();
    s_lastFlushMs = millis();

    Serial.println("\nСистема готова (ESP32-S3 + A7670G LTE + L76K external GPS).\n");
    printTelemetryPolicyStatus();
}

void loop()
{
    handleBlockSetupSerial();
    updateSensors();
    bleLoop();
    telemetryPolicyTick();

    if (geoTelemetryEnabled() && A7670_FORCE_EXTERNAL_GPS) {
        _gpsLoop();
    }

    const uint32_t now = millis();

    const bool willPost = telemetryShouldFlush(now - s_lastFlushMs);

    // Опрос модемного GNSS / CELL — только для geo и диагностики.
    if (geoTelemetryEnabled() && !willPost && hydroGsmModem().isReady() &&
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

#if HYDROWIN_SERIAL_DIAG
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
#endif
    }

#if HYDROWIN_SERIAL_DIAG
    if (now - s_lastDiagMs >= HYDROWIN_SERIAL_DIAG_MS) {
        s_lastDiagMs = now;
        printSensorsDiag();

        // ── Диагностика GPS для внешнего L76K (работает даже без SIM!) ────
        if (A7670_FORCE_EXTERNAL_GPS) {
            Serial.printf(
                "GPS mode: external-l76k | UART2 RX=%d ← TX L76K | TX=%d → RX L76K | WAKE=%d | NMEA=%u B\n",
                GPS_RX_PIN,
                GPS_TX_PIN,
                GPS_WAKEUP_PIN,
                (unsigned)g_gpsNmeaBytes);
            if (g_gpsValid) {
                Serial.printf(
                    "GPS: %.5f, %.5f  acc≈%.0f m (L76K)\n",
                    g_gpsLat,
                    g_gpsLon,
                    g_gpsAcc);
            } else {
                if (g_gpsNmeaBytes <= 64) {
                    Serial.println(
                        "GPS: L76K молчит по UART2 (0 байт NMEA). Причины:\n"
                        "  1) Антенна не в разъёме GPS (не MAIN LTE)\n"
                        "  2) WAKE GPIO0 не HIGH / нет 3.3В на L76K\n"
                        "  3) Пины UART: сейчас RX=45 TX=48; если снова 0 B —\n"
                        "     в .ino поменяйте на GPS_RX_PIN 48 / GPS_TX_PIN 45\n"
                        "  4) Нет модуля L76K на этой плате (тогда нужна другая модель)");
                } else {
                    Serial.println(
                        "GPS: L76K слушает (NMEA-байт идут), но нет 3D-фиксации.\n"
                        "       → ВЫВЕДИТЕ ПЛАТУ НА ОТКРЫТОЕ НЕБО (окно не годится!).\n"
                        "       → Холодный старт: 60–180 секунд. GPSRESET / GPSNMEA ON");
                    if (g_lastGsv.length()) {
                        Serial.print("GPS last GSV: ");
                        Serial.println(g_lastGsv);
                    }
                    if (g_lastGga.length()) {
                        Serial.print("GPS last GGA: ");
                        Serial.println(g_lastGga);
                    }
                }
            }
        } else {
            if (!hydroGsmModem().isReady()) {
                Serial.println("GPS: модем ещё инициализируется…");
            } else {
                Serial.println("GPS mode: modem-gnss");
                if (g_gpsValid) {
                    Serial.printf(
                        "GPS: %.5f, %.5f  acc=%.0f m\n",
                        g_gpsLat,
                        g_gpsLon,
                        g_gpsAcc);
                } else {
                    Serial.println("GPS: нет точки");
                }
            }
        }

        // CELL данные (только при работающем GSM)
        if (hydroGsmModem().isReady()) {
            if (g_cellValid) {
                Serial.printf(
                    "CELL: %d-%d lac=%lu cid=%lu %s (для LBS OpenCellID)\n",
                    g_cellMcc,
                    g_cellMnc,
                    (unsigned long)g_cellLac,
                    (unsigned long)g_cellCid,
                    g_cellRadio);
            } else {
                Serial.println("CELL: AT+CPSI? ещё не вернул данные…");
            }
        } else {
            Serial.println("CELL: GSM-модем не готов (нет SIM / нет сети / нет питания 5В 2А)");
        }
    }
#endif

    if (now - s_lastSampleMs >= TELEMETRY_SAMPLE_MS) {
        s_lastSampleMs = now;
        sampleTelemetry();
    }

    if (willPost) {
        s_lastFlushMs = now;
        postTelemetry();
    }
}
