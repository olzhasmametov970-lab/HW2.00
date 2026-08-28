import 'package:flutter/material.dart';
import 'package:hydrowin/domain/models/reading_point.dart';

/// Статистика за период графика: среднее / мин / макс и % по зонам.
/// Счётчики блока/насоса/моточасов — на карточке машины, не здесь.
class SensorStatsPanel extends StatelessWidget {
  const SensorStatsPanel({
    required this.stats,
    required this.unit,
    super.key,
  });

  final ReadingStats stats;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatRow('Среднее', '${stats.avg.toStringAsFixed(1)} $unit'),
        _StatRow('Минимум', '${stats.min.toStringAsFixed(1)} $unit'),
        _StatRow('Максимум', '${stats.max.toStringAsFixed(1)} $unit'),
        const Divider(height: 16),
        _StatRow(
          'Время в норме',
          '${stats.pctInNorm.toStringAsFixed(0)}%',
          color: Colors.green.shade700,
        ),
        _StatRow(
          'Warning',
          '${stats.pctWarning.toStringAsFixed(0)}%',
          color: Colors.amber.shade800,
        ),
        _StatRow(
          'Критично',
          '${stats.pctCritical.toStringAsFixed(0)}%',
          color: Theme.of(context).colorScheme.error,
        ),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow(this.label, this.value, {this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}
