import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hydrowin/app/app_scope.dart';
import 'package:hydrowin/data/demo/lite_demo_fleet.dart';
import 'package:hydrowin/domain/models/machine_summary.dart';
import 'package:hydrowin/features/fleet/widgets/machine_list_tile.dart';
import 'package:hydrowin/features/fleet/widgets/machine_status_chip.dart';

/// Локальный демо-парк машин для Lite.
class LiteDemoFleetScreen extends StatelessWidget {
  const LiteDemoFleetScreen({super.key});

  Future<void> _openMachine(BuildContext context, LiteDemoMachine machine) async {
    final session = AppScope.of(context);
    await session.startLiteDemo(machine);
    if (!context.mounted) return;
    context.push('/machine');
  }

  @override
  Widget build(BuildContext context) {
    final data = LiteDemoFleet.asListResponse();
    final scheme = Theme.of(context).colorScheme;
    final totals = data.totals;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Демо-парк'),
        leading: BackButton(onPressed: () => context.go('/lite')),
        actions: [
          IconButton(
            tooltip: 'Настройки',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'Учебные машины без Bluetooth и сервера. Откройте любую — '
            'увидите датчики, статусы и настройки как в реальном режиме.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatChip(label: 'Все ${totals.total}', color: scheme.primary),
              _StatChip(
                label: 'Норма ${totals.ok}',
                color: machineStatusColor(MachineStatus.ok, scheme),
              ),
              _StatChip(
                label: 'Внимание ${totals.warning}',
                color: machineStatusColor(MachineStatus.warning, scheme),
              ),
              _StatChip(
                label: 'Критично ${totals.critical}',
                color: machineStatusColor(MachineStatus.critical, scheme),
              ),
              _StatChip(
                label: 'Офлайн ${totals.offline}',
                color: machineStatusColor(MachineStatus.offline, scheme),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...LiteDemoFleet.machines.map(
            (m) => MachineListTile(
              machine: m.toSummary(),
              onTap: () => _openMachine(context, m),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => context.go('/ble/connect'),
            icon: const Icon(Icons.bluetooth),
            label: const Text('Перейти к реальному Bluetooth'),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      side: BorderSide(color: color.withValues(alpha: 0.55)),
      backgroundColor: color.withValues(alpha: 0.12),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
      visualDensity: VisualDensity.compact,
    );
  }
}
