#ifndef OFFLINE_QUEUE_H
#define OFFLINE_QUEUE_H

#include <Arduino.h>
#include <FS.h>
#include <LittleFS.h>
#include <Preferences.h>
#include "config.h"

// Очередь JSON-пакетов телеметрии во flash (LittleFS).
// Нет сети → enqueue. Сеть появилась → flush + удаление файлов.

static Preferences g_qPrefs;
static bool g_fsReady = false;
static uint32_t g_qNextId = 1;

inline String _qBaseName(const String& name)
{
    int slash = name.lastIndexOf('/');
    return slash >= 0 ? name.substring(slash + 1) : name;
}

inline String _qPath(const String& name)
{
    return String("/q/") + _qBaseName(name);
}

inline bool initOfflineQueue()
{
    g_fsReady = LittleFS.begin(true);
    if (!g_fsReady) {
        Serial.println("LittleFS: mount FAIL — офлайн-очередь недоступна");
        return false;
    }
    if (!LittleFS.exists("/q")) LittleFS.mkdir("/q");

    g_qPrefs.begin("hw_queue", false);
    g_qNextId = g_qPrefs.getUInt("next_id", 1);
    if (g_qNextId == 0) g_qNextId = 1;

    Serial.printf("LittleFS OK  used=%u / total=%u  queue_next=%lu\n",
                  (unsigned)LittleFS.usedBytes(),
                  (unsigned)LittleFS.totalBytes(),
                  (unsigned long)g_qNextId);
    return true;
}

inline uint16_t offlineQueueCount()
{
    if (!g_fsReady) return 0;
    uint16_t n = 0;
    File root = LittleFS.open("/q");
    if (!root || !root.isDirectory()) return 0;
    File f = root.openNextFile();
    while (f) {
        if (!f.isDirectory()) n++;
        f.close();
        f = root.openNextFile();
    }
    root.close();
    return n;
}

inline void offlineQueueListSorted(String* names, uint16_t maxN, uint16_t* outN)
{
    *outN = 0;
    if (!g_fsReady) return;
    File root = LittleFS.open("/q");
    if (!root || !root.isDirectory()) return;
    File f = root.openNextFile();
    while (f && *outN < maxN) {
        if (!f.isDirectory()) names[(*outN)++] = _qBaseName(f.name());
        f.close();
        f = root.openNextFile();
    }
    root.close();
    for (uint16_t i = 0; i + 1 < *outN; i++) {
        for (uint16_t j = 0; j + 1 < *outN - i; j++) {
            if (names[j] > names[j + 1]) {
                String tmp = names[j];
                names[j] = names[j + 1];
                names[j + 1] = tmp;
            }
        }
    }
}

inline void offlineQueueDropOldest(uint16_t keepMax)
{
    String names[OFFLINE_QUEUE_MAX_FILES + 4];
    uint16_t n = 0;
    offlineQueueListSorted(names, OFFLINE_QUEUE_MAX_FILES + 4, &n);
    while (n > keepMax) {
        String path = _qPath(names[0]);
        LittleFS.remove(path);
        Serial.printf("offline: drop oldest %s\n", path.c_str());
        for (uint16_t i = 0; i + 1 < n; i++) names[i] = names[i + 1];
        n--;
    }
}

inline bool enqueueOfflineTelemetry(const String& body)
{
    if (!g_fsReady || body.length() == 0) return false;

    if (offlineQueueCount() >= OFFLINE_QUEUE_MAX_FILES) {
        offlineQueueDropOldest(OFFLINE_QUEUE_MAX_FILES - 1);
    }

    char path[32];
    const uint32_t id = g_qNextId;
    // Сначала NVS — при reboot mid-write не перезапишем тот же id.
    g_qPrefs.putUInt("next_id", id + 1);
    g_qNextId = id + 1;

    snprintf(path, sizeof(path), "/q/%08lu.json", (unsigned long)id);

    File f = LittleFS.open(path, FILE_WRITE);
    if (!f) {
        Serial.println("offline: write FAIL");
        return false;
    }
    const size_t wrote = f.print(body);
    f.close();
    if (wrote != body.length()) {
        LittleFS.remove(path);
        Serial.println("offline: incomplete write");
        return false;
    }

    Serial.printf("offline: saved %s (%u B), queue=%u\n",
                  path, (unsigned)wrote, (unsigned)offlineQueueCount());
    return true;
}

inline bool clearOfflineQueue()
{
    if (!g_fsReady) return false;
    String names[OFFLINE_QUEUE_MAX_FILES + 4];
    uint16_t n = 0;
    offlineQueueListSorted(names, OFFLINE_QUEUE_MAX_FILES + 4, &n);
    for (uint16_t i = 0; i < n; i++) LittleFS.remove(_qPath(names[i]));
    Serial.println("offline: queue cleared");
    return true;
}

inline void printOfflineQueueStatus()
{
    if (!g_fsReady) {
        Serial.println("offline: FS not ready");
        return;
    }
    Serial.printf("offline: files=%u  FS used=%u/%u\n",
                  (unsigned)offlineQueueCount(),
                  (unsigned)LittleFS.usedBytes(),
                  (unsigned)LittleFS.totalBytes());
}

/// Подставить актуальные machine_id / device_id в старый JSON
/// (очередь могла накопиться с опечаткой MACHINE uuid DEVICE …).
inline String rewriteQueuedTelemetryIds(
    const String& body,
    const char* machineId,
    const char* deviceId)
{
    if (machineId == nullptr || deviceId == nullptr) return body;
    if (machineId[0] == '\0' || deviceId[0] == '\0') return body;

    auto replaceField = [](String s, const char* key, const char* value) -> String {
        const String needle = String("\"") + key + "\":\"";
        const int start = s.indexOf(needle);
        if (start < 0) return s;
        const int valStart = start + needle.length();
        const int valEnd = s.indexOf('"', valStart);
        if (valEnd < 0) return s;
        return s.substring(0, valStart) + value + s.substring(valEnd);
    };

    String out = replaceField(body, "machine_id", machineId);
    out = replaceField(out, "device_id", deviceId);
    return out;
}

template <typename SendFn>
inline uint16_t flushOfflineQueue(SendFn sendFn, uint16_t batchLimit = OFFLINE_FLUSH_BATCH)
{
    if (!g_fsReady) return 0;

    String names[OFFLINE_QUEUE_MAX_FILES];
    uint16_t n = 0;
    offlineQueueListSorted(names, OFFLINE_QUEUE_MAX_FILES, &n);
    if (n == 0) return 0;

    uint16_t sent = 0;
    const uint16_t limit = n < batchLimit ? n : batchLimit;
    for (uint16_t i = 0; i < limit; i++) {
        String path = _qPath(names[i]);
        File rf = LittleFS.open(path, FILE_READ);
        if (!rf) continue;
        String body = rf.readString();
        rf.close();
        if (body.length() == 0) {
            LittleFS.remove(path);
            continue;
        }
        // Обрывки без MACHINE/KEY (~27 B) — не слать на API.
        if (body.length() < 48 || body.indexOf("\"d\"") < 0) {
            Serial.printf("offline: drop junk %s (%u B)\n",
                          path.c_str(), (unsigned)body.length());
            LittleFS.remove(path);
            continue;
        }

        Serial.printf("offline: flush %s (%u B)...\n",
                      path.c_str(), (unsigned)body.length());
        if (!sendFn(body)) {
            Serial.println("offline: flush stop (send failed)");
            break;
        }
        LittleFS.remove(path);
        sent++;
    }
    if (sent > 0) {
        Serial.printf("offline: flushed %u, left=%u\n",
                      (unsigned)sent, (unsigned)offlineQueueCount());
    }
    return sent;
}

#endif
