#ifndef OFFLINE_QUEUE_H
#define OFFLINE_QUEUE_H

#include <Arduino.h>
#include <LittleFS.h>
#include <Preferences.h>
#include "config.h"

// Очередь JSON-пакетов телеметрии во flash (LittleFS).
// Нет сети → enqueue. Сеть появилась → flush + удаление файлов.

static Preferences g_qPrefs;
static bool g_fsReady = false;
static uint32_t g_qNextId = 1;

inline bool initOfflineQueue()
{
    g_fsReady = LittleFS.begin(true);  // formatIfFailed
    if (!g_fsReady) {
        Serial.println("LittleFS: mount FAIL — офлайн-очередь недоступна");
        return false;
    }

    if (!LittleFS.exists("/q")) {
        LittleFS.mkdir("/q");
    }

    g_qPrefs.begin("hw_queue", false);
    g_qNextId = g_qPrefs.getUInt("next_id", 1);
    if (g_qNextId == 0) g_qNextId = 1;

    size_t used = LittleFS.usedBytes();
    size_t total = LittleFS.totalBytes();
    Serial.printf("LittleFS OK  used=%u / total=%u  queue_next=%lu\n",
                  (unsigned)used, (unsigned)total, (unsigned long)g_qNextId);
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
        f = root.openNextFile();
    }
    return n;
}

inline void offlineQueueDropOldest(uint16_t keepMax)
{
    if (!g_fsReady) return;
    // Собираем имена, сортируем лексикографически (нулевая паддинг → по возрасту).
    String names[OFFLINE_QUEUE_MAX_FILES + 8];
    uint16_t n = 0;
    File root = LittleFS.open("/q");
    if (!root || !root.isDirectory()) return;
    File f = root.openNextFile();
    while (f && n < (uint16_t)(sizeof(names) / sizeof(names[0]))) {
        if (!f.isDirectory()) {
            names[n++] = String(f.name());
        }
        f = root.openNextFile();
    }
    // bubble sort ascending
    for (uint16_t i = 0; i + 1 < n; i++) {
        for (uint16_t j = 0; j + 1 < n - i; j++) {
            if (names[j] > names[j + 1]) {
                String tmp = names[j];
                names[j] = names[j + 1];
                names[j + 1] = tmp;
            }
        }
    }
    while (n > keepMax) {
        String path = names[0];
        if (!path.startsWith("/")) path = String("/q/") + path;
        else if (!path.startsWith("/q/")) path = String("/q/") + path.substring(path.lastIndexOf('/') + 1);
        // LittleFS.openNextFile().name() may be "0001.json" or "/q/0001.json"
        if (!path.startsWith("/q/")) {
            path = String("/q/") + names[0];
            if (names[0].startsWith("/")) path = names[0];
        }
        // normalize
        String base = names[0];
        int slash = base.lastIndexOf('/');
        if (slash >= 0) base = base.substring(slash + 1);
        path = String("/q/") + base;

        LittleFS.remove(path);
        Serial.printf("offline: drop oldest %s\n", path.c_str());
        for (uint16_t i = 0; i + 1 < n; i++) names[i] = names[i + 1];
        n--;
    }
}

inline bool enqueueOfflineTelemetry(const String& body)
{
    if (!g_fsReady || body.length() == 0) return false;

    uint16_t count = offlineQueueCount();
    if (count >= OFFLINE_QUEUE_MAX_FILES) {
        offlineQueueDropOldest(OFFLINE_QUEUE_MAX_FILES - 1);
    }

    char path[32];
    snprintf(path, sizeof(path), "/q/%08lu.json", (unsigned long)g_qNextId);

    File f = LittleFS.open(path, "w");
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

    g_qNextId++;
    g_qPrefs.putUInt("next_id", g_qNextId);
    Serial.printf("offline: saved %s (%u B), queue=%u\n",
                  path, (unsigned)wrote, (unsigned)offlineQueueCount());
    return true;
}

inline bool clearOfflineQueue()
{
    if (!g_fsReady) return false;
    File root = LittleFS.open("/q");
    if (!root || !root.isDirectory()) return false;
    File f = root.openNextFile();
    while (f) {
        if (!f.isDirectory()) {
            String base = f.name();
            int slash = base.lastIndexOf('/');
            if (slash >= 0) base = base.substring(slash + 1);
            String path = String("/q/") + base;
            LittleFS.remove(path);
        }
        f = root.openNextFile();
    }
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

/// Отправляет до batchLimit самых старых пакетов. sendFn — доставка без записи в очередь.
template <typename SendFn>
inline uint16_t flushOfflineQueue(SendFn sendFn, uint16_t batchLimit = OFFLINE_FLUSH_BATCH)
{
    if (!g_fsReady) return 0;

    String names[OFFLINE_QUEUE_MAX_FILES];
    uint16_t n = 0;
    File root = LittleFS.open("/q");
    if (!root || !root.isDirectory()) return 0;
    File f = root.openNextFile();
    while (f && n < OFFLINE_QUEUE_MAX_FILES) {
        if (!f.isDirectory()) names[n++] = String(f.name());
        f = root.openNextFile();
    }
    for (uint16_t i = 0; i + 1 < n; i++) {
        for (uint16_t j = 0; j + 1 < n - i; j++) {
            if (names[j] > names[j + 1]) {
                String tmp = names[j];
                names[j] = names[j + 1];
                names[j + 1] = tmp;
            }
        }
    }

    uint16_t sent = 0;
    const uint16_t limit = n < batchLimit ? n : batchLimit;
    for (uint16_t i = 0; i < limit; i++) {
        String base = names[i];
        int slash = base.lastIndexOf('/');
        if (slash >= 0) base = base.substring(slash + 1);
        String path = String("/q/") + base;

        File rf = LittleFS.open(path, "r");
        if (!rf) continue;
        String body = rf.readString();
        rf.close();
        if (body.length() == 0) {
            LittleFS.remove(path);
            continue;
        }

        Serial.printf("offline: flush %s (%u B)...\n", path.c_str(), (unsigned)body.length());
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
