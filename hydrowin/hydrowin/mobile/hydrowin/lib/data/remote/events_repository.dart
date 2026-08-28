import 'package:hydrowin/data/demo/demo_fleet_data.dart';
import 'package:hydrowin/data/remote/api_client.dart';

class MachineEventItem {
  const MachineEventItem({
    required this.id,
    required this.machineId,
    required this.type,
    required this.severity,
    required this.message,
    required this.ts,
    required this.acknowledged,
    this.sensorId,
    this.machineCode,
    this.machineName,
  });

  final String id;
  final String machineId;
  final String? sensorId;
  final String type;
  final String severity;
  final String message;
  final DateTime ts;
  final bool acknowledged;
  final String? machineCode;
  final String? machineName;

  factory MachineEventItem.fromJson(
    Map<String, dynamic> json, {
    String? machineCode,
    String? machineName,
  }) {
    return MachineEventItem(
      id: json['id'] as String? ?? '',
      machineId: json['machine_id'] as String? ?? '',
      sensorId: json['sensor_id'] as String?,
      type: json['type'] as String? ?? '',
      severity: json['severity'] as String? ?? 'info',
      message: json['message'] as String? ?? '',
      ts: DateTime.tryParse(json['ts'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      acknowledged: json['acknowledged'] as bool? ?? false,
      machineCode: machineCode ?? json['machine_code'] as String?,
      machineName: machineName ?? json['machine_name'] as String?,
    );
  }

  MachineEventItem copyWith({bool? acknowledged}) {
    return MachineEventItem(
      id: id,
      machineId: machineId,
      sensorId: sensorId,
      type: type,
      severity: severity,
      message: message,
      ts: ts,
      acknowledged: acknowledged ?? this.acknowledged,
      machineCode: machineCode,
      machineName: machineName,
    );
  }
}

class EventsRepository {
  EventsRepository(this._api);

  final ApiClient _api;

  Future<List<MachineEventItem>> listEvents({
    String? machineId,
    String? severity,
    String? from,
    String? to,
    bool? acknowledged,
    String? q,
  }) async {
    if (DemoSession.isActive) {
      var items = List<MachineEventItem>.from(DemoSession.events);
      if (machineId != null && machineId.isNotEmpty) {
        items = items.where((e) => e.machineId == machineId).toList();
      }
      if (severity != null && severity.isNotEmpty) {
        items = items.where((e) => e.severity == severity).toList();
      }
      if (acknowledged != null) {
        items = items.where((e) => e.acknowledged == acknowledged).toList();
      }
      if (q != null && q.trim().isNotEmpty) {
        final needle = q.trim().toLowerCase();
        items = items
            .where((e) => e.message.toLowerCase().contains(needle))
            .toList();
      }
      return items;
    }

    final query = <String, String>{};
    if (machineId != null && machineId.isNotEmpty) {
      query['machine_id'] = machineId;
    }
    if (severity != null && severity.isNotEmpty) query['severity'] = severity;
    if (from != null) query['from'] = from;
    if (to != null) query['to'] = to;
    if (acknowledged != null) query['acknowledged'] = acknowledged.toString();
    if (q != null && q.trim().isNotEmpty) query['q'] = q.trim();

    final raw = await _api.getList('/events', query: query.isEmpty ? null : query);
    return raw
        .whereType<Map<String, dynamic>>()
        .map(MachineEventItem.fromJson)
        .toList();
  }

  Future<MachineEventItem> acknowledge(String eventId) async {
    if (DemoSession.isActive) {
      final idx = DemoSession.events.indexWhere((e) => e.id == eventId);
      if (idx < 0) {
        return MachineEventItem(
          id: eventId,
          machineId: '',
          type: 'unknown',
          severity: 'info',
          message: '',
          ts: DateTime.now(),
          acknowledged: true,
        );
      }
      final updated = DemoSession.events[idx].copyWith(acknowledged: true);
      DemoSession.events[idx] = updated;
      return updated;
    }
    final raw = await _api.post('/events/$eventId/acknowledge', auth: true);
    return MachineEventItem.fromJson(raw);
  }
}
