import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hydrowin/app/cloud_scope.dart';
import 'package:hydrowin/app/notification_center.dart';
import 'package:hydrowin/domain/models/machine_summary.dart';

/// Фоновый опрос парка → side toast только при critical (авария).
/// Учитывает тумблер «Push в приложении» из каналов оповещений.
class FleetAlertMonitor extends StatefulWidget {
  const FleetAlertMonitor({required this.child, super.key});

  final Widget child;

  @override
  State<FleetAlertMonitor> createState() => _FleetAlertMonitorState();
}

class _FleetAlertMonitorState extends State<FleetAlertMonitor> {
  Timer? _timer;
  bool _running = false;
  DateTime? _prefsLoadedAt;
  bool _pushEnabled = true;
  static const _prefsTtl = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _arm());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _arm() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 12), (_) => _tick());
    _tick();
  }

  Future<void> _refreshPushPref() async {
    final now = DateTime.now();
    if (_prefsLoadedAt != null &&
        now.difference(_prefsLoadedAt!) < _prefsTtl) {
      return;
    }
    try {
      final cloud = CloudScope.of(context);
      final settings = await cloud.notifications.getSettings();
      if (!mounted) return;
      _pushEnabled = settings.critical.push;
      _prefsLoadedAt = now;
      NotificationScope.of(context).setPushEnabled(_pushEnabled);
    } catch (_) {
      // При ошибке сети оставляем последнее известное значение.
    }
  }

  Future<void> _tick() async {
    if (!mounted || _running) return;
    final cloud = CloudScope.of(context);
    final center = NotificationScope.of(context);
    if (await cloud.tokens.getAccessToken() == null) return;

    _running = true;
    try {
      await _refreshPushPref();
      if (!mounted) return;

      // Источник истины — NotificationCenter (prefs обновляют его сразу).
      if (!center.pushEnabled) {
        return;
      }

      final data = await cloud.machines.listMachines();
      if (!mounted) return;
      for (final MachineSummary m in data.items) {
        center.observeMachineStatus(
          machineId: m.id,
          code: m.code,
          name: m.name,
          statusName: m.status.name,
          headline: m.headlineAlert,
        );
      }
    } catch (_) {
      // тихо — монитор не должен ломать UI
    } finally {
      _running = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
