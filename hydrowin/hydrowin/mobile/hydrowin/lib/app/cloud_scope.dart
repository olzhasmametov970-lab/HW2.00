import 'package:flutter/material.dart';
import 'package:hydrowin/data/local/developer_settings_repository.dart';
import 'package:hydrowin/data/local/network_settings_repository.dart';
import 'package:hydrowin/data/local/server_config_service.dart';
import 'package:hydrowin/data/local/token_storage.dart';
import 'package:hydrowin/data/remote/api_client.dart';
import 'package:hydrowin/data/remote/auth_repository.dart';
import 'package:hydrowin/data/remote/events_repository.dart';
import 'package:hydrowin/data/remote/machines_repository.dart';
import 'package:hydrowin/data/remote/organizations_repository.dart';
import 'package:hydrowin/data/remote/notifications_repository.dart';

class CloudScope extends InheritedWidget {
  const CloudScope({
    required this.auth,
    required this.machines,
    required this.organizations,
    required this.events,
    required this.notifications,
    required this.tokens,
    required this.serverConfig,
    required this.developerSettings,
    required this.networkSettings,
    required this.api,
    required super.child,
    super.key,
  });

  final AuthRepository auth;
  final MachinesRepository machines;
  final OrganizationsRepository organizations;
  final EventsRepository events;
  final NotificationsRepository notifications;
  final TokenStorage tokens;
  final ServerConfigService serverConfig;
  final DeveloperSettingsRepository developerSettings;
  final NetworkSettingsRepository networkSettings;
  final ApiClient api;

  static CloudScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<CloudScope>();
    assert(scope != null, 'CloudScope not found');
    return scope!;
  }

  /// Lite-сборка без облака — вернёт null.
  static CloudScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<CloudScope>();
  }

  @override
  bool updateShouldNotify(CloudScope oldWidget) => false;
}
