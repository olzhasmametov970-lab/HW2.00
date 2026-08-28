import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:hydrowin/app/app.dart';
import 'package:hydrowin/app/app_scope.dart';
import 'package:hydrowin/app/cloud_scope.dart';
import 'package:hydrowin/app/notification_center.dart';
import 'package:hydrowin/app/router.dart';
import 'package:hydrowin/app/theme_scope.dart';
import 'package:hydrowin/core/theme/theme_controller.dart';
import 'package:hydrowin/data/demo/demo_fleet_data.dart';
import 'package:hydrowin/data/local/app_preferences.dart';
import 'package:hydrowin/data/local/developer_settings_repository.dart';
import 'package:hydrowin/data/local/fleet_registry_repository.dart';
import 'package:hydrowin/data/local/network_settings_repository.dart';
import 'package:hydrowin/data/local/server_config_service.dart';
import 'package:hydrowin/data/local/token_storage.dart';
import 'package:hydrowin/data/notifications/alert_notification_service.dart';
import 'package:hydrowin/data/remote/api_client.dart';
import 'package:hydrowin/data/remote/auth_repository.dart';
import 'package:hydrowin/data/remote/events_repository.dart';
import 'package:hydrowin/data/remote/machines_repository.dart';
import 'package:hydrowin/data/remote/notifications_repository.dart';
import 'package:hydrowin/data/remote/organizations_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  initAppRouter();

  final alerts = AlertNotificationService();
  if (!kIsWeb) {
    await alerts.init();
  }

  final prefs = await AppPreferences.create();
  final themeController = ThemeController(prefs);
  final tokens = TokenStorage();

  // Восстановить демо-флаг после перезапуска, если осталась demo-сессия.
  final access = await tokens.getAccessToken();
  if (access != null && access.startsWith('demo-')) {
    DemoSession.start();
  }

  final devRepo = await DeveloperSettingsRepository.create();
  final netRepo = await NetworkSettingsRepository.create();
  final fleetRepo = await FleetRegistryRepository.create();
  final serverConfig = ServerConfigService(devRepo);
  final api = ApiClient(tokens, baseUrl: serverConfig.resolveApiBaseUrl());
  final auth = AuthRepository(api, tokens);
  final machines = MachinesRepository(api, fleetRegistry: fleetRepo);
  final organizations = OrganizationsRepository(
    (path, {query}) => api.get(path, query: query),
    (path, {body}) => api.post(path, body: body, auth: true),
    (path, {body}) => api.put(path, body: body, auth: true),
    (path) => api.delete(path),
  );
  final events = EventsRepository(api);
  final notifications = NotificationsRepository(api);
  final notificationCenter = NotificationCenter(alerts: alerts);

  // CloudScope нужен и в Lite: демо завода использует те же экраны парка.
  final root = await AppScope.wrap(
    ThemeScope(
      controller: themeController,
      child: NotificationScope(
        center: notificationCenter,
        child: CloudScope(
          auth: auth,
          machines: machines,
          organizations: organizations,
          events: events,
          notifications: notifications,
          tokens: tokens,
          serverConfig: serverConfig,
          developerSettings: devRepo,
          networkSettings: netRepo,
          api: api,
          child: const HydroWinApp(),
        ),
      ),
    ),
    machines: machines,
    alerts: alerts,
  );

  runApp(root);
}
