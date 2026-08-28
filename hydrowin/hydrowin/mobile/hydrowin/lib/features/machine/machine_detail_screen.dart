import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hydrowin/app/app_scope.dart';
import 'package:hydrowin/app/cloud_scope.dart';
import 'package:hydrowin/core/constants/app_constants.dart';
import 'package:hydrowin/core/theme/hw_colors.dart';
import 'package:hydrowin/data/local/app_preferences.dart';
import 'package:hydrowin/data/local/fleet_registry_repository.dart';
import 'package:hydrowin/data/telemetry/telemetry_session.dart';
import 'package:hydrowin/features/machine/widgets/sensor_card.dart';
import 'package:intl/intl.dart';

class MachineDetailScreen extends StatefulWidget {
  const MachineDetailScreen({super.key});

  @override
  State<MachineDetailScreen> createState() => _MachineDetailScreenState();
}

class _MachineDetailScreenState extends State<MachineDetailScreen> {
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final session = AppScope.of(context);
    final prefs = await AppPreferences.create();
    if (AppConstants.isLite) {
      if (mounted) setState(() => _isAdmin = true);
      return;
    }
    try {
      final admin = await CloudScope.maybeOf(context)?.auth.isAdmin() ?? false;
      if (mounted) setState(() => _isAdmin = admin);
    } catch (_) {}
    if (!mounted) return;

    final mode = prefs.workMode;
    if (mode == AppConstants.workModeSingle) {
      final machineId = prefs.singleMachineId;
      if (machineId == null) {
        context.go('/single/setup');
        return;
      }
      final repo = await FleetRegistryRepository.create();
      final entry = await repo.findById(machineId);
      if (entry == null) {
        context.go('/single/setup');
        return;
      }
      await session.startServerPolling(
        machineId: entry.serverId ?? entry.id,
        label: '${entry.displayCode} · ${entry.name}',
      );
    }
  }

  Future<void> _refresh() async {
    final session = AppScope.of(context);
    if (session.isDemo) {
      final machine = session.demoMachine;
      if (machine != null) {
        await session.startLiteDemo(machine);
      }
      return;
    }
    final prefs = await AppPreferences.create();
    if (!mounted) return;

    if (prefs.workMode == AppConstants.workModeSingle) {
      final machineId = prefs.singleMachineId;
      if (machineId == null) return;
      final repo = await FleetRegistryRepository.create();
      final entry = await repo.findById(machineId);
      if (entry == null) return;
      await session.startServerPolling(
        machineId: entry.serverId ?? entry.id,
        label: '${entry.displayCode} · ${entry.name}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    final timeFmt = DateFormat.Hms();

    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final connLabel = switch (session.mode) {
          TelemetryConnectionMode.connected =>
            'Bluetooth: ${session.deviceLabel ?? "подключено"}',
          TelemetryConnectionMode.server =>
            'Сервер: ${session.deviceLabel ?? "подключено"}',
          TelemetryConnectionMode.demo =>
            'Демо: ${session.deviceLabel ?? "парк"}',
          TelemetryConnectionMode.connecting => 'Подключение…',
          _ => 'Нет данных',
        };
        final connIcon = session.isLive
            ? (session.mode == TelemetryConnectionMode.connected
                ? Icons.bluetooth_connected
                : session.mode == TelemetryConnectionMode.demo
                    ? Icons.science_outlined
                    : Icons.cloud_done)
            : Icons.cloud_off;
        final connColor = session.isLive ? HwColors.ok : HwColors.offline;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              session.deviceLabel ??
                  (session.isDemo ? 'Демо-машина' : 'Моя машина'),
            ),
            leading: session.isDemo
                ? BackButton(onPressed: () => context.go('/lite/demo'))
                : null,
            actions: [
              if (_isAdmin)
                IconButton(
                  tooltip: 'Настройки',
                  icon: const Icon(Icons.settings),
                  onPressed: () => context.push('/settings'),
                ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(connIcon, color: connColor),
                  title: Text(connLabel),
                  subtitle: session.lastPacketAt != null
                      ? Text(
                          'Обновлено: ${timeFmt.format(session.lastPacketAt!)}',
                        )
                      : const Text('Живые шкалы · сводка в шторке уведомлений'),
                ),
                if (session.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      session.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                Text('ДАТЧИКИ', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                ...session.configs.map((config) {
                  if (!config.enabled) return const SizedBox.shrink();
                  return SensorCard(
                    config: config,
                    reading: session.readings[config.channelIndex],
                  );
                }),
                if (!session.isLive)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: FilledButton(
                      onPressed: _refresh,
                      child: const Text('Обновить'),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
