/*
 * Изоляция GPS: копия логики LilyGO examples/GPS_BuiltIn
 * для платы LILYGO T-SIM7670G-S3 (пины как LILYGO_T_SIM7670G_S3).
 *
 * Без HydroWin, без HTTP, без датчиков — только модем + GNSS.
 *
 * Arduino IDE:
 *   Плата: ESP32S3 Dev Module
 *   USB CDC On Boot: Enable
 *   Flash Size: 16MB
 *   PSRAM: QSPI PSRAM
 *   Порт: ESP-USB (не Modem-USB)
 *   Монитор: 115200
 *
 * После загрузки вынесите плату на улицу, антенна GNSS плашмя.
 * Ждите строки CGNSSINFO каждые 15 с.
 */

#define MODEM_RX_PIN 10
#define MODEM_TX_PIN 11
#define MODEM_DTR_PIN 9
#define BOARD_PWRKEY_PIN 18
#define MODEM_RESET_PIN 17
#define MODEM_RESET_LEVEL LOW
#define MODEM_GPS_ENABLE_GPIO 4
#define MODEM_GPS_ENABLE_LEVEL 1
#define MODEM_POWERON_PULSE_MS 100

#define SerialAT Serial1

static String sendAt(const char* cmd, uint32_t timeoutMs)
{
    while (SerialAT.available()) SerialAT.read();
    Serial.printf(">> %s\n", cmd);
    SerialAT.println(cmd);
    String buf;
    const uint32_t t0 = millis();
    while (millis() - t0 < timeoutMs) {
        while (SerialAT.available()) {
            buf += (char)SerialAT.read();
        }
        if (buf.indexOf("\nOK") >= 0 || buf.indexOf("\nERROR") >= 0 ||
            buf.indexOf("READY!") >= 0) {
            delay(80);
            while (SerialAT.available()) {
                buf += (char)SerialAT.read();
            }
            break;
        }
        delay(10);
    }
    Serial.print(buf);
    return buf;
}

static bool waitAtOk(uint32_t timeoutMs)
{
    const uint32_t t0 = millis();
    while (millis() - t0 < timeoutMs) {
        SerialAT.println("AT");
        delay(300);
        String buf;
        while (SerialAT.available()) buf += (char)SerialAT.read();
        if (buf.indexOf("OK") >= 0) return true;
        Serial.print(".");
    }
    return false;
}

void setup()
{
    Serial.begin(115200);
    delay(400);
    Serial.println();
    Serial.println("=== LilyGO GPS_BuiltIn test (T-SIM7670G-S3) ===");
    Serial.println("Только GNSS. Нет HTTP, нет датчиков.");

    pinMode(MODEM_RESET_PIN, OUTPUT);
    digitalWrite(MODEM_RESET_PIN, !MODEM_RESET_LEVEL);
    delay(100);
    digitalWrite(MODEM_RESET_PIN, MODEM_RESET_LEVEL);
    delay(2600);
    digitalWrite(MODEM_RESET_PIN, !MODEM_RESET_LEVEL);

    pinMode(MODEM_DTR_PIN, OUTPUT);
    digitalWrite(MODEM_DTR_PIN, LOW);

    pinMode(BOARD_PWRKEY_PIN, OUTPUT);
    digitalWrite(BOARD_PWRKEY_PIN, LOW);
    delay(100);
    digitalWrite(BOARD_PWRKEY_PIN, HIGH);
    delay(MODEM_POWERON_PULSE_MS);
    digitalWrite(BOARD_PWRKEY_PIN, LOW);

    SerialAT.begin(115200, SERIAL_8N1, MODEM_RX_PIN, MODEM_TX_PIN);
    Serial.println("Start modem...");
    delay(3000);

    if (!waitAtOk(20000)) {
        Serial.println("\nНет ответа AT. Проверьте ESP-USB и COM-порт.");
        return;
    }
    Serial.println("\nAT OK");

    sendAt("ATE0", 2000);
    sendAt("AT+CGMM", 3000);
    sendAt("AT+SIMCOMATI", 8000);

    // Как TinyGSM enableGPS(GPIO4, 1) в GPS_BuiltIn:
    sendAt("AT+CGDRT=4,1", 2000);
    sendAt("AT+CGSETV=4,1", 2000);
    Serial.println("Enabling GPS/GNSS (ждём +CGNSSPWR: READY! до 30 с)...");
    String pwr = sendAt("AT+CGNSSPWR=1", 30000);
    if (pwr.indexOf("READY") >= 0 || pwr.indexOf("OK") >= 0) {
        Serial.println("GPS Enabled (OK или READY)");
    } else {
        Serial.println("CGNSSPWR не ответил READY/OK — продолжаем опрос всё равно");
    }

    sendAt("AT+CGNSSMODE=3", 3000);
    sendAt("AT+CGNSSIPR=115200", 3000);
    sendAt("AT+CGNSSPROD", 3000);
    sendAt("AT+CGNSSPWR?", 2000);

    Serial.println();
    Serial.println("Дальше раз в 15 с: AT+CGNSSINFO и AT+CGPSINFO");
    Serial.println("Антенна GNSS плашмя, открытое небо. Можно слать AT вручную.");
    Serial.println();
}

void loop()
{
    static uint32_t last = 0;
    if (millis() - last >= 15000UL) {
        last = millis();
        Serial.println("Requesting GPS/GNSS location");
        sendAt("AT+CGNSSINFO", 4000);
        sendAt("AT+CGPSINFO", 4000);
    }

    while (SerialAT.available()) Serial.write(SerialAT.read());
    while (Serial.available()) SerialAT.write(Serial.read());
}
