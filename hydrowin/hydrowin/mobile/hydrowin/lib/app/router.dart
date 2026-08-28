import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:hydrowin/features/admin/create_driver_screen.dart';
import 'package:hydrowin/features/admin/create_factory_screen.dart';
import 'package:hydrowin/features/admin/create_manufacturer_screen.dart';
import 'package:hydrowin/features/admin/manage_orgs_screen.dart';
import 'package:hydrowin/features/admin/manage_users_screen.dart';
import 'package:hydrowin/features/admin/register_board_screen.dart';
import 'package:hydrowin/features/auth/login_screen.dart';
import 'package:hydrowin/features/ble/connect_block_ble_screen.dart';
import 'package:hydrowin/features/fleet/cloud_machine_detail_screen.dart';
import 'package:hydrowin/features/fleet/cloud_machine_thresholds_screen.dart';
import 'package:hydrowin/features/fleet/cloud_sensor_day_chart_screen.dart';
import 'package:hydrowin/features/fleet/cloud_thresholds_picker_screen.dart';
import 'package:hydrowin/features/chart/chart_time_range.dart';
import 'package:hydrowin/features/fleet/fleet_list_screen.dart';
import 'package:hydrowin/features/fleet/fleet_map_screen.dart';
import 'package:hydrowin/features/chart/sensor_chart_screen.dart';
import 'package:hydrowin/features/fleet/single_machine_setup_screen.dart';
import 'package:hydrowin/features/lite/lite_home_screen.dart';
import 'package:hydrowin/features/machine/machine_detail_screen.dart';
import 'package:hydrowin/features/onboarding/mode_select_screen.dart';
import 'package:hydrowin/features/onboarding/sensor_setup_screen.dart';
import 'package:hydrowin/features/notifications/notifications_hub_screen.dart';
import 'package:hydrowin/features/notifications/notification_prefs_screen.dart';
import 'package:hydrowin/features/settings/network_settings_screen.dart';
import 'package:hydrowin/features/settings/profile_screen.dart';
import 'package:hydrowin/features/settings/service_fault_journal_screen.dart';
import 'package:hydrowin/features/settings/settings_screen.dart';
import 'package:hydrowin/features/splash/splash_screen.dart';
import 'package:hydrowin/app/app_scope.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

GoRouter createAppRouter() {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/lite', builder: (_, _) => const LiteHomeScreen()),
      GoRoute(
        path: '/lite/demo',
        redirect: (_, _) => '/lite',
      ),
      GoRoute(path: '/mode', builder: (_, _) => const ModeSelectScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: '/sensors/setup',
        builder: (context, state) {
          final from = state.uri.queryParameters['from'] ?? 'mode';
          return SensorSetupScreen(returnTo: from);
        },
      ),
      GoRoute(
        path: '/sensors/thresholds',
        builder: (_, _) => const CloudThresholdsPickerScreen(),
      ),
      GoRoute(
        path: '/sensors/thresholds/:machineId',
        builder: (context, state) {
          return CloudMachineThresholdsScreen(
            machineId: state.pathParameters['machineId']!,
            focusSensorId: state.uri.queryParameters['focus'],
          );
        },
      ),
      GoRoute(
        path: '/single/setup',
        builder: (_, _) => const SingleMachineSetupScreen(),
      ),
      GoRoute(
        path: '/machine',
        builder: (_, _) => const MachineDetailScreen(),
      ),
      GoRoute(
        path: '/chart/:channel',
        builder: (context, state) {
          final raw = state.pathParameters['channel']!;
          final channel = int.tryParse(raw);
          final configs = AppScope.of(context).configs;
          final config = configs
              .where((c) => c.channelIndex == channel)
              .firstOrNull;

          if (config == null) {
            return const Scaffold(
              body: Center(child: Text('Конфигурация датчика не найдена')),
            );
          }
          return SensorChartScreen(config: config);
        },
      ),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(
        path: '/settings/profile',
        builder: (_, _) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/settings/service-journal',
        builder: (_, _) => const ServiceFaultJournalScreen(),
      ),
      GoRoute(
        path: '/ble/connect',
        builder: (_, _) => const ConnectBlockBleScreen(),
      ),
      GoRoute(
        path: '/settings/network',
        builder: (_, _) => const NetworkSettingsScreen(),
      ),
      // Старый путь «режим разработчика» → единый экран настройки блока/сети.
      GoRoute(
        path: '/settings/developer',
        redirect: (_, _) => '/settings/network',
      ),
      GoRoute(
        path: '/admin/manufacturer',
        builder: (_, _) => const CreateManufacturerScreen(),
      ),
      GoRoute(
        path: '/admin/factory',
        builder: (_, _) => const CreateFactoryScreen(),
      ),
      GoRoute(
        path: '/admin/driver',
        builder: (_, _) => const CreateDriverScreen(),
      ),
      GoRoute(
        path: '/admin/register-board',
        builder: (_, _) => const RegisterBoardScreen(),
      ),
      GoRoute(
        path: '/admin/users',
        builder: (_, _) => const ManageUsersScreen(),
      ),
      GoRoute(
        path: '/admin/orgs',
        builder: (_, _) => const ManageOrgsScreen(),
      ),
      GoRoute(path: '/fleet', builder: (_, _) => const FleetListScreen()),
      GoRoute(path: '/fleet/map', builder: (_, _) => const FleetMapScreen()),
      GoRoute(
        path: '/notifications',
        builder: (_, _) => const NotificationsHubScreen(),
      ),
      GoRoute(
        path: '/notifications/prefs',
        builder: (_, _) => const NotificationPrefsScreen(),
      ),
      GoRoute(
        path: '/cloud/machine/:machineId/sensor/:sensorId/day',
        builder: (context, state) {
          final extra = state.extra;
          return CloudSensorDayChartScreen(
            machineId: state.pathParameters['machineId']!,
            sensorId: state.pathParameters['sensorId']!,
            initialRange: extra is ChartTimeRange ? extra : null,
          );
        },
      ),
      GoRoute(
        path: '/cloud/machine/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return CloudMachineDetailScreen(machineId: id);
        },
      ),
    ],
  );
}

GoRouter? _appRouter;

GoRouter get appRouter => _appRouter ??= createAppRouter();

// ИСПРАВЛЕНИЕ: убран параметр [Object? _] — он не использовался,
// но main.dart передавал tokens, что вызывало ошибку типов.
// Функция теперь без параметров — router не зависит от TokenStorage.
void initAppRouter() {
  _appRouter ??= createAppRouter();
}
