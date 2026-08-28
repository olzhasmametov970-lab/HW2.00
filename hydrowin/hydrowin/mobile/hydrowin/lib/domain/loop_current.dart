import 'package:hydrowin/core/ble/telemetry_packet.dart';
import 'package:hydrowin/domain/models/sensor_config.dart';
import 'package:hydrowin/domain/models/sensor_type.dart';

/// Петля 4–20 мА: оценка тока по шкале и пороги обрыва/КЗ (как на плате).
abstract final class LoopCurrent {
  static const openBelowMa = 3.2;
  static const shortAboveMa = 21.0;
  static const loopMinMa = 4.0;
  static const loopMaxMa = 20.0;

  /// Обратная калибровка платы: value ≈ scaleMin + (mA−4)/16 · (scaleMax−scaleMin).
  /// Offset на плате неизвестен приложению — оценка без него (±чуть).
  static double? estimateMaFromValue(SensorConfig config, double value) {
    final span = config.scaleMax - config.scaleMin;
    if (span.abs() < 1e-6) return null;
    final ratio = ((value - config.scaleMin) / span).clamp(0.0, 1.0);
    return loopMinMa + ratio * (loopMaxMa - loopMinMa);
  }

  /// При обрыве/КЗ в BLE value может нести реальный ток (мА) с платы.
  static double? resolve({
    required SensorConfig config,
    required double packetValue,
    required LoopFault fault,
  }) {
    switch (fault) {
      case LoopFault.open:
        // Старые платы шлют 0; новые — фактический ток.
        if (packetValue > 0.05 && packetValue < openBelowMa + 2) {
          return packetValue;
        }
        return packetValue > 0 ? packetValue : openBelowMa * 0.5;
      case LoopFault.short:
        if (packetValue >= shortAboveMa - 1) return packetValue;
        return packetValue > loopMaxMa ? packetValue : shortAboveMa + 1;
      case LoopFault.none:
        return estimateMaFromValue(config, packetValue);
    }
  }

  static String formatMa(double? ma, {LoopFault fault = LoopFault.none}) {
    if (ma == null) {
      return switch (fault) {
        LoopFault.open => '< ${openBelowMa.toStringAsFixed(1)} мА',
        LoopFault.short => '> ${shortAboveMa.toStringAsFixed(1)} мА',
        LoopFault.none => '— мА',
      };
    }
    return '${ma.toStringAsFixed(1)} мА';
  }

  /// fault — только явное поле API; currentMa — только ток с платы (мА),
  /// не подставлять инженерное значение (°C, бар и т.д.).
  static LoopFault faultFromApi(String? raw, {double? currentMa}) {
    final fault = switch (raw?.toLowerCase()) {
      'open' => LoopFault.open,
      'short' => LoopFault.short,
      _ => LoopFault.none,
    };
    if (fault != LoopFault.none) return fault;
    if (currentMa == null) return LoopFault.none;
    if (currentMa < openBelowMa) return LoopFault.open;
    if (currentMa > shortAboveMa) return LoopFault.short;
    return LoopFault.none;
  }

  /// Облако: только явное поле fault с API.
  /// current_ma — для подписи «Петля … мА», не для угадывания обрыва
  /// (иначе value=1 бар / залипший current_ma → ложный OPEN).
  static LoopFault faultFromCloud({
    required String? apiFault,
    required double? currentMa,
    required double value,
    required SensorType type,
  }) {
    // value/type/currentMa — совместимость; fault только из apiFault.
    return switch (apiFault?.toLowerCase()) {
      'open' => LoopFault.open,
      'short' => LoopFault.short,
      _ => LoopFault.none,
    };
  }

  static double? cloudCurrentMa({
    required double? apiCurrentMa,
    required LoopFault fault,
    required double value,
    required SensorConfig config,
  }) {
    if (apiCurrentMa != null) return apiCurrentMa;
    if (fault == LoopFault.none) return null;
    return resolve(config: config, packetValue: value, fault: fault);
  }
}
