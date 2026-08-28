import 'package:flutter_test/flutter_test.dart';
import 'package:hydrowin/core/theme/app_theme.dart';
import 'package:hydrowin/domain/models/reading_point.dart';
import 'package:hydrowin/domain/models/sensor_config.dart';
import 'package:hydrowin/domain/models/sensor_type.dart';
import 'package:hydrowin/domain/reading_stats_calculator.dart';

void main() {
  test('computes avg min max and norm percent', () {
    final now = DateTime.now();
    final points = [
      ReadingPoint(
        channelIndex: 0,
        value: 100,
        status: SensorStatusLevel.ok,
        recordedAt: now,
      ),
      ReadingPoint(
        channelIndex: 0,
        value: 120,
        status: SensorStatusLevel.warning,
        recordedAt: now.add(const Duration(seconds: 1)),
      ),
      ReadingPoint(
        channelIndex: 0,
        value: 140,
        status: SensorStatusLevel.ok,
        recordedAt: now.add(const Duration(seconds: 2)),
      ),
    ];

    final stats = ReadingStatsCalculator.compute(points);
    expect(stats.avg, closeTo(120, 0.01));
    expect(stats.min, 100);
    expect(stats.max, 140);
    expect(stats.pctInNorm, closeTo(200 / 3, 1)); // 2 of 3 ok
    expect(stats.pctWarning, closeTo(100 / 3, 1)); // 1 of 3 warning
    expect(stats.pctCritical, 0);
    expect(stats.warningCount, 1);
    expect(stats.count, 3);
    // Все три доли должны в сумме давать 100%, как в макете статистики.
    expect(
      stats.pctInNorm + stats.pctWarning + stats.pctCritical,
      closeTo(100, 0.01),
    );
  });

  test('computes critical percent and sums to 100', () {
    final now = DateTime.now();
    final points = [
      ReadingPoint(
        channelIndex: 0,
        value: 300,
        status: SensorStatusLevel.critical,
        recordedAt: now,
      ),
      ReadingPoint(
        channelIndex: 0,
        value: 200,
        status: SensorStatusLevel.ok,
        recordedAt: now.add(const Duration(seconds: 1)),
      ),
      ReadingPoint(
        channelIndex: 0,
        value: 250,
        status: SensorStatusLevel.ok,
        recordedAt: now.add(const Duration(seconds: 2)),
      ),
      ReadingPoint(
        channelIndex: 0,
        value: 260,
        status: SensorStatusLevel.ok,
        recordedAt: now.add(const Duration(seconds: 3)),
      ),
    ];

    final stats = ReadingStatsCalculator.compute(points);
    expect(stats.pctCritical, closeTo(25, 0.01)); // 1 of 4 critical
    expect(stats.criticalCount, 1);
    expect(
      stats.pctInNorm + stats.pctWarning + stats.pctCritical,
      closeTo(100, 0.01),
    );
  });

  test('re-evaluates status from config instead of stored point status', () {
    final config = SensorConfig(
      channelIndex: 0,
      name: 'Давление',
      type: SensorType.pressure,
      scaleMin: 0,
      scaleMax: 380,
      normMin: 100,
      normMax: 150,
      warnHigh: 200,
      criticalHigh: 250,
      criticalLow: 90,
    );
    final now = DateTime.now();
    final points = [
      ReadingPoint(
        channelIndex: 0,
        value: 120,
        status: SensorStatusLevel.ok,
        recordedAt: now,
      ),
      ReadingPoint(
        channelIndex: 0,
        value: 180,
        status: SensorStatusLevel.ok,
        recordedAt: now.add(const Duration(seconds: 1)),
      ),
      ReadingPoint(
        channelIndex: 0,
        value: 260,
        status: SensorStatusLevel.ok,
        recordedAt: now.add(const Duration(seconds: 2)),
      ),
    ];

    final stats = ReadingStatsCalculator.compute(points, config: config);
    expect(stats.pctInNorm, closeTo(100 / 3, 1));
    expect(stats.pctWarning, closeTo(100 / 3, 1));
    expect(stats.pctCritical, closeTo(100 / 3, 1));
  });

  test('computes BLOCK online time and pump runtime/starts for pressure', () {
    final config = SensorConfig(
      channelIndex: 0,
      name: 'Давление',
      type: SensorType.pressure,
      scaleMin: 0,
      scaleMax: 300,
      normMin: 100,
      normMax: 250,
      criticalHigh: 300,
    );
    final now = DateTime.now();
    // Насос: выкл (0) -> вкл (150) на 2 мин -> выкл (0) на 1 мин -> вкл (160) на 2 мин.
    final points = [
      ReadingPoint(
        channelIndex: 0,
        value: 0,
        status: SensorStatusLevel.ok,
        recordedAt: now,
      ),
      ReadingPoint(
        channelIndex: 0,
        value: 150,
        status: SensorStatusLevel.ok,
        recordedAt: now.add(const Duration(minutes: 1)),
      ),
      ReadingPoint(
        channelIndex: 0,
        value: 150,
        status: SensorStatusLevel.ok,
        recordedAt: now.add(const Duration(minutes: 3)),
      ),
      ReadingPoint(
        channelIndex: 0,
        value: 0,
        status: SensorStatusLevel.ok,
        recordedAt: now.add(const Duration(minutes: 4)),
      ),
      ReadingPoint(
        channelIndex: 0,
        value: 160,
        status: SensorStatusLevel.ok,
        recordedAt: now.add(const Duration(minutes: 5)),
      ),
      ReadingPoint(
        channelIndex: 0,
        value: 160,
        status: SensorStatusLevel.ok,
        recordedAt: now.add(const Duration(minutes: 7)),
      ),
    ];

    final stats = ReadingStatsCalculator.compute(points, config: config);
    expect(stats.BLOCKOnlineMinutes, closeTo(7, 0.01));
    expect(stats.pumpStarts, 2);
    // Промежуток, в котором насос включился/выключился, целиком считается
    // «включён» — так что 1+2 (первый запуск) + 1+2 (второй запуск) = 6 мин.
    expect(stats.pumpRunMinutes, closeTo(6, 0.01));
  });

  test('pump fields are null for non-pressure sensors', () {
    final config = SensorConfig(
      channelIndex: 1,
      name: 'Температура',
      type: SensorType.temperature,
      scaleMin: -50,
      scaleMax: 80,
      normMax: 50,
      criticalHigh: 55,
    );
    final now = DateTime.now();
    final points = [
      ReadingPoint(
        channelIndex: 1,
        value: 40,
        status: SensorStatusLevel.ok,
        recordedAt: now,
      ),
      ReadingPoint(
        channelIndex: 1,
        value: 42,
        status: SensorStatusLevel.ok,
        recordedAt: now.add(const Duration(minutes: 1)),
      ),
    ];

    final stats = ReadingStatsCalculator.compute(points, config: config);
    expect(stats.pumpStarts, isNull);
    expect(stats.pumpRunMinutes, isNull);
    expect(stats.BLOCKOnlineMinutes, closeTo(1, 0.01));
  });
}
