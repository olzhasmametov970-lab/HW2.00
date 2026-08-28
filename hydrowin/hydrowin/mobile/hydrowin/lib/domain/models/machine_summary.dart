enum MachineStatus { ok, warning, critical, offline }

MachineStatus machineStatusFromString(String value) {
  return MachineStatus.values.firstWhere(
    (s) => s.name == value,
    orElse: () => MachineStatus.offline,
  );
}

/// Как текущий пользователь видит машину в API.
enum MachineAccess { owner, manufacturerReadonly, platform }

MachineAccess machineAccessFromString(String? value) {
  if (value == 'manufacturer_readonly') {
    return MachineAccess.manufacturerReadonly;
  }
  if (value == 'platform') {
    return MachineAccess.platform;
  }
  return MachineAccess.owner;
}

class MachineGps {
  const MachineGps({required this.lat, required this.lon, this.accuracyM = 0});

  final double lat;
  final double lon;
  final double accuracyM;

  factory MachineGps.fromJson(Map<String, dynamic> json) {
    return MachineGps(
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      accuracyM: (json['accuracy_m'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lon': lon,
    'accuracy_m': accuracyM,
  };
}

class MachineGeofence {
  const MachineGeofence({
    required this.name,
    required this.centerLat,
    required this.centerLon,
    required this.radiusM,
    required this.enabled,
    this.inside,
  });

  final String name;
  final double centerLat;
  final double centerLon;
  final double radiusM;
  final bool enabled;
  final bool? inside;

  factory MachineGeofence.fromJson(Map<String, dynamic> json) {
    return MachineGeofence(
      name: json['name'] as String? ?? '',
      centerLat: (json['center_lat'] as num?)?.toDouble() ?? 0,
      centerLon: (json['center_lon'] as num?)?.toDouble() ?? 0,
      radiusM: (json['radius_m'] as num?)?.toDouble() ?? 0,
      enabled: json['enabled'] as bool? ?? false,
      inside: json['inside'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'center_lat': centerLat,
        'center_lon': centerLon,
        'radius_m': radiusM,
        'enabled': enabled,
      };
}

class MachineTrackPoint {
  const MachineTrackPoint({
    required this.lat,
    required this.lon,
    required this.ts,
    this.accuracyM = 0,
    this.source = 'ingest',
  });

  final double lat;
  final double lon;
  final DateTime ts;
  final double accuracyM;
  final String source;

  factory MachineTrackPoint.fromJson(Map<String, dynamic> json) {
    return MachineTrackPoint(
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      ts: DateTime.tryParse(json['ts'] as String? ?? '') ?? DateTime.now(),
      accuracyM: (json['accuracy_m'] as num?)?.toDouble() ?? 0,
      source: json['source'] as String? ?? 'ingest',
    );
  }
}

class FleetTotals {
  const FleetTotals({
    required this.total,
    required this.ok,
    required this.warning,
    required this.critical,
    required this.offline,
  });

  final int total;
  final int ok;
  final int warning;
  final int critical;
  final int offline;

  factory FleetTotals.fromJson(Map<String, dynamic> json) {
    return FleetTotals(
      total: json['total'] as int? ?? 0,
      ok: json['ok'] as int? ?? 0,
      warning: json['warning'] as int? ?? 0,
      critical: json['critical'] as int? ?? 0,
      offline: json['offline'] as int? ?? 0,
    );
  }
}

class MachineSummary {
  const MachineSummary({
    required this.id,
    required this.code,
    required this.name,
    required this.model,
    required this.status,
    required this.locationLabel,
    required this.operatorName,
    this.headlineAlert,
    this.engineHours,
    this.uptimeHours,
    this.pumpHours,
    this.pumpStarts,
    this.pumpOnPressureBar = 20,
    this.pumpOnTemperatureC = 35,
    this.lastSeenAt,
    this.ipAddress,
    this.access = MachineAccess.owner,
    this.canConfigure = true,
    this.canReassign = false,
    this.ownerOrgName,
    this.organizationId,
    this.gps,
    this.geofence,
    this.description = '',
    this.photoUrl,
  });

  final String id;
  final String code;
  final String name;
  final String model;
  final MachineStatus status;
  final String locationLabel;
  final String operatorName;
  final String? headlineAlert;
  final double? engineHours;
  final double? uptimeHours;
  final double? pumpHours;
  final int? pumpStarts;
  /// Порог «насос вкл» по давлению (бар).
  final double pumpOnPressureBar;
  /// Порог «насос вкл» по температуре (°C), если давление низкое, но линия жива.
  final double pumpOnTemperatureC;
  final DateTime? lastSeenAt;
  final String? ipAddress;
  final MachineAccess access;
  final bool canConfigure;
  final bool canReassign;
  final String? ownerOrgName;
  final String? organizationId;
  final MachineGps? gps;
  final MachineGeofence? geofence;
  final String description;
  final String? photoUrl;

  bool get isReadOnlyForCurrentUser =>
      access == MachineAccess.manufacturerReadonly;

  MachineSummary copyWith({
    String? ipAddress,
    String? code,
    String? name,
    String? operatorName,
    String? locationLabel,
    double? engineHours,
    double? uptimeHours,
    double? pumpHours,
    int? pumpStarts,
    double? pumpOnPressureBar,
    double? pumpOnTemperatureC,
    MachineStatus? status,
    DateTime? lastSeenAt,
    MachineGps? gps,
    MachineGeofence? geofence,
    bool clearGps = false,
    String? description,
    String? photoUrl,
    bool clearPhoto = false,
  }) {
    return MachineSummary(
      id: id,
      code: code ?? this.code,
      name: name ?? this.name,
      model: model,
      status: status ?? this.status,
      locationLabel: locationLabel ?? this.locationLabel,
      operatorName: operatorName ?? this.operatorName,
      headlineAlert: headlineAlert,
      engineHours: engineHours ?? this.engineHours,
      uptimeHours: uptimeHours ?? this.uptimeHours,
      pumpHours: pumpHours ?? this.pumpHours,
      pumpStarts: pumpStarts ?? this.pumpStarts,
      pumpOnPressureBar: pumpOnPressureBar ?? this.pumpOnPressureBar,
      pumpOnTemperatureC: pumpOnTemperatureC ?? this.pumpOnTemperatureC,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      ipAddress: ipAddress ?? this.ipAddress,
      access: access,
      canConfigure: canConfigure,
      canReassign: canReassign,
      ownerOrgName: ownerOrgName,
      organizationId: organizationId,
      gps: clearGps ? null : (gps ?? this.gps),
      geofence: geofence ?? this.geofence,
      description: description ?? this.description,
      photoUrl: clearPhoto ? null : (photoUrl ?? this.photoUrl),
    );
  }

  factory MachineSummary.fromJson(Map<String, dynamic> json) {
    final gpsJson = json['gps'];
    final geofenceJson = json['geofence'];
    return MachineSummary(
      id: json['id'] as String,
      code: json['code'] as String,
      name: json['name'] as String,
      model: json['model'] as String? ?? '',
      status: machineStatusFromString(json['status'] as String? ?? 'offline'),
      locationLabel: json['location_label'] as String? ?? '',
      operatorName: json['operator_name'] as String? ?? '',
      headlineAlert: json['headline_alert'] as String?,
      engineHours: (json['engine_hours'] as num?)?.toDouble(),
      uptimeHours: (json['uptime_hours'] as num?)?.toDouble() ?? 0,
      pumpHours: (json['pump_hours'] as num?)?.toDouble() ?? 0,
      pumpStarts: (json['pump_starts'] as num?)?.toInt() ?? 0,
      pumpOnPressureBar:
          (json['pump_on_pressure_bar'] as num?)?.toDouble() ?? 20,
      pumpOnTemperatureC:
          (json['pump_on_temperature_c'] as num?)?.toDouble() ?? 35,
      lastSeenAt: json['last_seen_at'] != null
          ? DateTime.parse(json['last_seen_at'] as String)
          : null,
      ipAddress: json['ip_address'] as String?,
      access: machineAccessFromString(json['access'] as String?),
      canConfigure: json['can_configure'] as bool? ?? true,
      canReassign: json['can_reassign'] as bool? ?? false,
      ownerOrgName: json['owner_org_name'] as String?,
      organizationId: json['organization_id'] as String?,
      gps: gpsJson is Map<String, dynamic>
          ? MachineGps.fromJson(gpsJson)
          : null,
      geofence: geofenceJson is Map<String, dynamic>
          ? MachineGeofence.fromJson(geofenceJson)
          : null,
      description: json['description'] as String? ?? '',
      photoUrl: json['photo_url'] as String?,
    );
  }
}

class MachineListResponse {
  const MachineListResponse({required this.items, required this.totals});

  final List<MachineSummary> items;
  final FleetTotals totals;

  factory MachineListResponse.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['items'] as List<dynamic>? ?? [];
    return MachineListResponse(
      items: itemsJson
          .map((e) => MachineSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
      totals: FleetTotals.fromJson(
        json['totals'] as Map<String, dynamic>? ?? {},
      ),
    );
  }
}
