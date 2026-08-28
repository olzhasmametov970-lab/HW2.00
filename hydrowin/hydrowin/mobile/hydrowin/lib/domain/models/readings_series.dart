import 'package:hydrowin/domain/models/reading_point.dart';
import 'package:hydrowin/domain/models/sensor_status_level.dart';

class ReadingsSeries {
  const ReadingsSeries({
    required this.sensorId,
    required this.unit,
    required this.points,
  });

  final String sensorId;
  final String unit;
  final List<ReadingPoint> points;

  factory ReadingsSeries.fromApiJson(
    Map<String, dynamic> json, {
    required int channelIndex,
  }) {
    final raw = json['points'] as List<dynamic>? ?? [];
    final points = raw.map((e) {
      final m = e as Map<String, dynamic>;
      return ReadingPoint(
        channelIndex: channelIndex,
        value: (m['value'] as num).toDouble(),
        status: _statusFromApi(m['status'] as String? ?? 'ok'),
        recordedAt: DateTime.parse(m['ts'] as String),
      );
    }).toList();

    return ReadingsSeries(
      sensorId: json['sensor_id'] as String,
      unit: json['unit'] as String? ?? '',
      points: points,
    );
  }
}

SensorStatusLevel _statusFromApi(String s) {
  return switch (s) {
    'warning' => SensorStatusLevel.warning,
    'critical' => SensorStatusLevel.critical,
    'offline' => SensorStatusLevel.offline,
    _ => SensorStatusLevel.ok,
  };
}
