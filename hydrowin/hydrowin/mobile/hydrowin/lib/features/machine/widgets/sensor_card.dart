import 'package:flutter/material.dart';
import 'package:hydrowin/core/theme/app_theme.dart';
import 'package:hydrowin/domain/models/live_sensor_reading.dart';
import 'package:hydrowin/domain/models/sensor_config.dart';
import 'package:hydrowin/domain/models/sensor_type.dart';
import 'package:hydrowin/features/fleet/widgets/circular_sensor_gauge.dart';

/// Карточка датчика со стрелочной шкалой (без графиков).
class SensorCard extends StatelessWidget {
  const SensorCard({
    required this.config,
    this.reading,
    this.showServiceCurrent = true,
    super.key,
  });

  final SensorConfig config;
  final LiveSensorReading? reading;

  /// Показывать ток петли 4–20 мА (сервисная строка под значением).
  final bool showServiceCurrent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = reading?.status ?? SensorStatusLevel.offline;
    final color = AppTheme.statusColor(status, context);
    final value = reading?.value ?? config.scaleMin;
    final valueText = reading?.formattedValue ?? '— ${config.unit}';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            CircularSensorGauge(
              value: value,
              config: config,
              status: status,
              size: 104,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${config.type.label} — ${config.name}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    valueText,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  if (showServiceCurrent && reading != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Петля 4–20 мА: ${reading!.formattedServiceCurrent}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    _normHint(config),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  if (reading == null)
                    Text(
                      'Ожидание данных…',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
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

  String _normHint(SensorConfig c) {
    return switch (c.type) {
      SensorType.temperature => 'Норма: до ${c.normMax} ${c.unit}',
      SensorType.pressure =>
        'Норма: ${c.normMin ?? c.scaleMin}–${c.normMax} ${c.unit}',
      _ => 'Диапазон: ${c.normMin ?? c.scaleMin}–${c.normMax} ${c.unit}',
    };
  }
}
