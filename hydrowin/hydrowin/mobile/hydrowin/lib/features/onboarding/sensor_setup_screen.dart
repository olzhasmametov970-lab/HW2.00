import 'package:flutter/material.dart';
import 'package:hydrowin/app/app_scope.dart';
import 'package:hydrowin/app/cloud_scope.dart';
import 'package:hydrowin/core/constants/app_constants.dart';
import 'package:hydrowin/domain/models/sensor_config.dart';
import 'package:hydrowin/domain/models/sensor_type.dart';
import 'package:hydrowin/features/onboarding/widgets/sensor_config_editor.dart';
import 'package:go_router/go_router.dart';

class SensorSetupScreen extends StatefulWidget {
  const SensorSetupScreen({this.returnTo = 'mode', super.key});

  /// Откуда открыли: settings | mode | machine | ble
  final String returnTo;

  @override
  State<SensorSetupScreen> createState() => _SensorSetupScreenState();
}

class _SensorSetupScreenState extends State<SensorSetupScreen> {
  late List<SensorConfig> _configs;
  bool _loading = true;
  /// GPIO / ADC подсказки — только админ платформы.
  bool _showHardwareHints = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final session = AppScope.of(context);
    // В демо и в Lite не показываем GPIO/ADC — это для платформенной настройки платы.
    var showHints = false;
    if (!AppConstants.isLite && !session.isDemo) {
      try {
        final scope = CloudScope.maybeOf(context);
        if (scope != null) {
          final admin = await scope.auth.isAdmin();
          if (admin) {
            final me = await scope.organizations.fetchMe();
            showHints = me.isPlatform;
          }
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _configs = _normalizeHardwareChannels(session.configs);
      _showHardwareHints = showHints;
      _loading = false;
    });
  }

  List<SensorConfig> _normalizeHardwareChannels(List<SensorConfig> source) {
    final byChannel = {
      for (final config in source) config.channelIndex: config,
    };
    return List.generate(AppConstants.hardwareAnalogChannels, (channel) {
      return (byChannel[channel] ??
              SensorConfig.defaults(
                channel,
                channel == 0 ? SensorType.pressure : SensorType.temperature,
              ))
          .repairThresholds();
    });
  }

  String get _fallbackHome =>
      AppConstants.isLite ? '/lite' : '/fleet';

  void _exitWithoutSaving() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(_fallbackHome);
  }

  Future<void> _goMainMenu() async {
    if (!mounted) return;
    context.go(_fallbackHome);
  }

  void _goAfterSave() {
    if (widget.returnTo == 'settings' ||
        widget.returnTo == 'ble' ||
        widget.returnTo == 'lite') {
      if (context.canPop()) {
        context.pop();
        return;
      }
    }
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(_fallbackHome);
  }

  Future<void> _save() async {
    final repaired = _normalizeHardwareChannels(_configs);

    for (final c in repaired.where((c) => c.enabled)) {
      final err = c.validate();
      if (err != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${c.name}: $err')),
        );
        return;
      }
    }

    final session = AppScope.of(context);
    await session.saveConfigs(repaired);
    if (!mounted) return;
    _goAfterSave();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final enabledCount = _configs.where((c) => c.enabled).length;
    final session = AppScope.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitWithoutSaving();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: BackButton(
            onPressed: _exitWithoutSaving,
          ),
          title: Text(
            AppConstants.isLite && session.deviceLabel != null
                ? 'Каналы · ${session.deviceLabel}'
                : 'Живые каналы (BLE)',
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  _goMainMenu();
                }
              },
              child: const Text('В МЕНЮ'),
            ),
          ],
        ),
        body: Column(
          children: [
            if (AppConstants.isLite)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  session.deviceLabel != null || session.bleDeviceKey != null
                      ? 'Настройки сохраняются для текущего блока. '
                            'У другой платы свой набор каналов.'
                      : 'Сначала подключите блок по Bluetooth — иначе сохранение '
                            'пойдёт в общий набор телефона.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (_showHardwareHints)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Аппаратные каналы блока: '
                      '${AppConstants.hardwareAnalogChannels} '
                      '(CH0–CH5, только ADC1)\n'
                      'GPIO: ${AppConstants.adc1GpioPins.join(', ')}',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Включено: $enabledCount из '
                      '${AppConstants.hardwareAnalogChannels}. '
                      'Все входы на ADC1 — стабильно с Wi‑Fi.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _configs.length,
                itemBuilder: (context, i) {
                  return SensorConfigEditor(
                    key: ValueKey(
                      'sensor-$i-${_configs[i].type.name}-${_configs[i].enabled}',
                    ),
                    index: i,
                    config: _configs[i],
                    showHardwareHints: _showHardwareHints,
                    showEnabledToggle: true,
                    onChanged: (c) => setState(
                      () => _configs[i] = c.repairThresholds(),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              minimum: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _exitWithoutSaving,
                      child: const Text('ВЫЙТИ'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _save,
                      child: const Text('СОХРАНИТЬ'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
