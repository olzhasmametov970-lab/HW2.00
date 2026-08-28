class FleetMachineEntry {
  const FleetMachineEntry({
    required this.id,
    required this.number,
    required this.name,
    required this.ipAddress,
    this.model,
    this.serverId,
  });

  final String id;

  /// Номер машины, например «001».
  final String number;
  final String name;

  /// IP блока BLOCK или шлюза на машине.
  final String ipAddress;
  final String? model;

  /// UUID машины на сервере (если синхронизировано).
  final String? serverId;

  String get displayCode => number.startsWith('#') ? number : '#$number';

  FleetMachineEntry copyWith({
    String? id,
    String? number,
    String? name,
    String? ipAddress,
    String? model,
    String? serverId,
  }) {
    return FleetMachineEntry(
      id: id ?? this.id,
      number: number ?? this.number,
      name: name ?? this.name,
      ipAddress: ipAddress ?? this.ipAddress,
      model: model ?? this.model,
      serverId: serverId ?? this.serverId,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'number': number,
    'name': name,
    'ip_address': ipAddress,
    if (model != null) 'model': model,
    if (serverId != null) 'server_id': serverId,
  };

  factory FleetMachineEntry.fromJson(Map<String, dynamic> json) {
    return FleetMachineEntry(
      id: json['id'] as String,
      number: json['number'] as String,
      name: json['name'] as String,
      ipAddress: json['ip_address'] as String? ?? '',
      model: json['model'] as String?,
      serverId: json['server_id'] as String?,
    );
  }
}
