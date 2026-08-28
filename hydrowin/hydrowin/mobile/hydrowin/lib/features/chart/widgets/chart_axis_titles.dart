import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:hydrowin/features/chart/chart_time_range.dart';

/// Подпись оси X: не вылезает за край графика.
Widget chartBottomAxisTitle({
  required double value,
  required TitleMeta meta,
  required ChartTimeRange range,
  required double epochMsAtZero,
}) {
  if (value < meta.min - 0.001 || value > meta.max + 0.001) {
    return const SizedBox.shrink();
  }

  final ts = DateTime.fromMillisecondsSinceEpoch(
    (epochMsAtZero + value * 3600000).round(),
  );
  final label = range.formatAxisTick(ts);

  return SideTitleWidget(
    meta: meta,
    space: 4,
    fitInside: SideTitleFitInsideData.fromTitleMeta(
      meta,
      distanceFromEdge: 4,
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 9, height: 1.1),
      textAlign: TextAlign.center,
      maxLines: 2,
      softWrap: false,
      overflow: TextOverflow.clip,
    ),
  );
}

/// Правый запас, чтобы последняя подпись не упиралась в край диалога.
const AxisTitles chartRightGutter = AxisTitles(
  sideTitles: SideTitles(showTitles: false, reservedSize: 20),
);

/// «Красивые» границы и шаг оси Y без наложения подписей.
class ChartYAxisScale {
  const ChartYAxisScale({
    required this.minY,
    required this.maxY,
    required this.interval,
    required this.ticks,
  });

  final double minY;
  final double maxY;
  final double interval;
  final List<double> ticks;

  factory ChartYAxisScale.fromValues(
    Iterable<double> values, {
    int targetTicks = 5,
  }) {
    final list = values.toList();
    if (list.isEmpty) {
      return const ChartYAxisScale(
        minY: 0,
        maxY: 1,
        interval: 0.25,
        ticks: [0, 0.25, 0.5, 0.75, 1],
      );
    }

    var dataMin = list.reduce(math.min);
    var dataMax = list.reduce(math.max);
    if ((dataMax - dataMin).abs() < 1e-9) {
      dataMin -= 1;
      dataMax += 1;
    }

    final pad = (dataMax - dataMin) * 0.08;
    final rawMin = dataMin - pad;
    final rawMax = dataMax + pad;
    final nice = _niceScale(rawMin, rawMax, targetTicks);
    return nice;
  }

  String format(double v) {
    return v.round().toString();
  }

  /// Показывать подпись только на «своих» тиках, без дублей текста.
  Widget titleWidget(double value, TitleMeta meta) {
    if (!_isTick(value)) return const SizedBox.shrink();

    final label = format(value);
    // Соседний тик с тем же текстом (29.0 / 28.96 → «29.0») — скрыть.
    for (final t in ticks) {
      if (t >= value - 1e-9) break;
      if (format(t) == label) return const SizedBox.shrink();
    }

    return SideTitleWidget(
      meta: meta,
      space: 4,
      child: Text(label, style: const TextStyle(fontSize: 10)),
    );
  }

  bool _isTick(double value) {
    for (final t in ticks) {
      if ((t - value).abs() <= interval * 0.02 + 1e-6) return true;
    }
    return false;
  }
}

ChartYAxisScale _niceScale(double min, double max, int targetTicks) {
  final range = _niceNum(max - min, round: false);
  final interval = _niceNum(range / math.max(1, targetTicks - 1), round: true);
  final niceMin = (min / interval).floor() * interval;
  final niceMax = (max / interval).ceil() * interval;

  final ticks = <double>[];
  // Защита от бесконечного цикла при странном interval.
  final safeInterval = interval <= 0 ? 1.0 : interval;
  for (var v = niceMin; v <= niceMax + safeInterval * 0.5; v += safeInterval) {
    ticks.add(double.parse(v.toStringAsFixed(10)));
    if (ticks.length > 20) break;
  }
  if (ticks.length < 2) {
    ticks
      ..clear()
      ..add(niceMin)
      ..add(niceMax);
  }

  return ChartYAxisScale(
    minY: niceMin,
    maxY: niceMax,
    interval: safeInterval,
    ticks: ticks,
  );
}

double _niceNum(double range, {required bool round}) {
  final abs = range.abs();
  if (abs < 1e-12) return 1;
  final exp = (math.log(abs) / math.ln10).floor();
  final frac = abs / math.pow(10, exp);
  late double niceFrac;
  if (round) {
    if (frac < 1.5) {
      niceFrac = 1;
    } else if (frac < 3) {
      niceFrac = 2;
    } else if (frac < 7) {
      niceFrac = 5;
    } else {
      niceFrac = 10;
    }
  } else {
    if (frac <= 1) {
      niceFrac = 1;
    } else if (frac <= 2) {
      niceFrac = 2;
    } else if (frac <= 5) {
      niceFrac = 5;
    } else {
      niceFrac = 10;
    }
  }
  return niceFrac * math.pow(10, exp).toDouble();
}
