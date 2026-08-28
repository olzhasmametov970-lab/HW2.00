import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hydrowin/core/constants/app_constants.dart';
import 'package:hydrowin/data/local/app_database.dart';
import 'package:hydrowin/domain/models/live_sensor_reading.dart';
import 'package:hydrowin/domain/models/reading_point.dart';
import 'package:hydrowin/domain/models/sensor_status_level.dart';
import 'package:hydrowin/domain/reading_stats_calculator.dart';

class ReadingsRepository {
  ReadingsRepository._(this._db, this._memory);

  final AppDatabase? _db;
  final List<_MemoryRow>? _memory;

  static Future<ReadingsRepository> create() async {
    if (kIsWeb) {
      return ReadingsRepository._(null, []);
    }
    final db = await AppDatabase.open();
    return ReadingsRepository._(db, null);
  }

  Future<void> insertFromSession(Map<int, LiveSensorReading> readings) async {
    if (readings.isEmpty) return;

    if (_memory != null) {
      for (final r in readings.values) {
        _memory.add(
          _MemoryRow(
            channelIndex: r.config.channelIndex,
            value: r.value,
            status: r.status,
            recordedAt: r.updatedAt,
          ),
        );
      }
      _trimMemory();
      return;
    }

    final batch = _db!.db.batch();
    for (final r in readings.values) {
      batch.insert('readings', {
        'channel_index': r.config.channelIndex,
        'value': r.value,
        'status': r.status.name,
        'recorded_at': r.updatedAt.millisecondsSinceEpoch,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<ReadingPoint>> lastMinutes({
    required int channelIndex,
    required int minutes,
  }) async {
    final since = DateTime.now().subtract(Duration(minutes: minutes));

    if (_memory != null) {
      return _memory
          .where(
            (r) =>
                r.channelIndex == channelIndex && !r.recordedAt.isBefore(since),
          )
          .map((r) => r.toPoint())
          .toList()
        ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    }

    final sinceMs = since.millisecondsSinceEpoch;
    final rows = await _db!.db.query(
      'readings',
      where: 'channel_index = ? AND recorded_at >= ?',
      whereArgs: [channelIndex, sinceMs],
      orderBy: 'recorded_at ASC',
    );
    return rows.map(_rowToPoint).toList();
  }

  Future<ReadingStats> statsForPeriod({
    required int channelIndex,
    required int minutes,
  }) async {
    final points = await lastMinutes(
      channelIndex: channelIndex,
      minutes: minutes,
    );
    return ReadingStatsCalculator.compute(points);
  }

  Future<int> purgeOlderThanRetention() async {
    final cutoff = DateTime.now().subtract(
      Duration(days: AppConstants.localHistoryDays),
    );

    if (_memory != null) {
      final before = _memory.length;
      _memory.removeWhere((r) => r.recordedAt.isBefore(cutoff));
      return before - _memory.length;
    }

    return _db!.db.delete(
      'readings',
      where: 'recorded_at < ?',
      whereArgs: [cutoff.millisecondsSinceEpoch],
    );
  }

  void _trimMemory() {
    final cutoff = DateTime.now().subtract(
      Duration(days: AppConstants.localHistoryDays),
    );
    _memory!.removeWhere((r) => r.recordedAt.isBefore(cutoff));
  }

  ReadingPoint _rowToPoint(Map<String, Object?> row) {
    return ReadingPoint(
      channelIndex: row['channel_index']! as int,
      value: row['value']! as double,
      status: SensorStatusLevel.values.byName(row['status']! as String),
      recordedAt: DateTime.fromMillisecondsSinceEpoch(
        row['recorded_at']! as int,
      ),
    );
  }
}

class _MemoryRow {
  _MemoryRow({
    required this.channelIndex,
    required this.value,
    required this.status,
    required this.recordedAt,
  });

  final int channelIndex;
  final double value;
  final SensorStatusLevel status;
  final DateTime recordedAt;

  ReadingPoint toPoint() => ReadingPoint(
    channelIndex: channelIndex,
    value: value,
    status: status,
    recordedAt: recordedAt,
  );
}
