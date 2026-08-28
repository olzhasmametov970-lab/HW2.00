import 'package:flutter_test/flutter_test.dart';
import 'package:hydrowin/core/theme/app_theme.dart';
import 'package:hydrowin/domain/models/readings_series.dart';
import 'package:hydrowin/domain/models/sensor_config.dart';

void main() {
  test('SensorConfig.fromApiJson maps snake_case', () {
    final c = SensorConfig.fromApiJson({
      'channel_index': 2,
      'name': 'Test',
      'type': 'flow',
      'scale_min': 0,
      'scale_max': 50,
      'norm_min': 10,
      'norm_max': 15,
      'warn_high': 20,
      'critical_high': 20,
      'critical_low': null,
    });
    expect(c.channelIndex, 2);
    expect(c.type.name, 'flow');
    expect(c.normMin, 10);
  });

  test('ReadingsSeries.fromApiJson maps points', () {
    final s = ReadingsSeries.fromApiJson(
      {
        'sensor_id': 'u1',
        'unit': 'bar',
        'points': [
          {
            'ts': '2026-05-18T08:00:00Z',
            'value': 100.5,
            'status': 'warning',
          },
          {
            'ts': '2026-05-18T08:05:00Z',
            'value': 101,
            'status': 'ok',
          },
        ],
      },
      channelIndex: 0,
    );
    expect(s.points, hasLength(2));
    expect(s.points.first.status, SensorStatusLevel.warning);
    expect(s.points.first.value, 100.5);
  });
}
