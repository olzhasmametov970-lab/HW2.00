import 'package:hydrowin/domain/models/sensor_config.dart';

/// Датчик машины в облаке: UUID с сервера + локальная модель порогов.
class CloudSensor {
  const CloudSensor({required this.id, required this.config});

  final String id;
  final SensorConfig config;

  factory CloudSensor.fromApiJson(Map<String, dynamic> json) {
    return CloudSensor(
      id: json['id'] as String,
      config: SensorConfig.fromApiJson(json),
    );
  }

  Map<String, dynamic> toApiJson() => {'id': id, ...config.toApiJson()};
}
