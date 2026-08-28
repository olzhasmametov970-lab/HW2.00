// lib/features/fleet/cloud_sensor_day_chart_screen.dart

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:hydrowin/app/app_scope.dart';
import 'package:hydrowin/app/cloud_scope.dart';
import 'package:hydrowin/core/api/session_expired_exception.dart';
import 'package:hydrowin/domain/models/cloud_sensor.dart';
import 'package:hydrowin/domain/models/machine_summary.dart';
import 'package:hydrowin/domain/models/readings_series.dart';
import 'package:hydrowin/domain/models/reading_point.dart';
import 'package:hydrowin/domain/models/sensor_status_level.dart';
import 'package:hydrowin/domain/reading_resolution.dart';
import 'package:hydrowin/domain/models/sensor_config.dart';
import 'package:hydrowin/domain/sensor_display_format.dart';
import 'package:hydrowin/domain/reading_stats_calculator.dart';
import 'package:hydrowin/features/chart/chart_export.dart';
import 'package:hydrowin/features/chart/chart_time_range.dart';
import 'package:hydrowin/features/chart/mixins/poll_interval_refresh_mixin.dart';
import 'package:hydrowin/features/chart/widgets/chart_export_button.dart';
import 'package:hydrowin/features/chart/widgets/chart_period_export_sheet.dart';
import 'package:hydrowin/features/chart/widgets/chart_axis_titles.dart';
import 'package:hydrowin/features/chart/widgets/chart_range_selector.dart';
import 'package:hydrowin/features/chart/widgets/sensor_stats_panel.dart';
import 'package:go_router/go_router.dart';

class CloudSensorDayChartScreen extends StatefulWidget {
  const CloudSensorDayChartScreen({
    required this.machineId,
    required this.sensorId,
    this.initialRange,
    super.key,
  });

  final String machineId;
  final String sensorId;
  final ChartTimeRange? initialRange;

  @override
  State<CloudSensorDayChartScreen> createState() =>
      _CloudSensorDayChartScreenState();
}

class _CloudSensorDayChartScreenState extends State<CloudSensorDayChartScreen>
    with PollIntervalRefreshMixin {
  CloudSensor? _sensor;
  MachineSummary? _machine;
  ReadingsSeries? _series;
  String? _error;
  bool _loading = true;
  late ChartTimeRange _range;
  int _loadGen = 0;

  @override
  void initState() {
    super.initState();
    _range = widget.initialRange ?? ChartTimeRange.day(DateTime.now());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      bindPollIntervalRefresh();
      _load(forceRefresh: true);
    });
  }

  @override
  void dispose() {
    unbindPollIntervalRefresh();
    super.dispose();
  }

  Future<void> _setRange(ChartTimeRange next) async {
    setState(() => _range = next);
    await _load(forceRefresh: true);
  }

  Future<void> _load({bool forceRefresh = false}) async {
    final gen = ++_loadGen;

    if (forceRefresh) {
      setState(() {
        _series = null;
      });
    }

    final isColdStart = _series == null || _series!.points.isEmpty;
    if (isColdStart) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    final repo = CloudScope.of(context).machines;
    final auth = CloudScope.of(context).auth;

    try {
      final sensors = await repo.listSensors(widget.machineId);
      if (!mounted || gen != _loadGen) return;

      CloudSensor? sensor;
      for (final s in sensors) {
        if (s.id == widget.sensorId) {
          sensor = s;
          break;
        }
      }

      // Для скользящих интервалов пересчитываем «сейчас» на каждый запрос.
      final range = switch (_range.kind) {
        ChartRangeKind.hour => ChartTimeRange.hour(),
        ChartRangeKind.week => ChartTimeRange.week(),
        ChartRangeKind.month => ChartTimeRange.month(),
        ChartRangeKind.day || ChartRangeKind.calendarMonth => _range,
      };

      final series = await repo.getReadings(
        widget.machineId,
        widget.sensorId,
        from: range.from,
        to: range.to,
        channelIndex: sensor?.config.channelIndex ?? 0,
      );
      final machine = await repo.getMachine(widget.machineId);

      if (!mounted || gen != _loadGen) return;
      setState(() {
        _range = range;
        _sensor = sensor;
        _machine = machine;
        _series = series;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || gen != _loadGen) return;
      if (e is SessionExpiredException) {
        context.go('/fleet');
        return;
      }
      setState(() {
        if (isColdStart) {
          _error = auth.humanizeError(e);
        } else {
          debugPrint('Фоновое обновление не удалось: $e');
        }
        _loading = false;
      });
    }
  }

  Future<void> _export(ChartExportFormat format) async {
    final series = _series;
    final sensor = _sensor;
    if (series == null || series.points.length < 2) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Нет данных для экспорта')));
      return;
    }
    final statsConfig = sensor?.config;
    final stats = statsConfig != null
        ? ReadingStatsCalculator.compute(series.points, config: statsConfig)
        : ReadingStatsCalculator.compute(series.points);
    try {
      final file = await ChartExport.save(
        format: format,
        points: series.points,
        sensorName: sensor?.config.name ?? 'sensor',
        unit: sensor?.config.unit ?? series.unit,
        rangeStart: _range.from,
        rangeEnd: _range.to,
        stats: stats,
        machineLabel: _machine != null
            ? '${_machine!.code} · ${_machine!.name}'
            : widget.machineId,
        engineHours: _machine?.engineHours,
        resolutionNote: ReadingResolution.describeSpan(_range.span),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${format.label}: ${file.path}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка экспорта: $e')));
    }
  }

  Future<void> _exportPeriod() async {
    final sensor = _sensor;
    if (sensor == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Датчик ещё не загружен')));
      return;
    }

    await ChartPeriodExportSheet.show(
      context,
      sensorName: sensor.config.name,
      unit: sensor.config.unit,
      machineLabel: _machine != null
          ? '${_machine!.code} · ${_machine!.name}'
          : widget.machineId,
      engineHours: _machine?.engineHours,
      statsConfig: sensor.config,
      loadPoints: (from, to) async {
        final series = await CloudScope.of(context).machines.getReadings(
          widget.machineId,
          widget.sensorId,
          from: from,
          to: to,
          channelIndex: sensor.config.channelIndex,
        );
        return series.points;
      },
    );
  }

  @override
  Future<void> onPollIntervalRefresh() async {
    if (_range.supportsLiveRefresh) {
      await _load(forceRefresh: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sensor = _sensor;
    final series = _series;
    final statsConfig = sensor?.config;

    final title = sensor != null
        ? '${sensor.config.type.label}: ${sensor.config.name}'
        : 'Датчик';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          ChartExportButton(
            onTodayExport: _export,
            onPeriodExport: _exportPeriod,
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
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => _load(forceRefresh: true),
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ChartRangeSelector(
                        value: _range,
                        onChanged: _setRange,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _range.titleLabel,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _range.intervalHint,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (_range.supportsLiveRefresh)
                        Text(
                          'Живое обновление каждые '
                          '${AppScope.of(context).pollSeconds} с',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      Text(
                        'Разрешение: ${ReadingResolution.describeSpan(_range.span)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: series == null || series.points.length < 2
                        ? Center(
                            child: Text(
                              series?.points.isEmpty ?? true
                                  ? 'Нет данных за выбранный период.'
                                  : 'Недостаточно точек для графика.',
                              textAlign: TextAlign.center,
                            ),
                          )
                        : _CloudDayLineChart(
                            key: ValueKey(
                              '${series.points.length}-'
                              '${series.points.last.recordedAt.millisecondsSinceEpoch}',
                            ),
                            points: series.points,
                            config: statsConfig,
                            range: _range,
                          ),
                  ),
                ),
                if (series != null && series.points.length >= 2)
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Статистика: ${_range.titleLabel}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          SensorStatsPanel(
                            stats: ReadingStatsCalculator.compute(
                              series.points,
                              config: statsConfig,
                            ),
                            unit: statsConfig?.unit ?? series.unit,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _CloudDayLineChart extends StatelessWidget {
  const _CloudDayLineChart({
    super.key,
    required this.points,
    required this.config,
    required this.range,
  });

  final List<ReadingPoint> points;
  final SensorConfig? config;
  final ChartTimeRange range;

  @override
  Widget build(BuildContext context) {
    final values = points.map((p) => p.value);
    // Ось только по данным — пороги не раздувают шкалу и не плодят подписи.
    final yScale = ChartYAxisScale.fromValues(values, targetTicks: 6);

    final t0 = points.first.recordedAt.millisecondsSinceEpoch.toDouble();
    // Разрыв линии на аварийных точках (fault/open/short дают status=critical).
    // Так история не "перемешивает" фиксацию обрыва как нормальное измерение.
    final segments = <List<FlSpot>>[];
    final criticalSegments = <List<FlSpot>>[];
    final criticalSingles = <FlSpot>[];
    var current = <FlSpot>[];
    var currentCritical = <FlSpot>[];
    for (final p in points) {
      final spot = FlSpot(
        (p.recordedAt.millisecondsSinceEpoch - t0) / 3600000,
        p.value,
      );
      final isFault = p.status == SensorStatusLevel.critical;
      if (isFault) {
        if (current.length >= 2) segments.add(current);
        current = <FlSpot>[];
        currentCritical.add(spot);
        continue;
      }
      if (currentCritical.length == 1) {
        criticalSingles.add(currentCritical.first);
      } else if (currentCritical.length >= 2) {
        criticalSegments.add(currentCritical);
      }
      currentCritical = <FlSpot>[];
      current.add(spot);
    }
    if (current.length >= 2) segments.add(current);
    if (currentCritical.length == 1) {
      criticalSingles.add(currentCritical.first);
    } else if (currentCritical.length >= 2) {
      criticalSegments.add(currentCritical);
    }

    final allSpots = <FlSpot>[
      ...segments.expand((s) => s),
      ...criticalSegments.expand((s) => s),
      ...criticalSingles,
    ]..sort((a, b) => a.x.compareTo(b.x));
    final xMax = allSpots.isEmpty ? 1.0 : allSpots.last.x;
    final xInterval =
        (xMax / 4).clamp(xMax > 0 ? xMax / 6 : 0.25, double.infinity);

    return LineChart(
      LineChartData(
        minY: yScale.minY,
        maxY: yScale.maxY,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          horizontalInterval: yScale.interval,
          getDrawingHorizontalLine: (v) => FlLine(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.35),
            strokeWidth: 1,
          ),
          getDrawingVerticalLine: (v) => FlLine(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: yScale.interval,
              getTitlesWidget: yScale.titleWidget,
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: xInterval,
              getTitlesWidget: (v, meta) => chartBottomAxisTitle(
                value: v,
                meta: meta,
                range: range,
                epochMsAtZero: t0,
              ),
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: chartRightGutter,
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          for (final seg in segments)
            LineChartBarData(
              spots: seg,
              isCurved: true,
              preventCurveOverShooting: true,
              color: Theme.of(context).colorScheme.primary,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.12),
              ),
            ),
          for (final seg in criticalSegments)
            LineChartBarData(
              spots: seg,
              isCurved: false,
              color: Theme.of(context).colorScheme.error,
              barWidth: 2,
              dashArray: const [6, 4],
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: false),
            ),
          if (criticalSingles.isNotEmpty)
            LineChartBarData(
              spots: criticalSingles,
              isCurved: false,
              color: Colors.transparent,
              barWidth: 1,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                  radius: 5.0,
                  color: Theme.of(context).colorScheme.error,
                  strokeWidth: 1.5,
                  strokeColor: Theme.of(context).colorScheme.surface,
                ),
              ),
              belowBarData: BarAreaData(show: false),
            ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touched) => [
              for (final t in touched)
                LineTooltipItem(
                  '${SensorDisplayFormat.valueWithUnit(t.y, config?.unit ?? '')}\n'
                  '${range.formatAxisTick(DateTime.fromMillisecondsSinceEpoch((t0 + t.x * 3600000).round()))}',
                  TextStyle(
                    color: Theme.of(context).colorScheme.onInverseSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

