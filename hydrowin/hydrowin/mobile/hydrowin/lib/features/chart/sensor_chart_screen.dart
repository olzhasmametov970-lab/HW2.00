// lib/features/chart/sensor_chart_screen.dart
//
// График датчика для простого (одна машина) режима.
// ID датчиков получаются автоматически через API по channel_index.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:hydrowin/app/app_scope.dart';
import 'package:hydrowin/data/local/app_preferences.dart';
import 'package:hydrowin/data/local/fleet_registry_repository.dart';
import 'package:hydrowin/data/telemetry/telemetry_session.dart';
import 'package:hydrowin/domain/models/reading_point.dart';
import 'package:hydrowin/domain/models/sensor_status_level.dart';
import 'package:hydrowin/domain/reading_resolution.dart';
import 'package:hydrowin/domain/models/sensor_config.dart';
import 'package:hydrowin/domain/sensor_display_format.dart';
import 'package:hydrowin/domain/reading_stats_calculator.dart';
import 'package:hydrowin/features/chart/chart_export.dart';
import 'package:hydrowin/features/chart/mixins/poll_interval_refresh_mixin.dart';
import 'package:hydrowin/features/chart/widgets/chart_export_button.dart';
import 'package:hydrowin/features/chart/widgets/chart_period_export_sheet.dart';
import 'package:hydrowin/features/chart/widgets/sensor_stats_panel.dart';
import 'package:intl/intl.dart';

class SensorChartScreen extends StatefulWidget {
  const SensorChartScreen({super.key, required this.config});

  final SensorConfig config;

  @override
  State<SensorChartScreen> createState() => _SensorChartScreenState();
}

class _SensorChartScreenState extends State<SensorChartScreen>
    with PollIntervalRefreshMixin {
  bool _isLoading = true;
  String? _errorMessage;
  List<ReadingPoint> _points = [];
  String? _sensorId;
  String? _machineIp;
  DateTime _selectedDay = DateTime.now();
  int _fetchGen = 0;

  // Блокировщик параллельных запросов — только последний ответ применяется.

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      bindPollIntervalRefresh();
      _fetchData(forceRefresh: true); // Первый запуск — жесткий лоадер
    });
  }

  @override
  void dispose() {
    unbindPollIntervalRefresh();
    super.dispose();
  }

  DateTime get _dayStart =>
      DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);

  DateTime get _dayEnd {
    final end = _dayStart.add(const Duration(days: 1));
    final now = DateTime.now();
    if (_isToday(_selectedDay) && end.isAfter(now)) return now;
    return end;
  }

  bool _isToday(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  Future<String?> _resolveMachineIp() async {
    final prefs = await AppPreferences.create();

    final machineId = prefs.singleMachineId;
    if (machineId == null) return null;

    final repo = await FleetRegistryRepository.create();
    final entry = await repo.findById(machineId);
    return entry?.ipAddress;
  }

  Future<void> _fetchData({bool forceRefresh = false}) async {
    final gen = ++_fetchGen;

    if (forceRefresh) {
      setState(() {
        _points = [];
      });
    }

    // Показываем спиннер только если у нас пустой список точек.
    final isColdStart = _points.isEmpty;
    if (isColdStart) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    final session = AppScope.of(context);
    final useLocal = session.isLive &&
        (session.mode == TelemetryConnectionMode.connected ||
            session.mode == TelemetryConnectionMode.demo);

    if (useLocal) {
      try {
        final from = _dayStart;
        final to = _dayEnd;
        final minutes = to.difference(from).inMinutes.clamp(1, 24 * 60);
        final all = await AppScope.readingsOf(context).lastMinutes(
          channelIndex: widget.config.channelIndex,
          minutes: minutes,
        );
        final points = all
            .where((p) => !p.recordedAt.isBefore(from) && !p.recordedAt.isAfter(to))
            .toList();
        if (!mounted || gen != _fetchGen) return;
        setState(() {
          _points = points;
          _isLoading = false;
          _errorMessage = null;
        });
      } catch (e) {
        if (!mounted || gen != _fetchGen) return;
        setState(() {
          if (isColdStart) {
            _errorMessage = 'Ошибка загрузки данных:\n$e';
          }
          _isLoading = false;
        });
      }
      return;
    }

    final machines = AppScope.machinesOf(context);
    if (machines == null) {
      if (!mounted || gen != _fetchGen) return;
      setState(() {
        if (isColdStart) {
          _errorMessage = 'Сервер недоступен';
        }
        _isLoading = false;
      });
      return;
    }

    try {
      final machineIp = await _resolveMachineIp();
      if (machineIp == null || machineIp.isEmpty) {
        throw Exception('IP машины не настроен. Откройте настройки машины.');
      }

      final sensors = await machines.listSensors(machineIp);
      if (!mounted || gen != _fetchGen) return;

      final sensor = sensors
          .where((s) => s.config.channelIndex == widget.config.channelIndex)
          .firstOrNull;

      if (sensor == null) {
        throw Exception(
          'Датчик канала ${widget.config.channelIndex + 1} не найден на сервере',
        );
      }

      final from = _dayStart;
      final to = _dayEnd;
      final series = await machines.getReadings(
        machineIp,
        sensor.id,
        from: from,
        to: to,
        channelIndex: sensor.config.channelIndex,
      );

      if (!mounted || gen != _fetchGen) return;
      setState(() {
        _machineIp = machineIp;
        _sensorId = sensor.id;
        _points = series.points;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted || gen != _fetchGen) return;
      setState(() {
        if (isColdStart) {
          _errorMessage = 'Ошибка загрузки данных:\n$e';
        } else {
          debugPrint('Фоновое обновление не удалось: $e');
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('ru'),
    );
    if (picked == null) return;
    setState(() => _selectedDay = picked);
    await _fetchData(
      forceRefresh: true,
    ); // При смене даты принудительно перезагружаем
  }

  Future<void> _export(ChartExportFormat format) async {
    if (_points.length < 2) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Нет данных для экспорта')));
      return;
    }
    final config =
        AppScope.of(context).configs
            .where((c) => c.channelIndex == widget.config.channelIndex)
            .firstOrNull ??
        widget.config;
    final stats = ReadingStatsCalculator.compute(_points, config: config);
    try {
      final file = await ChartExport.save(
        format: format,
        points: _points,
        sensorName: widget.config.name,
        unit: widget.config.unit,
        rangeStart: _dayStart,
        rangeEnd: _dayEnd,
        stats: stats,
        machineLabel: _machineIp,
        resolutionNote: ReadingResolution.describeSpan(
          _dayEnd.difference(_dayStart),
        ),
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
    final machines = AppScope.machinesOf(context);
    if (machines == null || _machineIp == null || _machineIp!.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Сервер недоступен')));
      return;
    }
    final sensorId = _sensorId;
    if (sensorId == null || sensorId.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Датчик ещё не загружен')));
      return;
    }
    final config =
        AppScope.of(context).configs
            .where((c) => c.channelIndex == widget.config.channelIndex)
            .firstOrNull ??
        widget.config;

    await ChartPeriodExportSheet.show(
      context,
      sensorName: widget.config.name,
      unit: widget.config.unit,
      machineLabel: _machineIp,
      statsConfig: config,
      loadPoints: (from, to) async {
        final series = await machines.getReadings(
          _machineIp!,
          sensorId,
          from: from,
          to: to,
          channelIndex: widget.config.channelIndex,
        );
        return series.points;
      },
    );
  }

  // При тике таймера — тихое фоновое обновление (только сегодня).
  @override
  Future<void> onPollIntervalRefresh() async {
    if (_isToday(_selectedDay)) {
      await _fetchData(forceRefresh: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config =
        AppScope.of(context).configs
            .where((c) => c.channelIndex == widget.config.channelIndex)
            .firstOrNull ??
        widget.config;
    final stats = _points.length >= 2
        ? ReadingStatsCalculator.compute(_points, config: config)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.config.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            tooltip: 'Выбрать дату',
            onPressed: _pickDate,
          ),
          ChartExportButton(
            onTodayExport: _export,
            onPeriodExport: _exportPeriod,
          ),
          // Кнопка ручного обновления вызывает жесткий релоад со спиннером
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _fetchData(forceRefresh: true),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _fetchData(forceRefresh: true),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('dd.MM.yyyy').format(_selectedDay),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (_machineIp != null)
                      Text(
                        'Машина: $_machineIp',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (_sensorId != null)
                      Text(
                        'Датчик: $_sensorId',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (_isToday(_selectedDay))
                      Text(
                        'Живое обновление каждые '
                        '${AppScope.of(context).pollSeconds} с',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 280,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                  ? Center(
                      child: Text(_errorMessage!, textAlign: TextAlign.center),
                    )
                  : _points.length < 2
                  ? const Center(child: Text('Нет данных за выбранный период'))
                  : _LocalLineChart(
                      key: ValueKey(
                        '${_points.length}-'
                        '${_points.last.recordedAt.millisecondsSinceEpoch}',
                      ),
                      points: _points,
                      config: widget.config,
                      day: _selectedDay,
                    ),
            ),
            if (stats != null) ...[
              const SizedBox(height: 24),
              Text(
                'Статистика за период',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              SensorStatsPanel(stats: stats, unit: widget.config.unit),
            ],
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}

class _LocalLineChart extends StatelessWidget {
  const _LocalLineChart({
    super.key,
    required this.points,
    required this.config,
    required this.day,
  });

  final List<ReadingPoint> points;
  final SensorConfig config;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final values = points.map((p) => p.value).toList();
    var dataMin = values.reduce((a, b) => a < b ? a : b);
    var dataMax = values.reduce((a, b) => a > b ? a : b);
    if ((dataMax - dataMin).abs() < 0.5) {
      dataMin -= 1;
      dataMax += 1;
    }
    final pad = (dataMax - dataMin) * 0.12 + 0.5;
    final minY = dataMin - pad;
    final maxY = dataMax + pad;

    final t0 = points.first.recordedAt.millisecondsSinceEpoch.toDouble();
    // Разрыв линии на аварийных точках (fault/open/short дают status=critical).
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

    final spots = <FlSpot>[
      ...segments.expand((s) => s),
      ...criticalSegments.expand((s) => s),
      ...criticalSingles,
    ]..sort((a, b) => a.x.compareTo(b.x));

    final timeFmt = DateFormat.Hm();

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
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
              interval: ((maxY - minY) / 4).clamp(0.5, double.infinity),
              getTitlesWidget: (v, _) => Text(
                v.round().toString(),
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: spots.length > 6
                  ? (spots.last.x - spots.first.x) / 5
                  : 1.0,
              getTitlesWidget: (v, _) {
                final ms = t0 + v * 3600000;
                return Text(
                  timeFmt.format(
                    DateTime.fromMillisecondsSinceEpoch(ms.round()),
                  ),
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.55),
          ),
        ),
        lineBarsData: [
          for (final seg in segments)
            LineChartBarData(
              spots: seg,
              isCurved: false,
              color: Theme.of(context).colorScheme.primary,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.12),
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
            getTooltipItems: (touched) => touched.map((bar) {
              final p = points[bar.spotIndex];
              return LineTooltipItem(
                '${SensorDisplayFormat.valueWithUnit(p.value, config.unit)}\n'
                '${timeFmt.format(p.recordedAt)}',
                const TextStyle(color: Colors.white, fontSize: 11),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

