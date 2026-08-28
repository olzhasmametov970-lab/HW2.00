import 'package:hydrowin/domain/models/machine_summary.dart';

class SensorLiveReading {
  const SensorLiveReading({
    required this.id,
    required this.channel,
    required this.name,
    required this.unit,
    this.value,
    this.ts,
    this.status = 'offline',
    this.fault,
    this.currentMa,
  });

  final String id;
  final int channel;
  final String name;
  final String unit;
  final double? value;
  final DateTime? ts;
  final String status;
  final String? fault;
  final double? currentMa;

  factory SensorLiveReading.fromJson(Map<String, dynamic> json) {
    final rawTs = json['ts'] as String?;
    return SensorLiveReading(
      id: json['id'] as String,
      channel: json['channel'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      unit: json['unit'] as String? ?? '',
      value: (json['value'] as num?)?.toDouble(),
      ts: rawTs != null ? DateTime.tryParse(rawTs) : null,
      status: json['status'] as String? ?? 'offline',
      fault: json['fault'] as String?,
      currentMa: (json['current_ma'] as num?)?.toDouble(),
    );
  }
}

class MachineLiveSnapshot {
  const MachineLiveSnapshot({
    required this.machineId,
    required this.code,
    required this.status,
    required this.sensors,
    this.lastSeenAt,
  });

  final String machineId;
  final String code;
  final MachineStatus status;
  final DateTime? lastSeenAt;
  final List<SensorLiveReading> sensors;

  factory MachineLiveSnapshot.fromJson(Map<String, dynamic> json) {
    final sensorsJson = json['sensors'] as List<dynamic>? ?? const [];
    return MachineLiveSnapshot(
      machineId: json['machine_id'] as String,
      code: json['code'] as String? ?? '',
      status: machineStatusFromString(json['status'] as String? ?? 'offline'),
      lastSeenAt: json['last_seen_at'] != null
          ? DateTime.tryParse(json['last_seen_at'] as String)
          : null,
      sensors: sensorsJson
          .map((e) => SensorLiveReading.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class FleetLiveSnapshot {
  const FleetLiveSnapshot({
    required this.machines,
    this.at,
  });

  final List<MachineLiveSnapshot> machines;
  final DateTime? at;

  factory FleetLiveSnapshot.fromJson(Map<String, dynamic> json) {
    final machinesJson = json['machines'] as List<dynamic>? ?? const [];
    return FleetLiveSnapshot(
      machines: machinesJson
          .map((e) => MachineLiveSnapshot.fromJson(e as Map<String, dynamic>))
          .toList(),
      at: json['at'] != null
          ? DateTime.tryParse(json['at'] as String)
          : null,
    );
  }
}
