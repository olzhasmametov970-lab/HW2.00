import 'dart:io';

import 'package:hydrowin/domain/models/reading_point.dart';
import 'package:hydrowin/features/chart/chart_export.dart';

/// Обратная совместимость: делегирует в [ChartExport].
abstract final class ChartCsvExport {
  static Future<File> save({
    required List<ReadingPoint> points,
    required String sensorName,
    required String unit,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    ReadingStats? stats,
    String? machineLabel,
    double? engineHours,
  }) {
    return ChartExport.save(
      format: ChartExportFormat.csv,
      points: points,
      sensorName: sensorName,
      unit: unit,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      stats: stats,
      machineLabel: machineLabel,
      engineHours: engineHours,
    );
  }
}
