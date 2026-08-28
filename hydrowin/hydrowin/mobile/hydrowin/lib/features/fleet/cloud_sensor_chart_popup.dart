import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:hydrowin/app/app_scope.dart';
import 'package:hydrowin/app/cloud_scope.dart';
import 'package:hydrowin/core/constants/app_constants.dart';
import 'package:hydrowin/domain/models/cloud_sensor.dart';
import 'package:hydrowin/domain/models/reading_point.dart';
import 'package:hydrowin/domain/models/readings_series.dart';
import 'package:hydrowin/domain/models/sensor_status_level.dart';
import 'package:hydrowin/domain/reading_resolution.dart';
import 'package:hydrowin/domain/sensor_display_format.dart';
import 'package:hydrowin/features/chart/chart_time_range.dart';
import 'package:hydrowin/features/chart/mixins/poll_interval_refresh_mixin.dart';
import 'package:hydrowin/features/chart/widgets/chart_axis_titles.dart';
import 'package:hydrowin/features/chart/widgets/chart_range_selector.dart';
import 'package:go_router/go_router.dart';

/// Всплывающий график. Двойной тап / кнопка — полный экран.
Future<void> showCloudSensorDayChartPopup(
  BuildContext context, {
  required String machineId,
  required String sensorId,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 620),
        child: _CloudSensorChartPopupBody(
          machineId: machineId,
          sensorId: sensorId,
        ),
      ),
    ),
  );
}

class _CloudSensorChartPopupBody extends StatefulWidget {
  const _CloudSensorChartPopupBody({
    required this.machineId,
    required this.sensorId,
  });

  final String machineId;
  final String sensorId;

  @override
  State<_CloudSensorChartPopupBody> createState() =>
      _CloudSensorChartPopupBodyState();
}

class _CloudSensorChartPopupBodyState extends State<_CloudSensorChartPopupBody>
    with PollIntervalRefreshMixin {
  CloudSensor? _sensor;
  ReadingsSeries? _series;
  bool _loading = true;
  String? _error;
  ChartTimeRange _range = ChartTimeRange.day(DateTime.now());
  int _loadGen = 0;

  @override
  void initState() {
    super.initState();
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
      setState(() => _series = null);
    }

    final isColdStart = _series == null || _series!.points.isEmpty;
    if (isColdStart) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    final repo = CloudScope.of(context).machines;
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
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _range = range;
        _sensor = sensor;
        _series = series;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        if (isColdStart) {
          _error = CloudScope.of(context).auth.humanizeError(e);
        } else {
          debugPrint('Фоновое обновление графика не удалось: $e');
        }
        _loading = false;
      });
    }
  }

  @override
  Future<void> onPollIntervalRefresh() async {
    if (_range.supportsLiveRefresh) {
      await _load(forceRefresh: false);
    }
  }

  void _openFull() {
    final range = _range;
    Navigator.of(context).pop();
    context.push(
      '/cloud/machine/${widget.machineId}/sensor/${widget.sensorId}/day',
      extra: range,
    );
  }

  int get _pollSeconds {
    final session = AppScope.of(context);
    return session.pollSeconds
        .clamp(AppConstants.minPollSeconds, AppConstants.maxPollSeconds);
  }

  @override
  Widget build(BuildContext context) {
    final sensor = _sensor;
    final series = _series;
    final title = sensor != null
        ? '${sensor.config.type.label}: ${sensor.config.name}'
        : 'График';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: ChartRangeSelector(
            value: _range,
            onChanged: _setRange,
            compact: true,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            '${_range.titleLabel} · двойной тап — открыть вкладку'
            '${_range.supportsLiveRefresh ? ' · обновление каждые $_pollSeconds с' : ''}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_error!, textAlign: TextAlign.center),
                      ),
                    )
                  : series == null || series.points.length < 2
                      ? Center(
                          child: Text(
                            series?.points.isEmpty ?? true
                                ? 'Нет данных за период'
                                : 'Недостаточно точек',
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 12, 8),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onDoubleTap: _openFull,
                            child: _PopupLineChart(
                              key: ValueKey(
                                '${series.points.length}-'
                                '${series.points.last.recordedAt.millisecondsSinceEpoch}',
                              ),
                              points: series.points,
                              unit: sensor?.config.unit ?? series.unit,
                              range: _range,
                            ),
                          ),
                        ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  ReadingResolution.describeSpan(_range.span),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: _openFull,
                child: const Text('Открыть вкладку'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PopupLineChart extends StatelessWidget {
  const _PopupLineChart({
    super.key,
    required this.points,
    required this.unit,
    required this.range,
  });

  final List<ReadingPoint> points;
  final String unit;
  final ChartTimeRange range;

  @override
  Widget build(BuildContext context) {
    final yScale = ChartYAxisScale.fromValues(
      points.map((p) => p.value),
      targetTicks: 5,
    );

    final first = points.first.recordedAt.millisecondsSinceEpoch.toDouble();
    // Разрыв линии на аварийных точках (fault/open/short дают status=critical).
    final segments = <List<FlSpot>>[];
    final criticalSegments = <List<FlSpot>>[];
    final criticalSingles = <FlSpot>[];
    var current = <FlSpot>[];
    var currentCritical = <FlSpot>[];
    for (final p in points) {
      final spot = FlSpot(
        (p.recordedAt.millisecondsSinceEpoch.toDouble() - first) / 3600000,
        p.value,
      );
      if (p.status == SensorStatusLevel.critical) {
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
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: chartRightGutter,
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
                epochMsAtZero: first,
              ),
            ),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yScale.interval,
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          for (final seg in segments)
            LineChartBarData(
              spots: seg,
              isCurved: true,
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
                  SensorDisplayFormat.valueWithUnit(t.y, unit),
                  TextStyle(
                    color: Theme.of(context).colorScheme.onInverseSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

