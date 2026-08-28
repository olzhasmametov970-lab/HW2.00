import 'package:hydrowin/core/ble/telemetry_packet.dart';
import 'package:hydrowin/domain/loop_current.dart';
import 'package:hydrowin/domain/sensor_display_format.dart';
import 'package:hydrowin/domain/models/sensor_config.dart';
import 'package:hydrowin/domain/models/sensor_status_level.dart';

class LiveSensorReading {
  const LiveSensorReading({
    required this.config,
    required this.value,
    required this.status,
    required this.updatedAt,
    this.fromDeviceStatus = false,
    this.loopFault = LoopFault.none,
    this.currentMa,
  });

  final SensorConfig config;
  final double value;
  final SensorStatusLevel status;
  final DateTime updatedAt;
  final bool fromDeviceStatus;
  final LoopFault loopFault;

  /// Ток петли 4–20 мА (с платы или оценка по шкале). Сервисная метрика.
  final double? currentMa;

  String get formattedValue {
    switch (loopFault) {
      case LoopFault.open:
        return 'обрыв цепи / датчик';
      case LoopFault.short:
        return 'короткое замыкание';
      case LoopFault.none:
        return SensorDisplayFormat.valueWithUnit(value, config.unit);
    }
  }

  String get formattedServiceCurrent =>
      LoopCurrent.formatMa(currentMa, fault: loopFault);

  String get alertTitle => switch (loopFault) {
        LoopFault.open => 'Обрыв цепи',
        LoopFault.short => 'Короткое замыкание',
        LoopFault.none =>
          status == SensorStatusLevel.critical ? 'Критично' : 'Внимание',
      };

  /// Текст аварии с током — для пуша и журнала гарантии.
  String get alertDetailBody {
    final ma = formattedServiceCurrent;
    switch (loopFault) {
      case LoopFault.open:
        return '${config.name}: обрыв петли 4–20 мА · $ma';
      case LoopFault.short:
        return '${config.name}: КЗ петли 4–20 мА · $ma';
      case LoopFault.none:
        return '${config.name}: $formattedValue · $ma';
    }
  }

  bool get isAccident =>
      status == SensorStatusLevel.critical ||
      loopFault == LoopFault.open ||
      loopFault == LoopFault.short;
}
