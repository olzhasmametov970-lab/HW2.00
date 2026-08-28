import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hydrowin/app/app_scope.dart';
import 'package:hydrowin/app/cloud_scope.dart';
import 'package:hydrowin/core/api/session_expired_exception.dart';
import 'package:hydrowin/core/constants/app_constants.dart';
import 'package:hydrowin/domain/models/cloud_sensor.dart';
import 'package:hydrowin/domain/models/machine_summary.dart';
import 'package:hydrowin/features/onboarding/widgets/sensor_config_editor.dart';
import 'package:go_router/go_router.dart';

/// Облачные пороги датчиков одной машины.
class CloudMachineThresholdsScreen extends StatefulWidget {
  const CloudMachineThresholdsScreen({
    required this.machineId,
    this.focusSensorId,
    super.key,
  });

  final String machineId;
  final String? focusSensorId;

  @override
  State<CloudMachineThresholdsScreen> createState() =>
      _CloudMachineThresholdsScreenState();
}

class _CloudMachineThresholdsScreenState
    extends State<CloudMachineThresholdsScreen> {
  MachineSummary? _machine;
  List<CloudSensor> _sensors = [];
  final Map<String, GlobalKey> _sensorKeys = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _isAdmin = false;

  bool get _canEdit =>
      _isAdmin && (_machine?.canConfigure ?? false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final scope = CloudScope.of(context);
    try {
      final admin = await scope.auth.isAdmin();
      final results = await Future.wait([
        scope.machines.getMachine(widget.machineId),
        scope.machines.listSensors(widget.machineId),
      ]);
      if (!mounted) return;
      final machine = results[0] as MachineSummary?;
      final sensors = results[1] as List<CloudSensor>;
      for (final s in sensors) {
        _sensorKeys.putIfAbsent(s.id, GlobalKey.new);
      }
      setState(() {
        _isAdmin = admin;
        _machine = machine;
        _sensors = sensors;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToFocus());
    } catch (e) {
      if (!mounted) return;
      if (e is SessionExpiredException) {
        context.go('/login');
        return;
      }
      setState(() {
        _error = scope.auth.humanizeError(e);
        _loading = false;
      });
    }
  }

  void _scrollToFocus() {
    final id = widget.focusSensorId;
    if (id == null) return;
    final key = _sensorKeys[id];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 300),
      alignment: 0.1,
    );
  }

  Future<void> _save() async {
    if (!_canEdit) return;
    for (final s in _sensors) {
      final err = s.config.validate();
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${s.config.name}: $err')),
        );
        return;
      }
    }

    setState(() => _saving = true);
    final scope = CloudScope.of(context);
    try {
      final updated = await scope.machines.updateSensors(
        widget.machineId,
        _sensors,
      );
      if (!mounted) return;
      if (updated == null) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось сохранить пороги на сервере'),
          ),
        );
        return;
      }
      setState(() {
        _sensors = updated;
        _saving = false;
      });
      // Локальный BLE / сессия используют те же пороги.
      try {
        await AppScope.of(context).applyCloudConfigs(
          updated.map((s) => s.config).toList(),
          machineId: widget.machineId,
        );
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пороги сохранены')),
      );
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(scope.auth.humanizeError(e))),
      );
    }
  }

  String get _machineKey => _machine?.id ?? widget.machineId;

  Future<void> _addSensor() async {
    if (!_canEdit) return;
    final scope = CloudScope.of(context);
    List<Map<String, dynamic>> catalog;
    try {
      catalog = await scope.machines.fetchSensorCatalog();
    } catch (_) {
      catalog = [
        {'type': 'pressure', 'name': 'Давление'},
        {'type': 'temperature', 'name': 'Температура'},
        {'type': 'flow', 'name': 'Расход'},
        {'type': 'level', 'name': 'Уровень'},
        {'type': 'vibration', 'name': 'Вибрация'},
      ];
    }
    if (!mounted) return;

    final occupied = _sensors.map((s) => s.config.channelIndex).toSet();
    final freeChannels = [
      for (var ch = 0; ch < AppConstants.hardwareAnalogChannels; ch++)
        if (!occupied.contains(ch)) ch,
    ];
    if (freeChannels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'До 6 каналов (CH0–CH5). Все уже заняты.',
          ),
        ),
      );
      return;
    }

    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Добавить датчик'),
        children: [
          for (final item in catalog)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, item),
              child: Text('${item['name'] ?? item['type']}'),
            ),
        ],
      ),
    );
    if (selected == null || !mounted) return;

    var channel = freeChannels.first;
    if (freeChannels.length > 1) {
      final picked = await showDialog<int>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Канал на плате'),
          children: [
            for (final ch in freeChannels)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, ch),
                child: Text('Канал №${ch + 1} (CH$ch)'),
              ),
          ],
        ),
      );
      if (picked == null || !mounted) return;
      channel = picked;
    }

    setState(() => _saving = true);
    try {
      final created = await scope.machines.addSensor(
        _machineKey,
        type: selected['type'] as String,
        name: selected['name'] as String?,
        channelIndex: channel,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      if (created == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось добавить датчик')),
        );
        return;
      }
      await Clipboard.setData(ClipboardData(text: 'ENABLE $channel'));
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Добавлен канал ${channel + 1}. На плате: ENABLE $channel',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(scope.auth.humanizeError(e))),
      );
    }
  }

  Future<void> _deleteSensor(CloudSensor sensor) async {
    if (!_canEdit) return;
    final ch = sensor.config.channelIndex;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Убрать датчик?'),
        content: Text(
          '«${sensor.config.name}» (канал ${ch + 1}) удалится в облаке '
          'у всех пользователей вместе с историей.\n\n'
          'На плате: DISABLE $ch',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await CloudScope.of(context).machines.deleteSensor(
        _machineKey,
        sensor.id,
      );
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: 'DISABLE $ch'));
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Удалён. На плате: DISABLE $ch')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(CloudScope.of(context).auth.humanizeError(e)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _machine == null
        ? 'Пороги датчиков'
        : '${_machine!.code} · пороги';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (_canEdit)
            TextButton(
              onPressed: _saving || _loading ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Сохранить'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  ),
                )
              : _sensors.isEmpty
                  ? const Center(
                      child: Text('У машины пока нет датчиков в облаке'),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      children: [
                        Text(
                          _canEdit
                              ? 'Норма и пороги сохраняются в облако для всех. '
                                  'Тумблер «канал включён», добавление и удаление — '
                                  'только администратор.'
                              : 'Только просмотр: у вашей организации нет '
                                  'права менять пороги этой машины.',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                        if (_machine != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${_machine!.name} · ${_machine!.locationLabel}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 16),
                        if (_canEdit)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FilledButton.icon(
                              onPressed: _saving ? null : _addSensor,
                              icon: const Icon(Icons.add),
                              label: const Text('Добавить датчик'),
                            ),
                          ),
                        if (_canEdit) const SizedBox(height: 12),
                        for (var i = 0; i < _sensors.length; i++)
                          KeyedSubtree(
                            key: _sensorKeys[_sensors[i].id],
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SensorConfigEditor(
                                  index: _sensors[i].config.channelIndex,
                                  config: _sensors[i].config,
                                  showHardwareHints: false,
                                  showEnabledToggle: _canEdit,
                                  readOnly: !_canEdit,
                                  onChanged: (c) {
                                    setState(() {
                                      _sensors[i] = CloudSensor(
                                        id: _sensors[i].id,
                                        config: c.repairThresholds(),
                                      );
                                    });
                                  },
                                ),
                                if (_canEdit)
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: _saving
                                          ? null
                                          : () => _deleteSensor(_sensors[i]),
                                      icon: const Icon(Icons.delete_outline),
                                      label: const Text('Удалить датчик'),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        if (_canEdit) ...[
                          const SizedBox(height: 8),
                          FilledButton(
                            onPressed: _saving ? null : _save,
                            child: const Text('СОХРАНИТЬ'),
                          ),
                        ],
                      ],
                    ),
    );
  }
}
