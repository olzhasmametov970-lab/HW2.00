import 'package:hydrowin/domain/models/reading_point.dart';
import 'package:hydrowin/domain/models/sensor_config.dart';
import 'package:hydrowin/domain/models/sensor_status_level.dart';
import 'package:hydrowin/domain/models/sensor_type.dart';
import 'package:hydrowin/domain/sensor_threshold_evaluator.dart';

abstract final class ReadingStatsCalculator {
  /// Промежутки между соседними точками длиннее этого считаются разрывом
  /// связи с блоком BLOCK (не засчитываются во время работы/насоса).
  static const _maxGapMinutes = 10.0;

  /// Насос считается «включён», когда давление превышает минимум шкалы
  /// на эту долю диапазона — простая эвристика без отдельного сигнала
  /// «насос вкл/выкл» с блока.
  static const _pumpOnFraction = 0.05;

  static ReadingStats compute(
    List<ReadingPoint> points, {
    SensorConfig? config,
  }) {
    if (points.isEmpty) return ReadingStats.empty;

    var sum = 0.0;
    var min = points.first.value;
    var max = points.first.value;
    var okCount = 0;
    var warnCount = 0;
    var critCount = 0;

    for (final p in points) {
      sum += p.value;
      if (p.value < min) min = p.value;
      if (p.value > max) max = p.value;
      final status = config != null
          ? SensorThresholdEvaluator.evaluate(config, p.value)
          : p.status;
      switch (status) {
        case SensorStatusLevel.ok:
          okCount++;
        case SensorStatusLevel.warning:
          warnCount++;
        case SensorStatusLevel.critical:
          critCount++;
        case SensorStatusLevel.offline:
          break;
      }
    }

    double? pumpRunMinutes;
    int? pumpStarts;
    if (config != null && config.type == SensorType.pressure) {
      final threshold =
          config.scaleMin +
          (config.scaleMax - config.scaleMin) * _pumpOnFraction;
      final activity = _pumpActivity(points, threshold);
      pumpRunMinutes = activity.runMinutes;
      pumpStarts = activity.starts;
    }

    return ReadingStats(
      avg: sum / points.length,
      min: min,
      max: max,
      pctInNorm: okCount / points.length * 100,
      pctWarning: warnCount / points.length * 100,
      pctCritical: critCount / points.length * 100,
      warningCount: warnCount,
      criticalCount: critCount,
      count: points.length,
      BLOCKOnlineMinutes: _onlineMinutes(points),
      pumpRunMinutes: pumpRunMinutes,
      pumpStarts: pumpStarts,
    );
  }

  static double _onlineMinutes(List<ReadingPoint> points) {
    if (points.length < 2) return 0;
    var totalMs = 0;
    for (var i = 1; i < points.length; i++) {
      final gapMs = points[i].recordedAt
          .difference(points[i - 1].recordedAt)
          .inMilliseconds;
      if (gapMs / 60000 <= _maxGapMinutes) {
        totalMs += gapMs;
      }
    }
    return totalMs / 60000;
  }

  static _PumpActivity _pumpActivity(
    List<ReadingPoint> points,
    double onThreshold,
  ) {
    var starts = 0;
    var runMs = 0;
    var wasOn = points.first.value > onThreshold;

    for (var i = 1; i < points.length; i++) {
      final isOn = points[i].value > onThreshold;
      final gapMs = points[i].recordedAt
          .difference(points[i - 1].recordedAt)
          .inMilliseconds;
      if (isOn && gapMs / 60000 <= _maxGapMinutes) {
        runMs += gapMs;
      }
      if (isOn && !wasOn) starts++;
      wasOn = isOn;
    }

    return _PumpActivity(starts: starts, runMinutes: runMs / 60000);
  }
}

class _PumpActivity {
  const _PumpActivity({required this.starts, required this.runMinutes});

  final int starts;
  final double runMinutes;
}
