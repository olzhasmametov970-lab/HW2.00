import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:hydrowin/data/local/app_preferences.dart';
import 'package:hydrowin/data/local/readings_repository.dart';
import 'package:hydrowin/data/local/sensor_config_repository.dart';
import 'package:hydrowin/data/local/service_fault_journal.dart';
import 'package:hydrowin/data/notifications/alert_notification_service.dart';
import 'package:hydrowin/data/remote/machines_repository.dart';
import 'package:hydrowin/data/telemetry/telemetry_session.dart';

class AppScope extends InheritedNotifier<TelemetrySession> {
  const AppScope({
    required this.readings,
    required this.machines,
    required this.faultJournal,
    required super.notifier,
    required super.child,
    super.key,
  });

  final ReadingsRepository readings;
  final MachinesRepository? machines;
  final ServiceFaultJournal faultJournal;

  static TelemetrySession of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found');
    return scope!.notifier!;
  }

  static ReadingsRepository readingsOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found');
    return scope!.readings;
  }

  static ServiceFaultJournal faultJournalOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found');
    return scope!.faultJournal;
  }

  static MachinesRepository? machinesOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AppScope>()
        ?.machines;
  }

  static Future<AppScope> wrap(
    Widget child, {
    bool initNotifications = true,
    MachinesRepository? machines,
    AlertNotificationService? alerts,
  }) async {
    final sensorRepo = await SensorConfigRepository.create();
    final readingsRepo = await ReadingsRepository.create();
    final faultJournal = await ServiceFaultJournal.create();
    final preferences = await AppPreferences.create();
    await readingsRepo.purgeOlderThanRetention();
    await faultJournal.purgeOlderThanRetention();

    final alertService = alerts ?? AlertNotificationService();
    if (initNotifications && !kIsWeb && alerts == null) {
      await alertService.init();
    }

    final session = TelemetrySession(
      sensorRepo,
      readingsRepo,
      alertService,
      machines: machines,
      preferences: preferences,
      faultJournal: faultJournal,
    );
    await session.loadConfigs();

    return AppScope(
      readings: readingsRepo,
      machines: machines,
      faultJournal: faultJournal,
      notifier: session,
      child: child,
    );
  }
}
