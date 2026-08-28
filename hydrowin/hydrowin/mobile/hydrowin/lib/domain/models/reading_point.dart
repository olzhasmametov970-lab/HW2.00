import 'package:hydrowin/domain/models/sensor_status_level.dart';

class ReadingPoint {
  const ReadingPoint({
    required this.channelIndex,
    required this.value,
    required this.status,
    required this.recordedAt,
  });

  final int channelIndex;
  final double value;
  final SensorStatusLevel status;
  final DateTime recordedAt;
}

class ReadingStats {
  const ReadingStats({
    required this.avg,
    required this.min,
    required this.max,
    required this.pctInNorm,
    required this.pctWarning,
    required this.pctCritical,
    required this.warningCount,
    required this.criticalCount,
    required this.count,
    this.BLOCKOnlineMinutes = 0,
    this.pumpRunMinutes,
    this.pumpStarts,
  });

  final double avg;
  final double min;
  final double max;

  /// Доля точек со статусом OK, в процентах (0–100).
  final double pctInNorm;

  /// Доля точек со статусом warning, в процентах (0–100).
  final double pctWarning;

  /// Доля точек со статусом critical, в процентах (0–100).
  final double pctCritical;
  final int warningCount;
  final int criticalCount;
  final int count;

  /// Суммарное время, когда блок BLOCK присылал данные за период
  /// (сумма промежутков между соседними точками, не считая разрывов
  /// длиннее допустимого — это время считается офлайном блока).
  final double BLOCKOnlineMinutes;

  /// Суммарное время работы насоса за период (только для канала давления).
  /// `null`, если это не канал давления или порог не определён.
  final double? pumpRunMinutes;

  /// Количество запусков насоса (переходов «выключен → включён») за период.
  final int? pumpStarts;

  static const empty = ReadingStats(
    avg: 0,
    min: 0,
    max: 0,
    pctInNorm: 0,
    pctWarning: 0,
    pctCritical: 0,
    warningCount: 0,
    criticalCount: 0,
    count: 0,
  );
}
