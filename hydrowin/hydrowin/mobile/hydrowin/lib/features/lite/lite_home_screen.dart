import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hydrowin/app/cloud_scope.dart';
import 'package:hydrowin/core/constants/app_constants.dart';
import 'package:hydrowin/data/demo/demo_fleet_data.dart';
import 'package:hydrowin/data/local/app_preferences.dart';
import 'package:hydrowin/widgets/brand_logo.dart';

/// Стартовый экран Lite: Bluetooth или демо завода (полный UI).
class LiteHomeScreen extends StatelessWidget {
  const LiteHomeScreen({super.key});

  Future<void> _openFactoryDemo(BuildContext context) async {
    final scope = CloudScope.of(context);
    await scope.auth.loginDemo();
    final prefs = await AppPreferences.create();
    await prefs.setWorkMode(AppConstants.workModeFleet);
    await prefs.setFirstLaunchDone();
    if (!context.mounted) return;
    context.go('/fleet');
  }

  Future<void> _continueDemo(BuildContext context) async {
    final prefs = await AppPreferences.create();
    await prefs.setWorkMode(AppConstants.workModeFleet);
    if (!context.mounted) return;
    context.go('/fleet');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final demoActive = DemoSession.isActive;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppConstants.appName),
        actions: [
          IconButton(
            tooltip: 'Настройки',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          const Center(child: BrandLogo(size: 96)),
          const SizedBox(height: 12),
          Text(
            'Локальная диагностика',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            'Работает без интернета. Подключите блок по Bluetooth — '
            'показания только на этом устройстве.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 28),
          _ModeCard(
            icon: Icons.bluetooth_searching,
            title: 'Подключить блок',
            subtitle: 'Без интернета · скан HydroWin… · живые датчики',
            color: scheme.primary,
            onTap: () => context.go('/ble/connect'),
          ),
          if (AppConstants.demoAvailable) ...[
            const SizedBox(height: 12),
            if (demoActive)
              _ModeCard(
                icon: Icons.play_circle_outline,
                title: 'Продолжить демо завода',
                subtitle: 'Вернуться в учебный парк',
                color: scheme.tertiary,
                onTap: () => _continueDemo(context),
              )
            else
              _ModeCard(
                icon: Icons.factory_outlined,
                title: 'Демо завода',
                subtitle:
                    'Учебный парк офлайн · графики и уведомления без сервера',
                color: scheme.tertiary,
                onTap: () => _openFactoryDemo(context),
              ),
          ],
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withValues(alpha: 0.45)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.15),
                foregroundColor: color,
                child: Icon(icon),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
