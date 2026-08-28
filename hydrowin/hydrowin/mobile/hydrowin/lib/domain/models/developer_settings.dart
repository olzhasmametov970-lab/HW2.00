class DeveloperSettings {
  const DeveloperSettings({
    this.serverHost = '',
    this.apiPort = 8090,
    this.BLOCKPort = 80,
    this.apiPath = '/v1',
    this.useCustomServer = false,
  });

  final String serverHost;
  final int apiPort;
  final int BLOCKPort;
  final String apiPath;
  final bool useCustomServer;

  bool get isConfigured =>
      useCustomServer && serverHost.trim().isNotEmpty && apiPort > 0;

  String get apiBaseUrl {
    if (!isConfigured) return '';
    final path = apiPath.startsWith('/') ? apiPath : '/$apiPath';
    final host = serverHost.trim();
    final local = host == 'localhost' ||
        host == '127.0.0.1' ||
        host.startsWith('192.168.') ||
        host.startsWith('10.');
    // Снаружи — только HTTPS. HTTP разрешён лишь для LAN/loopback.
    final scheme = (!local || apiPort == 443) ? 'https' : 'http';
    if (apiPort == 443 || (scheme == 'http' && apiPort == 80)) {
      return '$scheme://$host$path';
    }
    return '$scheme://$host:$apiPort$path';
  }

  DeveloperSettings copyWith({
    String? serverHost,
    int? apiPort,
    int? BLOCKPort,
    String? apiPath,
    bool? useCustomServer,
  }) {
    return DeveloperSettings(
      serverHost: serverHost ?? this.serverHost,
      apiPort: apiPort ?? this.apiPort,
      BLOCKPort: BLOCKPort ?? this.BLOCKPort,
      apiPath: apiPath ?? this.apiPath,
      useCustomServer: useCustomServer ?? this.useCustomServer,
    );
  }

  Map<String, dynamic> toJson() => {
    'server_host': serverHost,
    'api_port': apiPort,
    'BLOCK_port': BLOCKPort,
    'api_path': apiPath,
    'use_custom_server': useCustomServer,
  };

  factory DeveloperSettings.fromJson(Map<String, dynamic> json) {
    return DeveloperSettings(
      serverHost: json['server_host'] as String? ?? '',
      apiPort: json['api_port'] as int? ?? 8090,
      BLOCKPort: json['block_port'] as int? ?? 80,
      apiPath: json['api_path'] as String? ?? '/v1',
      useCustomServer: json['use_custom_server'] as bool? ?? false,
    );
  }
}
