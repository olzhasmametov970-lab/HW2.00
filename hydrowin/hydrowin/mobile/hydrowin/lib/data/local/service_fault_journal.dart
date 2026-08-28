import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hydrowin/core/ble/telemetry_packet.dart';
import 'package:hydrowin/core/constants/app_constants.dart';
import 'package:hydrowin/data/local/app_database.dart';
import 'package:hydrowin/domain/models/live_sensor_reading.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ServiceFaultEntry {
  const ServiceFaultEntry({
    required this.id,
    required this.channelIndex,
    required this.sensorName,
    required this.title,
    required this.detail,
    required this.status,
    required this.loopFault,
    required this.recordedAt,
    this.currentMa,
    this.engineeringValue,
    this.deviceLabel,
  });

  final int id;
  final int channelIndex;
  final String sensorName;
  final String title;
  final String detail;
  final String status;
  final String loopFault;
  final DateTime recordedAt;
  final double? currentMa;
  final double? engineeringValue;
  final String? deviceLabel;

  Map<String, Object?> toJson() => {
        'id': id,
        'channel_index': channelIndex,
        'sensor_name': sensorName,
        'title': title,
        'detail': detail,
        'status': status,
        'loop_fault': loopFault,
        'current_ma': currentMa,
        'engineering_value': engineeringValue,
        'device_label': deviceLabel,
        'recorded_at': recordedAt.millisecondsSinceEpoch,
      };

  factory ServiceFaultEntry.fromJson(Map<String, Object?> json) {
    return ServiceFaultEntry(
      id: (json['id'] as num?)?.toInt() ?? 0,
      channelIndex: (json['channel_index'] as num?)?.toInt() ?? 0,
      sensorName: json['sensor_name'] as String? ?? '',
      title: json['title'] as String? ?? '',
      detail: json['detail'] as String? ?? '',
      status: json['status'] as String? ?? '',
      loopFault: json['loop_fault'] as String? ?? '',
      currentMa: (json['current_ma'] as num?)?.toDouble(),
      engineeringValue: (json['engineering_value'] as num?)?.toDouble(),
      deviceLabel: json['device_label'] as String?,
      recordedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['recorded_at'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}

/// Локальный журнал аварий петли 4–20 мА (гарантия / сервис).
/// Desktop/mobile: SQLite. Web: SharedPreferences (история в браузере).
class ServiceFaultJournal {
  ServiceFaultJournal._(this._db, this._memory, this._prefs);

  static const _webKey = 'service_faults_web_v1';
  static const _maxWebEntries = 500;

  final AppDatabase? _db;
  final List<ServiceFaultEntry>? _memory;
  final SharedPreferences? _prefs;
  final Map<int, String> _lastKey = {};
  int _nextWebId = 1;

  static Future<ServiceFaultJournal> create() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final journal = ServiceFaultJournal._(null, [], prefs);
      await journal._loadWeb();
      return journal;
    }
    final db = await AppDatabase.open();
    return ServiceFaultJournal._(db, null, null);
  }

  Future<void> _loadWeb() async {
    final raw = _prefs?.getString(_webKey);
    if (raw == null || raw.isEmpty || _memory == null) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _memory.clear();
      for (final item in list) {
        if (item is! Map) continue;
        final entry = ServiceFaultEntry.fromJson(
          Map<String, Object?>.from(item),
        );
        _memory.add(entry);
        if (entry.id >= _nextWebId) _nextWebId = entry.id + 1;
      }
    } catch (_) {
      // битый кэш — начинаем с пустого
    }
  }

  Future<void> _saveWeb() async {
    final prefs = _prefs;
    final mem = _memory;
    if (prefs == null || mem == null) return;
    final encoded = jsonEncode(mem.map((e) => e.toJson()).toList());
    await prefs.setString(_webKey, encoded);
  }

  Future<void> maybeRecord(
    LiveSensorReading reading, {
    String? deviceLabel,
  }) async {
    if (!reading.isAccident) {
      _lastKey.remove(reading.config.channelIndex);
      return;
    }
    final key =
        '${reading.status.name}_${reading.loopFault.name}_${reading.formattedServiceCurrent}';
    if (_lastKey[reading.config.channelIndex] == key) return;
    _lastKey[reading.config.channelIndex] = key;

    final entry = ServiceFaultEntry(
      id: 0,
      channelIndex: reading.config.channelIndex,
      sensorName: reading.config.name,
      title: reading.alertTitle,
      detail: reading.alertDetailBody,
      status: reading.status.name,
      loopFault: reading.loopFault.name,
      recordedAt: reading.updatedAt,
      currentMa: reading.currentMa,
      engineeringValue:
          reading.loopFault == LoopFault.none ? reading.value : null,
      deviceLabel: deviceLabel,
    );

    if (_memory != null) {
      _memory.insert(
        0,
        ServiceFaultEntry(
          id: _nextWebId++,
          channelIndex: entry.channelIndex,
          sensorName: entry.sensorName,
          title: entry.title,
          detail: entry.detail,
          status: entry.status,
          loopFault: entry.loopFault,
          recordedAt: entry.recordedAt,
          currentMa: entry.currentMa,
          engineeringValue: entry.engineeringValue,
          deviceLabel: entry.deviceLabel,
        ),
      );
      if (_memory.length > _maxWebEntries) {
        _memory.removeRange(_maxWebEntries, _memory.length);
      }
      await _saveWeb();
      return;
    }

    await _db!.db.insert('service_faults', {
      'channel_index': entry.channelIndex,
      'sensor_name': entry.sensorName,
      'title': entry.title,
      'detail': entry.detail,
      'status': entry.status,
      'loop_fault': entry.loopFault,
      'current_ma': entry.currentMa,
      'engineering_value': entry.engineeringValue,
      'device_label': entry.deviceLabel,
      'recorded_at': entry.recordedAt.millisecondsSinceEpoch,
    });
  }

  Future<List<ServiceFaultEntry>> list({
    int limit = 300,
    String? query,
    String? loopFault,
  }) async {
    final q = query?.trim().toLowerCase() ?? '';
    List<ServiceFaultEntry> items;
    if (_memory != null) {
      items = List<ServiceFaultEntry>.from(_memory);
    } else {
      final rows = await _db!.db.query(
        'service_faults',
        orderBy: 'recorded_at DESC',
        limit: limit * 3,
      );
      items = rows.map(_fromRow).toList();
    }

    if (loopFault != null && loopFault.isNotEmpty && loopFault != 'all') {
      items = items.where((e) => e.loopFault == loopFault).toList();
    }
    if (q.isNotEmpty) {
      items = items.where((e) {
        final hay = [
          e.deviceLabel ?? '',
          e.sensorName,
          e.title,
          e.detail,
          'CH${e.channelIndex}',
          e.channelIndex.toString(),
        ].join(' ').toLowerCase();
        return hay.contains(q);
      }).toList();
    }
    if (items.length > limit) {
      items = items.take(limit).toList();
    }
    return items;
  }

  Future<int> purgeOlderThanRetention() async {
    final cutoff = DateTime.now().subtract(
      Duration(days: AppConstants.localHistoryDays),
    );
    if (_memory != null) {
      final before = _memory.length;
      _memory.removeWhere((e) => e.recordedAt.isBefore(cutoff));
      if (before != _memory.length) await _saveWeb();
      return before - _memory.length;
    }
    return _db!.db.delete(
      'service_faults',
      where: 'recorded_at < ?',
      whereArgs: [cutoff.millisecondsSinceEpoch],
    );
  }

  ServiceFaultEntry _fromRow(Map<String, Object?> row) {
    return ServiceFaultEntry(
      id: row['id']! as int,
      channelIndex: row['channel_index']! as int,
      sensorName: row['sensor_name']! as String,
      title: row['title']! as String,
      detail: row['detail']! as String,
      status: row['status']! as String,
      loopFault: row['loop_fault']! as String,
      currentMa: (row['current_ma'] as num?)?.toDouble(),
      engineeringValue: (row['engineering_value'] as num?)?.toDouble(),
      deviceLabel: row['device_label'] as String?,
      recordedAt: DateTime.fromMillisecondsSinceEpoch(
        row['recorded_at']! as int,
      ),
    );
  }
}
