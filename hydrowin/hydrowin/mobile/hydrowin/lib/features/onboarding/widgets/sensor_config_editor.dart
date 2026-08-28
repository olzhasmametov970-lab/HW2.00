import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hydrowin/core/constants/app_constants.dart';
import 'package:hydrowin/domain/models/sensor_config.dart';
import 'package:hydrowin/domain/models/sensor_type.dart';

class SensorConfigEditor extends StatefulWidget {
  const SensorConfigEditor({
    required this.index,
    required this.config,
    required this.onChanged,
    this.showHardwareHints = false,
    this.showEnabledToggle = true,
    this.readOnly = false,
    super.key,
  });

  final int index;
  final SensorConfig config;
  final ValueChanged<SensorConfig> onChanged;

  /// GPIO / ADC подписи — только админ платформы.
  final bool showHardwareHints;

  /// Локальный BLE: вкл/выкл канала. В облаке обычно скрыто.
  final bool showEnabledToggle;

  final bool readOnly;

  @override
  State<SensorConfigEditor> createState() => _SensorConfigEditorState();
}

class _SensorConfigEditorState extends State<SensorConfigEditor> {
  late TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.config.name);
  }

  @override
  void didUpdateWidget(SensorConfigEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.type != widget.config.type ||
        oldWidget.config.name != widget.config.name) {
      if (_nameCtrl.text != widget.config.name) {
        _nameCtrl.text = widget.config.name;
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  bool get _fieldsEnabled =>
      !widget.readOnly && (widget.showEnabledToggle ? widget.config.enabled : true);

  void _emit(SensorConfig next) {
    if (widget.readOnly) return;
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Канал №${config.channelIndex + 1}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (widget.showHardwareHints) ...[
              const SizedBox(height: 4),
              Text(
                'Аппаратный вход: GPIO${AppConstants.gpioForChannel(config.channelIndex)} '
                '(CH${config.channelIndex}, ADC1)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (widget.showEnabledToggle) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Канал включён'),
                subtitle: Text(
                  config.enabled
                      ? 'Канал участвует в мониторинге и отправке'
                      : 'Канал выключен и скрыт из мониторинга',
                ),
                value: config.enabled,
                onChanged: widget.readOnly
                    ? null
                    : (v) => _emit(config.copyWith(enabled: v)),
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Название',
                border: OutlineInputBorder(),
              ),
              controller: _nameCtrl,
              enabled: _fieldsEnabled,
              onChanged: (v) => _emit(config.copyWith(name: v)),
            ),
            const SizedBox(height: 12),
            Text('Тип', style: Theme.of(context).textTheme.labelLarge),
            ...SensorType.values.map(
              (t) => RadioListTile<SensorType>(
                title: Text(t.label),
                subtitle: Text(t.unit),
                value: t,
                groupValue: config.type,
                onChanged: !_fieldsEnabled
                    ? null
                    : (v) {
                        if (v == null) return;
                        final next = SensorConfig.defaults(
                          config.channelIndex,
                          v,
                        ).copyWith(
                          name: _nameCtrl.text,
                          enabled: config.enabled,
                        );
                        _emit(next);
                      },
              ),
            ),
            _NumField(
              key: ValueKey('${config.channelIndex}-min'),
              label: 'Мин. шкала (${config.unit})',
              initial: config.scaleMin,
              enabled: _fieldsEnabled,
              onSubmitted: (v) => _emit(config.copyWith(scaleMin: v)),
            ),
            _NumField(
              key: ValueKey('${config.channelIndex}-max'),
              label: 'Макс. шкала (${config.unit})',
              initial: config.scaleMax,
              enabled: _fieldsEnabled,
              onSubmitted: (v) => _emit(config.copyWith(scaleMax: v)),
            ),
            if (config.type != SensorType.temperature)
              _NumField(
                key: ValueKey('${config.channelIndex}-normMin'),
                label: 'Норма от (${config.unit})',
                initial: config.normMin ?? config.scaleMin,
                enabled: _fieldsEnabled,
                onSubmitted: (v) {
                  var next = config.copyWith(normMin: v);
                  if (next.criticalLow != null && next.criticalLow! >= v) {
                    next = next.copyWith(criticalLow: v - 1);
                  }
                  _emit(next.repairThresholds());
                },
              ),
            _NumField(
              key: ValueKey('${config.channelIndex}-normMax'),
              label: 'Норма до (${config.unit})',
              initial: config.normMax,
              enabled: _fieldsEnabled,
              onSubmitted: (v) => _emit(config.copyWith(normMax: v)),
            ),
            if (config.criticalLow != null ||
                config.type == SensorType.pressure)
              _NumField(
                key: ValueKey('${config.channelIndex}-critLo'),
                label: 'Критично ниже (${config.unit})',
                initial: config.criticalLow ?? 0,
                enabled: _fieldsEnabled,
                onSubmitted: (v) => _emit(
                  config.copyWith(criticalLow: v).repairThresholds(),
                ),
              ),
            _NumField(
              key: ValueKey('${config.channelIndex}-critHi'),
              label: 'Критично выше (${config.unit})',
              initial: config.criticalHigh,
              enabled: _fieldsEnabled,
              onSubmitted: (v) =>
                  _emit(config.copyWith(criticalHigh: v)),
            ),
          ],
        ),
      ),
    );
  }
}

class _NumFieldState extends State<_NumField> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial.toString());
  }

  @override
  void didUpdateWidget(_NumField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initial != widget.initial) {
      _ctrl.text = widget.initial.toString();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        decoration: InputDecoration(
          labelText: widget.label,
          border: const OutlineInputBorder(),
        ),
        enabled: widget.enabled,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*')),
        ],
        controller: _ctrl,
        onSubmitted: (s) {
          final v = double.tryParse(s.replaceAll(',', '.'));
          if (v != null) widget.onSubmitted(v);
        },
        onEditingComplete: () {
          final v = double.tryParse(_ctrl.text.replaceAll(',', '.'));
          if (v != null) widget.onSubmitted(v);
        },
      ),
    );
  }
}

class _NumField extends StatefulWidget {
  const _NumField({
    required super.key,
    required this.label,
    required this.initial,
    required this.enabled,
    required this.onSubmitted,
  });

  final String label;
  final double initial;
  final bool enabled;
  final ValueChanged<double> onSubmitted;

  @override
  State<_NumField> createState() => _NumFieldState();
}
