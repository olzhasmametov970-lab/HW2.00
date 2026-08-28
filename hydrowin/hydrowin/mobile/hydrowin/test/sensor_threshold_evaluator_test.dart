import 'package:flutter_test/flutter_test.dart';
import 'package:hydrowin/core/theme/app_theme.dart';
import 'package:hydrowin/domain/models/sensor_config.dart';
import 'package:hydrowin/domain/models/sensor_type.dart';
import 'package:hydrowin/domain/sensor_threshold_evaluator.dart';

void main() {
  test('pressure in norm is ok', () {
    final c = SensorConfig.defaults(0, SensorType.pressure);
    expect(
      SensorThresholdEvaluator.evaluate(c, 145),
      SensorStatusLevel.ok,
    );
  });

  test('pressure below critical is critical', () {
    final c = SensorConfig.defaults(0, SensorType.pressure);
    expect(
      SensorThresholdEvaluator.evaluate(c, 89),
      SensorStatusLevel.critical,
    );
  });

  test('temperature above norm is warning', () {
    final c = SensorConfig.defaults(1, SensorType.temperature);
    expect(
      SensorThresholdEvaluator.evaluate(c, 52),
      SensorStatusLevel.warning,
    );
  });

  test('temperature above critical is critical', () {
    final c = SensorConfig.defaults(1, SensorType.temperature);
    expect(
      SensorThresholdEvaluator.evaluate(c, 56),
      SensorStatusLevel.critical,
    );
  });
}
