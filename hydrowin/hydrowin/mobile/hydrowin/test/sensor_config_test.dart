import 'package:flutter_test/flutter_test.dart';
import 'package:hydrowin/domain/models/sensor_config.dart';
import 'package:hydrowin/domain/models/sensor_type.dart';

void main() {
  test('pressure defaults pass validation', () {
    final c = SensorConfig.defaults(0, SensorType.pressure);
    expect(c.validate(), isNull);
    expect(c.criticalLow, lessThan(c.normMin!));
  });

  test('repairThresholds fixes criticalLow equal to normMin', () {
    final c = SensorConfig.defaults(0, SensorType.pressure)
        .copyWith(criticalLow: 100, normMin: 100);
    final fixed = c.repairThresholds();
    expect(fixed.validate(), isNull);
    expect(fixed.criticalLow, lessThan(fixed.normMin!));
  });

  test('flow defaults pass validation', () {
    final c = SensorConfig.defaults(0, SensorType.flow);
    expect(c.validate(), isNull);
  });
}
