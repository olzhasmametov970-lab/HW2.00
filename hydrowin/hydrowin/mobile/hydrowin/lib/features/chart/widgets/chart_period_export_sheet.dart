import 'package:flutter/material.dart';
import 'package:hydrowin/domain/models/reading_point.dart';
import 'package:hydrowin/domain/models/sensor_config.dart';
import 'package:hydrowin/domain/reading_resolution.dart';
import 'package:hydrowin/domain/reading_stats_calculator.dart';
import 'package:hydrowin/features/chart/chart_export.dart';
import 'package:intl/intl.dart';

/// Экспорт показаний за произвольный период (с агрегацией на сервере).
class ChartPeriodExportSheet extends StatefulWidget {
  const ChartPeriodExportSheet({
    required this.sensorName,
    required this.unit,
    required this.loadPoints,
    this.machineLabel,
    this.engineHours,
    this.statsConfig,
    super.key,
  });

  final String sensorName;
  final String unit;
  final String? machineLabel;
  final double? engineHours;
  final SensorConfig? statsConfig;
  final Future<List<ReadingPoint>> Function(DateTime from, DateTime to)
      loadPoints;

  static Future<void> show(
    BuildContext context, {
    required String sensorName,
    required String unit,
    required Future<List<ReadingPoint>> Function(DateTime from, DateTime to)
        loadPoints,
    String? machineLabel,
    double? engineHours,
    SensorConfig? statsConfig,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: ChartPeriodExportSheet(
          sensorName: sensorName,
          unit: unit,
          loadPoints: loadPoints,
          machineLabel: machineLabel,
          engineHours: engineHours,
          statsConfig: statsConfig,
        ),
      ),
    );
  }

  @override
  State<ChartPeriodExportSheet> createState() => _ChartPeriodExportSheetState();
}

class _ChartPeriodExportSheetState extends State<ChartPeriodExportSheet> {
  late DateTime _from;
  late DateTime _to;
  ChartExportFormat _format = ChartExportFormat.xlsx;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _to = DateTime(now.year, now.month, now.day, 23, 59, 59);
    _from = _to.subtract(
      const Duration(days: ReadingResolution.maxHistoryDays),
    );
  }

  Duration get _span => _to.difference(_from);

  DateTime get _earliestAllowed {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: ReadingResolution.maxHistoryDays));
  }

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _from.isBefore(_earliestAllowed) ? _earliestAllowed : _from,
      firstDate: _earliestAllowed,
      lastDate: _to,
      locale: const Locale('ru'),
    );
    if (picked == null) return;
    setState(() {
      _from = DateTime(picked.year, picked.month, picked.day);
      if (_from.isAfter(_to)) _to = _from;
    });
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: _from.isBefore(_earliestAllowed) ? _earliestAllowed : _from,
      lastDate: DateTime.now(),
      locale: const Locale('ru'),
    );
    if (picked == null) return;
    setState(() {
      _to = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
    });
  }

  Future<void> _export() async {
    if (_exporting) return;
    if (_from.isAfter(_to)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Дата «с» не может быть позже «по»')),
      );
      return;
    }

    setState(() => _exporting = true);
    try {
      final points = await widget.loadPoints(_from, _to);
      if (!mounted) return;
      if (points.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет данных за выбранный период')),
        );
        return;
      }

      final stats = widget.statsConfig != null
          ? ReadingStatsCalculator.compute(points, config: widget.statsConfig)
          : ReadingStatsCalculator.compute(points);

      final file = await ChartExport.save(
        format: _format,
        points: points,
        sensorName: widget.sensorName,
        unit: widget.unit,
        rangeStart: _from,
        rangeEnd: _to,
        stats: stats,
        machineLabel: widget.machineLabel,
        engineHours: widget.engineHours,
        resolutionNote: ReadingResolution.describeSpan(_span),
      );

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(file.path)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка экспорта: $e')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd.MM.yyyy');
    final est = ReadingResolution.estimatedPointCount(_span);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Экспорт за период',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'История на сервере: до ${ReadingResolution.maxHistoryDays} дней '
              '(полгода). Сырые точки — ${ReadingResolution.rawHistoryDays} дн., '
              'дальше — часовые/суточные агрегаты. '
              'Для длинных периодов отдаются усреднённые точки.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('С'),
              subtitle: Text(dateFmt.format(_from)),
              trailing: const Icon(Icons.calendar_today),
              onTap: _exporting ? null : _pickFrom,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('По'),
              subtitle: Text(dateFmt.format(_to)),
              trailing: const Icon(Icons.calendar_today),
              onTap: _exporting ? null : _pickTo,
            ),
            const SizedBox(height: 8),
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Оптимизация: ${ReadingResolution.describeSpan(_span)}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text('Ожидаемо ~$est точек (не каждая секунда с платы)'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ChartExportFormat>(
              initialValue: _format,
              decoration: const InputDecoration(
                labelText: 'Формат файла',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final f in ChartExportFormat.values)
                  DropdownMenuItem(value: f, child: Text(f.label)),
              ],
              onChanged: _exporting
                  ? null
                  : (v) {
                      if (v != null) setState(() => _format = v);
                    },
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _exporting ? null : _export,
              icon: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
              label: Text(_exporting ? 'Загрузка…' : 'Скачать'),
            ),
          ],
        ),
      ),
    );
  }
}
