import 'package:hydrowin/domain/models/sensor_type.dart';

class SensorConfig {
  const SensorConfig({
    required this.channelIndex,
    this.enabled = true,
    required this.name,
    required this.type,
    required this.scaleMin,
    required this.scaleMax,
    this.normMin,
    required this.normMax,
    this.warnHigh,
    required this.criticalHigh,
    this.criticalLow,
  });

  final int channelIndex;
  final bool enabled;
  final String name;
  final SensorType type;
  final double scaleMin;
  final double scaleMax;
  final double? normMin;
  final double normMax;
  final double? warnHigh;
  final double criticalHigh;
  final double? criticalLow;

  String get unit => type.unit;

  static SensorConfig defaults(int channelIndex, SensorType type) {
    return switch (type) {
      SensorType.pressure => SensorConfig(
          channelIndex: channelIndex,
          enabled: true,
          name: channelIndex == 0 ? 'Стрела подъёма' : 'Давление',
          type: type,
          scaleMin: 0,
          scaleMax: 400,
          normMin: 100,
          normMax: 250,
          warnHigh: 300,
          criticalHigh: 300,
          criticalLow: 90,
        ),
      SensorType.temperature => SensorConfig(
          channelIndex: channelIndex,
          enabled: true,
          name: channelIndex == 1 ? 'Гидромотор' : 'Температура',
          type: type,
          scaleMin: -50,
          scaleMax: 200,
          normMin: 40,
          normMax: 85,
          warnHigh: 90,
          criticalHigh: 95,
        ),
      SensorType.flow => SensorConfig(
          channelIndex: channelIndex,
          enabled: true,
          name: 'Основная линия',
          type: type,
          scaleMin: 0,
          scaleMax: 50,
          normMin: 10,
          normMax: 15,
          warnHigh: 20,
          criticalHigh: 20,
        ),
      SensorType.level => SensorConfig(
          channelIndex: channelIndex,
          enabled: true,
          name: 'Уровень',
          type: type,
          scaleMin: 0,
          scaleMax: 100,
          normMin: 20,
          normMax: 90,
          warnHigh: 95,
          criticalHigh: 98,
          criticalLow: 10,
        ),
      SensorType.vibration => SensorConfig(
          channelIndex: channelIndex,
          enabled: true,
          name: 'Вибрация',
          type: type,
          scaleMin: 0,
          scaleMax: 50,
          normMin: 0,
          normMax: 10,
          warnHigh: 15,
          criticalHigh: 25,
        ),
      SensorType.custom => SensorConfig(
          channelIndex: channelIndex,
          enabled: true,
          name: 'Датчик ${channelIndex + 1}',
          type: type,
          scaleMin: 0,
          scaleMax: 100,
          normMax: 100,
          criticalHigh: 999,
        ),
    };
  }

  static List<SensorConfig> defaultSet(int count) {
    const types = [SensorType.pressure, SensorType.temperature, SensorType.flow];
    return List.generate(
      count,
      (i) => defaults(i, types[i % types.length]),
    );
  }

  SensorConfig copyWith({
    int? channelIndex,
    bool? enabled,
    String? name,
    SensorType? type,
    double? scaleMin,
    double? scaleMax,
    double? normMin,
    bool clearNormMin = false,
    double? normMax,
    double? warnHigh,
    double? criticalHigh,
    double? criticalLow,
    bool clearCriticalLow = false,
  }) {
    return SensorConfig(
      channelIndex: channelIndex ?? this.channelIndex,
      enabled: enabled ?? this.enabled,
      name: name ?? this.name,
      type: type ?? this.type,
      scaleMin: scaleMin ?? this.scaleMin,
      scaleMax: scaleMax ?? this.scaleMax,
      normMin: clearNormMin ? null : (normMin ?? this.normMin),
      normMax: normMax ?? this.normMax,
      warnHigh: warnHigh ?? this.warnHigh,
      criticalHigh: criticalHigh ?? this.criticalHigh,
      criticalLow: clearCriticalLow ? null : (criticalLow ?? this.criticalLow),
    );
  }

  Map<String, dynamic> toJson() => {
        'channelIndex': channelIndex,
        'enabled': enabled,
        'name': name,
        'type': type.name,
        'scaleMin': scaleMin,
        'scaleMax': scaleMax,
        'normMin': normMin,
        'normMax': normMax,
        'warnHigh': warnHigh,
        'criticalHigh': criticalHigh,
        'criticalLow': criticalLow,
      };

  factory SensorConfig.fromJson(Map<String, dynamic> json) {
    return SensorConfig(
      channelIndex: json['channelIndex'] as int,
      enabled: json['enabled'] as bool? ?? true,
      name: json['name'] as String,
      type: SensorType.fromApi(json['type'] as String),
      scaleMin: (json['scaleMin'] as num).toDouble(),
      scaleMax: (json['scaleMax'] as num).toDouble(),
      normMin: (json['normMin'] as num?)?.toDouble(),
      normMax: (json['normMax'] as num).toDouble(),
      warnHigh: (json['warnHigh'] as num?)?.toDouble(),
      criticalHigh: (json['criticalHigh'] as num).toDouble(),
      criticalLow: (json['criticalLow'] as num?)?.toDouble(),
    );
  }

  /// OpenAPI `SensorConfig` (snake_case) — для PUT /machines/{ip}/sensors.
  Map<String, dynamic> toApiJson() => {
        'channel_index': channelIndex,
        'enabled': enabled,
        'name': name,
        'type': type.name,
        'unit': unit,
        'scale_min': scaleMin,
        'scale_max': scaleMax,
        'norm_min': normMin,
        'norm_max': normMax,
        'warn_high': warnHigh,
        'critical_high': criticalHigh,
        'critical_low': criticalLow,
      };

  /// OpenAPI `SensorConfig` (snake_case).
  factory SensorConfig.fromApiJson(Map<String, dynamic> json) {
    return SensorConfig(
      channelIndex: json['channel_index'] as int,
      enabled: json['enabled'] as bool? ?? true,
      name: json['name'] as String,
      type: SensorType.fromApi(json['type'] as String),
      scaleMin: (json['scale_min'] as num).toDouble(),
      scaleMax: (json['scale_max'] as num).toDouble(),
      normMin: (json['norm_min'] as num?)?.toDouble(),
      normMax: (json['norm_max'] as num).toDouble(),
      warnHigh: (json['warn_high'] as num?)?.toDouble(),
      criticalHigh: (json['critical_high'] as num).toDouble(),
      criticalLow: (json['critical_low'] as num?)?.toDouble(),
    );
  }

  /// Подправляет пороги, если «критично ниже» ≥ «норма от».
  SensorConfig repairThresholds() {
    var c = this;
    if (c.criticalLow != null) {
      final normLo = c.normMin ?? c.scaleMin;
      if (c.criticalLow! >= normLo) {
        final fixed = (normLo - 1).clamp(c.scaleMin, c.scaleMax).toDouble();
        c = c.copyWith(criticalLow: fixed);
      }
    }
    if (c.criticalHigh < c.normMax) {
      c = c.copyWith(criticalHigh: c.normMax);
    }
    return c;
  }

  String? validate() {
    if (name.trim().isEmpty) return 'Укажите название датчика';
    if (scaleMin >= scaleMax) return 'Мин. шкалы должно быть меньше макс.';
    if (criticalLow != null) {
      final normLo = normMin ?? scaleMin;
      if (criticalLow! >= normLo) {
        return '«Критично ниже» ($criticalLow) должно быть меньше «Норма от» ($normLo)';
      }
      if (criticalLow! < scaleMin) {
        return '«Критично ниже» не может быть меньше мин. шкалы ($scaleMin)';
      }
    }
    final normLo = normMin ?? scaleMin;
    if (normLo >= normMax) return 'Норма: нижняя граница должна быть меньше верхней';
    if (normMax > scaleMax) return 'Верхняя норма не может превышать макс. шкалы';
    if (criticalHigh < normMax) return 'Критично (высоко) должно быть не ниже нормы';
    return null;
  }
}
