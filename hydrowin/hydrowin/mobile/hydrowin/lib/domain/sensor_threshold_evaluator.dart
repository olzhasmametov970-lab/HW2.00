import 'package:hydrowin/domain/models/sensor_config.dart';
import 'package:hydrowin/domain/models/sensor_status_level.dart';

/// Вычисляет статус датчика по порогам из конфигурации приложения.
abstract final class SensorThresholdEvaluator {
  static SensorStatusLevel evaluate(SensorConfig config, double value) {
    if (config.criticalLow != null && value < config.criticalLow!) {
      return SensorStatusLevel.critical;
    }
    if (value > config.criticalHigh) {
      return SensorStatusLevel.critical;
    }

    final normLo = config.normMin ?? config.scaleMin;
    if (value < normLo || value > config.normMax) {
      if (config.warnHigh != null &&
          value > config.normMax &&
          value <= config.warnHigh!) {
        return SensorStatusLevel.warning;
      }
      if (value < normLo) return SensorStatusLevel.warning;
      if (value > config.normMax) return SensorStatusLevel.warning;
    }

    return SensorStatusLevel.ok;
  }
}
