import 'package:hydrowin/data/demo/demo_fleet_data.dart';
import 'package:hydrowin/data/remote/api_client.dart';

class ChannelPrefs {
  const ChannelPrefs({
    this.push = true,
    this.sound = true,
    this.vibration = true,
    this.email = true,
    this.telegram = true,
  });

  final bool push;
  final bool sound;
  final bool vibration;
  final bool email;
  final bool telegram;

  factory ChannelPrefs.fromJson(Map<String, dynamic>? json) {
    json ??= const {};
    return ChannelPrefs(
      push: json['push'] as bool? ?? true,
      sound: json['sound'] as bool? ?? true,
      vibration: json['vibration'] as bool? ?? true,
      email: json['email'] as bool? ?? true,
      telegram: json['telegram'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'push': push,
        'sound': sound,
        'vibration': vibration,
        'email': email,
        'telegram': telegram,
      };

  ChannelPrefs copyWith({
    bool? push,
    bool? sound,
    bool? vibration,
    bool? email,
    bool? telegram,
  }) {
    return ChannelPrefs(
      push: push ?? this.push,
      sound: sound ?? this.sound,
      vibration: vibration ?? this.vibration,
      email: email ?? this.email,
      telegram: telegram ?? this.telegram,
    );
  }
}

class QuietHoursPrefs {
  const QuietHoursPrefs({
    this.enabled = false,
    this.from = '22:00',
    this.to = '08:00',
  });

  final bool enabled;
  final String from;
  final String to;

  factory QuietHoursPrefs.fromJson(Map<String, dynamic>? json) {
    json ??= const {};
    return QuietHoursPrefs(
      enabled: json['enabled'] as bool? ?? false,
      from: json['from'] as String? ?? '22:00',
      to: json['to'] as String? ?? '08:00',
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'from': from,
        'to': to,
      };

  QuietHoursPrefs copyWith({bool? enabled, String? from, String? to}) {
    return QuietHoursPrefs(
      enabled: enabled ?? this.enabled,
      from: from ?? this.from,
      to: to ?? this.to,
    );
  }
}

class AlertContactsPrefs {
  const AlertContactsPrefs({
    this.email = '',
    this.telegram = '',
  });

  final String email;
  final String telegram;

  factory AlertContactsPrefs.fromJson(Map<String, dynamic>? json) {
    json ??= const {};
    return AlertContactsPrefs(
      email: json['email'] as String? ?? '',
      telegram: json['telegram'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'email': email,
        'telegram': telegram,
      };

  AlertContactsPrefs copyWith({
    String? email,
    String? telegram,
  }) {
    return AlertContactsPrefs(
      email: email ?? this.email,
      telegram: telegram ?? this.telegram,
    );
  }
}

class NotificationSettingsModel {
  const NotificationSettingsModel({
    required this.critical,
    required this.warning,
    required this.quietHours,
    required this.contacts,
    this.policyDescription,
  });

  final ChannelPrefs critical;
  final ChannelPrefs warning;
  final QuietHoursPrefs quietHours;
  final AlertContactsPrefs contacts;
  final String? policyDescription;

  factory NotificationSettingsModel.fromJson(Map<String, dynamic> json) {
    final policy = json['policy'] as Map<String, dynamic>?;
    return NotificationSettingsModel(
      critical: ChannelPrefs.fromJson(json['critical'] as Map<String, dynamic>?),
      warning: ChannelPrefs.fromJson(json['warning'] as Map<String, dynamic>?),
      quietHours:
          QuietHoursPrefs.fromJson(json['quiet_hours'] as Map<String, dynamic>?),
      contacts:
          AlertContactsPrefs.fromJson(json['contacts'] as Map<String, dynamic>?),
      policyDescription: policy?['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'critical': critical.toJson(),
        'warning': warning.toJson(),
        'quiet_hours': quietHours.toJson(),
        'contacts': contacts.toJson(),
      };

  NotificationSettingsModel copyWith({
    ChannelPrefs? critical,
    ChannelPrefs? warning,
    QuietHoursPrefs? quietHours,
    AlertContactsPrefs? contacts,
  }) {
    return NotificationSettingsModel(
      critical: critical ?? this.critical,
      warning: warning ?? this.warning,
      quietHours: quietHours ?? this.quietHours,
      contacts: contacts ?? this.contacts,
      policyDescription: policyDescription,
    );
  }
}

class AuditLogItem {
  const AuditLogItem({
    required this.id,
    required this.action,
    required this.severity,
    required this.message,
    required this.ts,
    this.actorEmail,
  });

  final String id;
  final String action;
  final String severity;
  final String message;
  final DateTime ts;
  final String? actorEmail;

  factory AuditLogItem.fromJson(Map<String, dynamic> json) {
    return AuditLogItem(
      id: json['id'] as String? ?? '',
      action: json['action'] as String? ?? '',
      severity: json['severity'] as String? ?? 'info',
      message: json['message'] as String? ?? '',
      ts: DateTime.tryParse(json['ts'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      actorEmail: json['actor_email'] as String?,
    );
  }
}

class NotificationsRepository {
  NotificationsRepository(this._api);

  final ApiClient _api;

  Future<NotificationSettingsModel> getSettings() async {
    if (DemoSession.isActive) return DemoSession.notificationSettings;
    final json = await _api.get('/notifications/settings');
    return NotificationSettingsModel.fromJson(json);
  }

  Future<NotificationSettingsModel> updateSettings(
    NotificationSettingsModel settings,
  ) async {
    if (DemoSession.isActive) {
      DemoSession.notificationSettings = settings;
      return settings;
    }
    final json = await _api.put(
      '/notifications/settings',
      body: settings.toJson(),
      auth: true,
    );
    return NotificationSettingsModel.fromJson(json);
  }

  Future<void> testTelegram() async {
    if (DemoSession.isActive) return;
    await _api.post('/notifications/test-telegram', body: const {}, auth: true);
  }

  Future<void> testEmail() async {
    if (DemoSession.isActive) return;
    await _api.post('/notifications/test-email', body: const {}, auth: true);
  }

  Future<List<AuditLogItem>> listAudit({String? q}) async {
    if (DemoSession.isActive) {
      var items = DemoFleetData.auditLog();
      if (q != null && q.trim().isNotEmpty) {
        final needle = q.trim().toLowerCase();
        items = items
            .where((e) => e.message.toLowerCase().contains(needle))
            .toList();
      }
      return items;
    }
    final query = <String, String>{};
    if (q != null && q.trim().isNotEmpty) query['q'] = q.trim();
    final raw = await _api.getList(
      '/audit',
      query: query.isEmpty ? null : query,
    );
    return raw
        .whereType<Map<String, dynamic>>()
        .map(AuditLogItem.fromJson)
        .toList();
  }
}
