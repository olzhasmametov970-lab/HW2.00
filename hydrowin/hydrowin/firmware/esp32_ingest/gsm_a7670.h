/*
 * HydroWin — модем SIMCom A7670G (LTE) через AT + HTTP(S).
 * Плата: LILYGO T‑A7670G‑S3 (и совместимые).
 *
 * UART модема — Serial1 (как в примерах LilyGO), не Serial2.
 * Пины по умолчанию — A7670_* до include; при тишине begin() перебирает
 * известные карты LilyGO и печатает победителя.
 */
#ifndef GSM_A7670_H
#define GSM_A7670_H

#include <Arduino.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "driver/gpio.h"
#include "config.h"
#include "runtime_config.h"

#ifndef A7670_RX_PIN
#define A7670_RX_PIN 17
#endif
#ifndef A7670_TX_PIN
#define A7670_TX_PIN 16
#endif
#ifndef A7670_PWRKEY_PIN
#define A7670_PWRKEY_PIN 15
#endif
#ifndef A7670_BAUD
#define A7670_BAUD 115200
#endif
#ifndef A7670_PWRKEY_MS
#define A7670_PWRKEY_MS 1000
#endif
#ifndef A7670_PWRKEY_IDLE
#define A7670_PWRKEY_IDLE HIGH
#endif
#ifndef A7670_DTR_PIN
#define A7670_DTR_PIN -1
#endif
#ifndef A7670_POWER_SAVE_PIN
#define A7670_POWER_SAVE_PIN -1
#endif
#ifndef A7670_RESET_PIN
#define A7670_RESET_PIN -1
#endif
#ifndef A7670_RESET_LEVEL
#define A7670_RESET_LEVEL LOW
#endif
#ifndef A7670_UART
#define A7670_UART Serial1
#endif

/** Синхронизация времени модема не чаще раза в час. */
#ifndef A7670_TIME_SYNC_MS
#define A7670_TIME_SYNC_MS (60UL * 60UL * 1000UL)
#endif

#ifndef A7670_FORCE_EXTERNAL_GPS
#define A7670_FORCE_EXTERNAL_GPS 0
#endif

/** Кавычка / CR / LF в URL или USERDATA ломают AT+HTTPPARA. */
inline bool a7670AtParamSafe(const char* s)
{
    if (s == nullptr) return true;
    for (const char* p = s; *p; ++p) {
        const unsigned char c = (unsigned char)*p;
        if (c == '"' || c == '\r' || c == '\n' || c < 0x20) return false;
    }
    return true;
}

class A7670Modem {
public:
    A7670Modem() : _at(A7670_UART) {}

    bool begin()
    {
        if (_unavailable) {
            Serial.println("A7670: пропуск (недоступен до перезагрузки)");
            return false;
        }
        if (_ready) return true;

        Serial.println("\n--- A7670 init ---");
        if (!_bringUpWithScan()) {
            Serial.println(
                "A7670: нет ответа на AT — питание 5V VIN/LiPo, антенна LTE,");
            Serial.println(
                "       либо второй USB-C модема в ПК (115200) и команда AT");
            _unavailable = true;
            return false;
        }

        at("ATE0", "OK", 2000);
        at("AT+CMEE=2", "OK", 2000);

        if (!waitSimReady(60000)) {
            Serial.println("A7670: SIM не READY");
            _unavailable = true;
            return false;
        }
        if (!waitNetwork(90000)) {
            Serial.println("A7670: сеть не зарегистрирована");
            return false;
        }
        if (!attachData()) {
            Serial.println("A7670: PDP/data не поднялся");
            return false;
        }

        at("AT+CSSLCFG=\"sslversion\",0,3", "OK", 3000);
        at("AT+CSSLCFG=\"enableSNI\",0,1", "OK", 3000);

        _ready = true;
        _lastTimeSyncMs = 0;
        enableGnss();
        Serial.println("A7670: готов к HTTPS");
        return true;
    }

    bool isReady() const { return _ready; }
    bool isUnavailable() const { return _unavailable; }
    bool hasModemGnss() const
    {
        return A7670_FORCE_EXTERNAL_GPS ? false : _modemGnss;
    }
    const String& lastGnssRaw() const { return _lastGnssRaw; }
    const String& lastLbsRaw() const { return _lastLbsRaw; }
    const String& lastCellRaw() const { return _lastCellRaw; }
    void clearLockout()
    {
        _unavailable = false;
        _ready = false;
    }

    String exchangeAt(const char* cmd, uint32_t timeoutMs = 5000)
    {
        if (!probeAt(1500) && !begin()) {
            Serial.println("ERR: A7670 not responding");
            return String();
        }
        flushRx();
        _at.println(cmd);
        Serial.printf("A7670 >> %s\n", cmd);
        String resp = readAll(timeoutMs);
        Serial.print(resp);
        return resp;
    }

    /**
     * GNSS внутри модема SIM7670G / A7670E-FASE.
     * T-SIM7670G-S3 (не STAN): питание антенны = GPIO4 модема.
     * A7670G без FASE: GNSS в модеме нет.
     */
    void enableGnss()
    {
        if (!_ready) return;
        _modemGnss = false;

        if (A7670_FORCE_EXTERNAL_GPS) {
            Serial.println(
                "A7670: принудительно используем внешний GPS по UART (L76K), GNSS модема отключён.");
            return;
        }

        flushRx();
        _at.println("AT+CGMM");
        String model = readAll(2000);
        model.trim();
        Serial.print("A7670 model: ");
        Serial.println(model.length() ? model : "?");
        if (model.indexOf("A7670G") >= 0 &&
            model.indexOf("FASE") < 0) {
            Serial.println(
                "A7670G: внутреннего GNSS в модеме нет.");
            Serial.println(
                "        Ищем координаты только с внешнего L76K по UART или по LBS.");
            return;
        }

        // T-SIM7670G-S3: GPS Ant Power = modem GPIO4 HIGH.
        // Standard STAN использует GPIO1 — шлём оба, лишнее OK не мешает.
        at("AT+CGDRT=4,1", "OK", 2000, false);
        at("AT+CGSETV=4,1", "OK", 2000, false);
        at("AT+CGDRT=1,1", "OK", 2000, false);
        at("AT+CGSETV=1,1", "OK", 2000, false);

        flushRx();
        _at.println("AT+CGNSSPWR=1");
        String pwr = readAll(8000);
        const uint32_t waitReady = millis();
        while (millis() - waitReady < 12000UL) {
            while (_at.available()) {
                pwr += (char)_at.read();
            }
            if (pwr.indexOf("READY") >= 0 || pwr.indexOf("ERROR") >= 0) {
                break;
            }
            delay(50);
        }
        const bool pwrOk =
            (pwr.indexOf("OK") >= 0 || pwr.indexOf("READY") >= 0) &&
            pwr.indexOf("ERROR") < 0;
        if (!pwrOk) {
            Serial.println(
                "A7670: AT+CGNSSPWR нет — спутников на этой плате нет.");
            Serial.println(
                "        Дальше точка по вышкам (LBS).");
            return;
        }

        at("AT+CGNSSMODE=3", "OK", 3000, false);
        at("AT+CGPS=1", "OK", 5000, false);
        _modemGnss = true;
        Serial.println(
            "T-SIM7670G-S3: GNSS включён (GPIO4 антенна). Разъём GNSS, небо 5–15 мин");
    }

    bool pollGnss(double* lat, double* lon)
    {
        if (A7670_FORCE_EXTERNAL_GPS) return false;
        if (!_ready || !_modemGnss || lat == nullptr || lon == nullptr) {
            return false;
        }
        flushRx();
        _at.println("AT+CGNSSINFO");
        String r = readAll(2500);
        r.trim();
        _lastGnssRaw = r;
        if (_parseCgnss(r, lat, lon)) return true;
        // Пустой +CGNSSINFO: ,,,,,,,, — спутников нет, второй запрос не нужен.
        if (r.indexOf("+CGNSSINFO:") >= 0) return false;
        flushRx();
        _at.println("AT+CGPSINFO");
        r = readAll(2500);
        r.trim();
        if (r.length()) _lastGnssRaw = r;
        return _parseCgps(r, lat, lon);
    }

    /**
     * Приблизительные координаты по сотовым вышкам (A7670G без GNSS).
     * +CLBS: 0,<lon>,<lat>,<acc_m>  (SIMCom LBS). Нужен уже открытый PDP.
     */
    bool pollLbs(double* lat, double* lon, double* accM)
    {
        if (!_ready || lat == nullptr || lon == nullptr) return false;
        Serial.println("A7670: LBS запрос AT+CLBS=1 (до 25 с)...");
        flushRx();
        _at.println("AT+CLBS=1");
        String buf;
        const uint32_t start = millis();
        while (millis() - start < 25000UL) {
            while (_at.available()) {
                buf += (char)_at.read();
            }
            if (buf.indexOf("+CLBS:") >= 0) {
                delay(80);
                while (_at.available()) {
                    buf += (char)_at.read();
                }
                break;
            }
            if (buf.indexOf("ERROR") >= 0 && buf.indexOf("+CLBS:") < 0) {
                break;
            }
            delay(20);
        }
        buf.trim();
        _lastLbsRaw = buf;
        const int i = buf.indexOf("+CLBS:");
        if (i < 0) {
            Serial.println("A7670: LBS нет +CLBS (нужна сеть, как у HTTP 202)");
            if (buf.length()) Serial.println(buf);
            return false;
        }
        String rest = buf.substring(i + 6);
        rest.trim();
        int code = -1;
        double a = 0;
        double b = 0;
        double acc = 0;
        const int n = sscanf(rest.c_str(), "%d,%lf,%lf,%lf", &code, &a, &b, &acc);
        if (n < 3 || code != 0) {
            Serial.printf("A7670: LBS код %d (%s)\n", code, rest.c_str());
            if (code == 10) {
                Serial.println(
                    "  код 10 — LBS SIMCom не закрыл сеть (конфликт с HTTP).");
                Serial.println(
                    "  В РФ lbs-simcom.com часто не даёт точку. Нужны спутники или «Задать» в приложении.");
            }
            return false;
        }
        double la;
        double lo;
        if (fabs(a) <= 90.0 && fabs(b) > 90.0 && fabs(b) <= 180.0) {
            la = a;
            lo = b;
        } else if (fabs(a) > 90.0 && fabs(a) <= 180.0 && fabs(b) <= 90.0) {
            lo = a;
            la = b;
        } else {
            lo = a;
            la = b;
        }
        if (la < -90.0 || la > 90.0 || lo < -180.0 || lo > 180.0) return false;
        if (fabs(la) < 0.001 && fabs(lo) < 0.001) return false;
        *lat = la;
        *lon = lo;
        if (accM != nullptr) {
            *accM = acc > 1.0 ? acc : 500.0;
        }
        Serial.printf(
            "A7670 LBS: %.5f, %.5f (~%.0f м)  raw %s\n",
            la,
            lo,
            acc > 1.0 ? acc : 500.0,
            rest.c_str());
        return true;
    }

    /**
     * Текущая сота LTE/GSM (без сервера SIMCom).
     * AT+CPSI? → MCC-MNC, TAC/LAC, Cell ID.
     */
    bool pollCell(int* mcc, int* mnc, uint32_t* lac, uint32_t* cid, char* radio, size_t radioLen)
    {
        if (!_ready || mcc == nullptr || mnc == nullptr || lac == nullptr ||
            cid == nullptr) {
            return false;
        }
        flushRx();
        _at.println("AT+CPSI?");
        String r = readAll(3000);
        r.trim();
        _lastCellRaw = r;
        const int i = r.indexOf("+CPSI:");
        if (i < 0) return false;
        String rest = r.substring(i + 6);
        rest.trim();
        String f[8];
        int n = 0;
        if (!_splitCsv(rest, f, 8, &n) || n < 5) return false;
        String mode = f[0];
        mode.trim();
        mode.toUpperCase();
        if (mode.indexOf("NO SERVICE") >= 0 || mode.indexOf("UNKNOWN") >= 0) {
            return false;
        }
        int mc = 0;
        int mn = 0;
        if (sscanf(f[2].c_str(), "%d-%d", &mc, &mn) != 2) return false;
        String tac = f[3];
        tac.trim();
        uint32_t lacV = 0;
        if (tac.startsWith("0x") || tac.startsWith("0X")) {
            lacV = (uint32_t)strtoul(tac.c_str() + 2, nullptr, 16);
        } else {
            lacV = (uint32_t)strtoul(tac.c_str(), nullptr, 10);
        }
        uint32_t cidV = (uint32_t)strtoul(f[4].c_str(), nullptr, 10);
        if (mc <= 0 || cidV == 0) return false;
        *mcc = mc;
        *mnc = mn;
        *lac = lacV;
        *cid = cidV;
        const char* rad = "lte";
        if (mode.indexOf("GSM") >= 0) rad = "gsm";
        else if (mode.indexOf("WCDMA") >= 0 || mode.indexOf("UMTS") >= 0) {
            rad = "umts";
        } else if (mode.indexOf("NR") >= 0) rad = "nr";
        if (radio != nullptr && radioLen > 0) {
            strncpy(radio, rad, radioLen - 1);
            radio[radioLen - 1] = '\0';
        }
        Serial.printf(
            "A7670 CELL: %d-%d lac=%lu cid=%lu %s\n",
            mc,
            mn,
            (unsigned long)lacV,
            (unsigned long)cidV,
            rad);
        return true;
    }

    bool syncTime()
    {
        const uint32_t now = millis();
        if (_lastTimeSyncMs != 0 &&
            (now - _lastTimeSyncMs) < A7670_TIME_SYNC_MS) {
            return true;
        }

        flushRx();
        _at.println("AT+CCLK?");
        String resp = readAll(3000);
        int q1 = resp.indexOf('"');
        int q2 = resp.indexOf('"', q1 + 1);
        if (q1 < 0 || q2 <= q1) return false;

        const String ts = resp.substring(q1 + 1, q2);
        int yy, MM, dd, hh, mm, ss;
        if (sscanf(ts.c_str(), "%d/%d/%d,%d:%d:%d", &yy, &MM, &dd, &hh, &mm, &ss) !=
            6) {
            return false;
        }

        struct tm t = {};
        t.tm_year = (yy >= 70 ? yy : yy + 100);
        t.tm_mon = MM - 1;
        t.tm_mday = dd;
        t.tm_hour = hh;
        t.tm_min = mm;
        t.tm_sec = ss;
        const time_t epoch = mktime(&t);
        if (epoch > 1700000000) {
            struct timeval tv = {epoch, 0};
            settimeofday(&tv, nullptr);
            _lastTimeSyncMs = now;
            return true;
        }
        return false;
    }

    bool httpPost(
        const char* url,
        const char* headers,
        const char* body,
        int* outCode)
    {
        if (!_ready && !begin()) return false;
        if (url == nullptr || body == nullptr) return false;
        if (!a7670AtParamSafe(url) || !a7670AtParamSafe(headers)) {
            Serial.println("A7670: URL/headers содержат запрещённые символы");
            return false;
        }

        syncTime();
        httpSessionIdleCheck();

#if A7670_HTTP_KEEPALIVE
        if (!httpSessionEnsure(url, headers)) return false;
#else
        at("AT+HTTPTERM", "OK", 3000);
        if (!at("AT+HTTPINIT", "OK", 10000)) return false;
        at("AT+CSSLCFG=\"sslversion\",0,3", "OK", 3000);
        at("AT+CSSLCFG=\"enableSNI\",0,1", "OK", 3000);
        char para[192];
        snprintf(para, sizeof(para), "AT+HTTPPARA=\"URL\",\"%s\"", url);
        if (!at(para, "OK", 5000)) {
            at("AT+HTTPTERM", "OK", 3000);
            return false;
        }
        at("AT+HTTPPARA=\"CONTENT\",\"application/json\"", "OK", 3000);
        if (headers && headers[0]) {
            char ud[256];
            snprintf(ud, sizeof(ud), "AT+HTTPPARA=\"USERDATA\",\"%s\"", headers);
            at(ud, "OK", 3000);
        }
#endif

        const size_t len = strlen(body);
        char dataCmd[48];
        snprintf(dataCmd, sizeof(dataCmd), "AT+HTTPDATA=%u,20000", (unsigned)len);
        flushRx();
        _at.println(dataCmd);
        if (!readUntil("DOWNLOAD", 10000) && !readUntil("CONNECT", 2000)) {
            Serial.println("A7670: HTTPDATA — нет DOWNLOAD");
            httpSessionClose();
            return false;
        }
        _at.print(body);
        if (!readUntil("OK", 15000)) {
            Serial.println("A7670: HTTPDATA — нет OK после body");
            httpSessionClose();
            return false;
        }

        flushRx();
        _at.println("AT+HTTPACTION=1");
        int code = -1;
        int bodyLen = 0;
        if (!waitHttpAction(&code, &bodyLen)) {
#if !A7670_HTTP_KEEPALIVE
            at("AT+HTTPTERM", "OK", 3000, false);
#endif
            httpSessionClose();
            if (outCode) *outCode = code;
            return false;
        }
        if (bodyLen > 4) {
            char rd[40];
            snprintf(rd, sizeof(rd), "AT+HTTPREAD=0,%d", bodyLen);
            at(rd, "OK", 8000, false);
        }

#if !A7670_HTTP_KEEPALIVE
        at("AT+HTTPTERM", "OK", 3000, false);
#endif

        if (outCode) *outCode = code;
        const bool ok = code >= 200 && code < 300;
        if (ok) {
            _httpSessionLastMs = millis();
        } else {
            httpSessionClose();
        }
        return ok;
    }

    void httpSessionClose()
    {
        if (!_httpSessionOpen) return;
        at("AT+HTTPTERM", "OK", 3000, false);
        _httpSessionOpen = false;
        _httpSessionUrl[0] = '\0';
        _httpSessionHeaders[0] = '\0';
    }

private:
    struct PinMap {
        const char* name;
        int8_t rx;
        int8_t tx;
        int8_t pwrkey;
        int8_t dtr;
        int8_t psave;
        int pwrIdle;
        uint16_t pwrMs;
    };

    bool _ready = false;
    bool _unavailable = false;
    bool _modemGnss = false;
    bool _httpSessionOpen = false;
    char _httpSessionUrl[160] = {0};
    char _httpSessionHeaders[128] = {0};
    uint32_t _httpSessionLastMs = 0;
    String _lastGnssRaw;
    String _lastLbsRaw;
    String _lastCellRaw;
    uint32_t _lastTimeSyncMs = 0;
    HardwareSerial& _at;
    int8_t _rx = A7670_RX_PIN;
    int8_t _tx = A7670_TX_PIN;
    int8_t _pwrkey = A7670_PWRKEY_PIN;
    int8_t _dtr = A7670_DTR_PIN;
    int8_t _psave = A7670_POWER_SAVE_PIN;
    int _pwrIdle = A7670_PWRKEY_IDLE;
    uint16_t _pwrMs = A7670_PWRKEY_MS;

    void _applyMap(const PinMap& m)
    {
        _rx = m.rx;
        _tx = m.tx;
        _pwrkey = m.pwrkey;
        _dtr = m.dtr;
        _psave = m.psave;
        _pwrIdle = m.pwrIdle;
        _pwrMs = m.pwrMs;
    }

    void _printPins(const char* tag)
    {
        Serial.printf(
            "A7670 %s: UART1 RX=%d TX=%d PWRKEY=%d DTR=%d PSAVE=%d pulse=%u idle=%s\n",
            tag,
            _rx,
            _tx,
            _pwrkey,
            _dtr,
            _psave,
            (unsigned)_pwrMs,
            _pwrIdle == LOW ? "LOW" : "HIGH");
    }

    bool _bringUpWithScan()
    {
        const PinMap maps[] = {
            {"STAN", 5, 4, 46, 7, 42, LOW, 100},
            {"STAN-swap", 4, 5, 46, 7, 42, LOW, 100},
            {"STAN-1s", 5, 4, 46, 7, 42, LOW, 1000},
            {"SIM7670-S3", 10, 11, 18, 9, -1, LOW, 100},
            {"SIM7670-swap", 11, 10, 18, 9, -1, LOW, 100},
            {"A7608-S3", 18, 17, 15, 7, -1, LOW, 100},
            {"A7608-swap", 17, 18, 15, 7, -1, LOW, 100},
            {"legacy-16-17", 17, 16, 15, -1, -1, HIGH, 1000},
        };

        PinMap configured = {
            "configured",
            _rx,
            _tx,
            _pwrkey,
            _dtr,
            _psave,
            _pwrIdle,
            _pwrMs};

        if (_tryMap(configured)) return true;

        const int n = (int)(sizeof(maps) / sizeof(maps[0]));
        for (int i = 0; i < n; i++) {
            if (maps[i].rx == configured.rx && maps[i].tx == configured.tx &&
                maps[i].pwrkey == configured.pwrkey &&
                maps[i].pwrMs == configured.pwrMs) {
                continue;
            }
            if (_tryMap(maps[i])) return true;
        }
        return false;
    }

    bool _tryMap(const PinMap& m)
    {
        _applyMap(m);
        _printPins(m.name);
        _boardPrep();
        _openUart();

        if (probeAt(2000)) {
            Serial.printf("A7670: AT OK без PWRKEY (%s)\n", m.name);
            return true;
        }
        _dumpRx("before-pwrkey");
        _pulsePwrKey();
        delay(5000);
        _dumpRx("after-boot");
        if (probeAt(8000)) {
            Serial.printf("A7670: AT OK после PWRKEY (%s)\n", m.name);
            return true;
        }
        _dumpRx("fail");
        return false;
    }

    void _boardPrep()
    {
        // На STAN GPIO42 должен оставаться HIGH, даже если карта без PSAVE.
        if (A7670_POWER_SAVE_PIN >= 0) {
            pinMode(A7670_POWER_SAVE_PIN, OUTPUT);
            digitalWrite(A7670_POWER_SAVE_PIN, HIGH);
        }
        if (_psave >= 0 && _psave != A7670_POWER_SAVE_PIN) {
            pinMode(_psave, OUTPUT);
            digitalWrite(_psave, HIGH);
        }
        if (_dtr >= 0) {
            pinMode(_dtr, OUTPUT);
            digitalWrite(_dtr, LOW);
        }
        if (A7670_RESET_PIN >= 0) {
            pinMode(A7670_RESET_PIN, OUTPUT);
            digitalWrite(
                A7670_RESET_PIN,
                A7670_RESET_LEVEL == LOW ? HIGH : LOW);
        }
    }

    void _openUart()
    {
        _at.end();
        delay(30);
        pinMode(_rx, INPUT);
        pinMode(_tx, OUTPUT);
        digitalWrite(_tx, HIGH);
        _at.setRxBufferSize(1024);
        _at.begin(A7670_BAUD, SERIAL_8N1, _rx, _tx);
        delay(50);
    }

    void _pulsePwrKey()
    {
        if (_pwrkey < 0) return;
        Serial.printf(
            "A7670: импульс PWRKEY GPIO%d %u ms (idle=%s)...\n",
            _pwrkey,
            (unsigned)_pwrMs,
            _pwrIdle == LOW ? "LOW" : "HIGH");
        gpio_reset_pin((gpio_num_t)_pwrkey);
        pinMode(_pwrkey, OUTPUT);
        digitalWrite(_pwrkey, _pwrIdle);
        delay(100);
        digitalWrite(_pwrkey, _pwrIdle == LOW ? HIGH : LOW);
        delay(_pwrMs);
        digitalWrite(_pwrkey, _pwrIdle);
    }

    void _dumpRx(const char* tag)
    {
        if (!_at.available()) {
            Serial.printf("A7670 RX (%s): пусто\n", tag);
            return;
        }
        Serial.printf("A7670 RX (%s):", tag);
        int n = 0;
        while (_at.available() && n < 80) {
            Serial.printf(" %02X", (unsigned char)_at.read());
            n++;
        }
        Serial.println();
    }

    void flushRx()
    {
        while (_at.available()) (void)_at.read();
    }

    String readAll(uint32_t timeoutMs)
    {
        String buf;
        const uint32_t start = millis();
        while (millis() - start < timeoutMs) {
            while (_at.available()) buf += (char)_at.read();
            if (buf.indexOf("OK") >= 0 || buf.indexOf("ERROR") >= 0 ||
                buf.indexOf("+CME ERROR") >= 0) {
                delay(30);
                while (_at.available()) buf += (char)_at.read();
                break;
            }
            delay(10);
        }
        return buf;
    }

    bool readUntil(const char* token, uint32_t timeoutMs)
    {
        String buf;
        const uint32_t start = millis();
        while (millis() - start < timeoutMs) {
            while (_at.available()) buf += (char)_at.read();
            if (buf.indexOf(token) >= 0) return true;
            delay(10);
        }
        return false;
    }

    bool at(const char* cmd, const char* expect, uint32_t timeoutMs, bool logFail = true)
    {
        flushRx();
        _at.println(cmd);
        String resp = readAll(timeoutMs);
        const bool ok = resp.indexOf(expect) >= 0;
        if (!ok && logFail) {
            Serial.printf("A7670 AT fail: %s\n", cmd);
            Serial.print(resp);
        }
        return ok;
    }

    bool probeAt(uint32_t timeoutMs)
    {
        const uint32_t start = millis();
        while (millis() - start < timeoutMs) {
            flushRx();
            _at.print("AT\r\n");
            if (readUntil("OK", 600)) return true;
            delay(150);
        }
        return false;
    }

    bool waitSimReady(uint32_t timeoutMs)
    {
        const uint32_t start = millis();
        while (millis() - start < timeoutMs) {
            flushRx();
            _at.println("AT+CPIN?");
            String r = readAll(3000);
            if (r.indexOf("READY") >= 0) return true;
            if (r.indexOf("SIM PIN") >= 0) {
                Serial.println("A7670: нужен PIN карты");
                return false;
            }
            delay(1500);
        }
        return false;
    }

    bool waitNetwork(uint32_t timeoutMs)
    {
        const uint32_t start = millis();
        while (millis() - start < timeoutMs) {
            flushRx();
            _at.println("AT+CEREG?");
            String r = readAll(3000);
            if (r.indexOf(",1") >= 0 || r.indexOf(",5") >= 0) return true;
            _at.println("AT+CREG?");
            r = readAll(3000);
            if (r.indexOf(",1") >= 0 || r.indexOf(",5") >= 0) return true;
            delay(2000);
        }
        return false;
    }

    bool attachData()
    {
        at("AT+CGATT=1", "OK", 15000);
        char apn[96];
        snprintf(
            apn,
            sizeof(apn),
            "AT+CGDCONT=1,\"IP\",\"%s\"",
            rtConfig().gsmApn[0] ? rtConfig().gsmApn : "internet");
        at(apn, "OK", 5000);

        flushRx();
        _at.println("AT+NETOPEN?");
        String st = readAll(3000);
        if (st.indexOf("+NETOPEN: 1") >= 0 || st.indexOf("+NETOPEN:1") >= 0) {
            Serial.println("A7670: PDP уже открыт");
            return true;
        }

        flushRx();
        _at.println("AT+NETOPEN");
        String r = readAll(20000);
        if (r.indexOf("OK") >= 0 ||
            r.indexOf("already opened") >= 0 ||
            r.indexOf("already") >= 0) {
            return true;
        }
        Serial.print(r);
        Serial.println("A7670: NETOPEN — продолжаем, HTTP проверит сам");
        return true;
    }

    bool waitHttpAction(int* outCode, int* outLen = nullptr)
    {
        const uint32_t start = millis();
        String buf;
        while (millis() - start < 90000) {
            while (_at.available()) buf += (char)_at.read();
            int idx = buf.indexOf("+HTTPACTION:");
            if (idx >= 0) {
                int method = 0, code = 0, len = 0;
                sscanf(
                    buf.c_str() + idx,
                    "+HTTPACTION: %d,%d,%d",
                    &method,
                    &code,
                    &len);
                Serial.printf("A7670 HTTP %d (len=%d)\n", code, len);
                if (outCode) *outCode = code;
                if (outLen) *outLen = len;
                return code > 0;
            }
            delay(20);
        }
        return false;
    }

    static double _ddmmToDeg(const String& ddmm)
    {
        if (ddmm.length() < 3) return 0.0;
        const double v = ddmm.toDouble();
        const double deg = floor(v / 100.0);
        return deg + (v - deg * 100.0) / 60.0;
    }

    // SIM7670 часто отдаёт десятичные градусы (56.767), A7670 — NMEA ddmm.mmmm.
    static double _coordToDeg(const String& s, bool isLat)
    {
        if (s.length() < 3) return 0.0;
        const double v = s.toDouble();
        const double maxAbs = isLat ? 90.0 : 180.0;
        if (fabs(v) <= maxAbs) return v;
        return _ddmmToDeg(s);
    }

    static bool _splitCsv(const String& s, String* f, int maxN, int* outN)
    {
        int n = 0;
        int start = 0;
        for (int i = 0; i <= (int)s.length() && n < maxN; i++) {
            if (i == (int)s.length() || s[i] == ',') {
                f[n++] = s.substring(start, i);
                start = i + 1;
            }
        }
        *outN = n;
        return n > 0;
    }

    bool _parseLatLonFields(
        const String* f,
        int latIdx,
        int n,
        double* lat,
        double* lon)
    {
        if (n <= latIdx + 3) return false;
        if (f[latIdx].length() < 4 || f[latIdx + 2].length() < 4) return false;
        double la = _coordToDeg(f[latIdx], true);
        double lo = _coordToDeg(f[latIdx + 2], false);
        if (f[latIdx + 1].indexOf('S') >= 0 || f[latIdx + 1].indexOf('s') >= 0) {
            la = -la;
        }
        if (f[latIdx + 3].indexOf('W') >= 0 || f[latIdx + 3].indexOf('w') >= 0) {
            lo = -lo;
        }
        if (fabs(la) < 0.001 && fabs(lo) < 0.001) return false;
        *lat = la;
        *lon = lo;
        return true;
    }

    bool _parseCgps(const String& resp, double* lat, double* lon)
    {
        int i = resp.indexOf("+CGPSINFO:");
        if (i < 0) return false;
        String rest = resp.substring(i + 10);
        rest.trim();
        String f[12];
        int n = 0;
        if (!_splitCsv(rest, f, 12, &n)) return false;
        return _parseLatLonFields(f, 0, n, lat, lon);
    }

    bool _parseCgnss(const String& resp, double* lat, double* lon)
    {
        int i = resp.indexOf("+CGNSSINFO:");
        if (i < 0) return false;
        String rest = resp.substring(i + 11);
        rest.trim();
        String f[16];
        int n = 0;
        if (!_splitCsv(rest, f, 16, &n)) return false;
        return _parseLatLonFields(f, 4, n, lat, lon);
    }

    void httpSessionIdleCheck()
    {
#if A7670_HTTP_KEEPALIVE
        if (!_httpSessionOpen || _httpSessionLastMs == 0) return;
        if ((millis() - _httpSessionLastMs) >= A7670_HTTP_SESSION_IDLE_MS) {
            Serial.println("A7670: HTTP session idle timeout → close");
            httpSessionClose();
        }
#endif
    }

    bool httpSessionEnsure(const char* url, const char* headers)
    {
#if !A7670_HTTP_KEEPALIVE
        (void)url;
        (void)headers;
        return false;
#else
        if (url == nullptr) return false;
        if (!a7670AtParamSafe(url) || !a7670AtParamSafe(headers)) {
            Serial.println("A7670: URL/headers unsafe for AT");
            return false;
        }
        const char* hdr = headers ? headers : "";

        if (_httpSessionOpen) {
            if (strcmp(_httpSessionUrl, url) != 0 ||
                strcmp(_httpSessionHeaders, hdr) != 0) {
                httpSessionClose();
            }
        }

        if (_httpSessionOpen) return true;

        at("AT+HTTPTERM", "OK", 3000);
        if (!at("AT+HTTPINIT", "OK", 10000)) return false;
        at("AT+CSSLCFG=\"sslversion\",0,3", "OK", 3000);
        at("AT+CSSLCFG=\"enableSNI\",0,1", "OK", 3000);

        char para[192];
        snprintf(para, sizeof(para), "AT+HTTPPARA=\"URL\",\"%s\"", url);
        if (!at(para, "OK", 5000)) {
            httpSessionClose();
            return false;
        }
        at("AT+HTTPPARA=\"CONTENT\",\"application/json\"", "OK", 3000);
        if (hdr[0]) {
            char ud[256];
            snprintf(ud, sizeof(ud), "AT+HTTPPARA=\"USERDATA\",\"%s\"", hdr);
            at(ud, "OK", 3000);
        }

        strncpy(_httpSessionUrl, url, sizeof(_httpSessionUrl) - 1);
        strncpy(_httpSessionHeaders, hdr, sizeof(_httpSessionHeaders) - 1);
        _httpSessionOpen = true;
        _httpSessionLastMs = millis();
        Serial.println("A7670: HTTP keep-alive session open");
        return true;
#endif
    }
};

#endif // GSM_A7670_H
