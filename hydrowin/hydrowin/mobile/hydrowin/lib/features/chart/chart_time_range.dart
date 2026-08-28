/// Выбор интервала для облачного графика датчика.
enum ChartRangeKind {
  hour,
  day,
  week,
  month,
  calendarMonth,
}

extension ChartRangeKindLabel on ChartRangeKind {
  String get shortLabel => switch (this) {
        ChartRangeKind.hour => 'Час',
        ChartRangeKind.day => 'День',
        ChartRangeKind.week => 'Неделя',
        ChartRangeKind.month => 'Месяц',
        ChartRangeKind.calendarMonth => 'Месяц…',
      };
}

class ChartTimeRange {
  const ChartTimeRange({
    required this.kind,
    required this.anchor,
  });

  final ChartRangeKind kind;

  /// Для day — календарный день; для calendarMonth — любой день выбранного месяца.
  /// Для hour/week/month (скользящих) якорь обычно «сейчас».
  final DateTime anchor;

  static ChartTimeRange hour([DateTime? now]) =>
      ChartTimeRange(kind: ChartRangeKind.hour, anchor: now ?? DateTime.now());

  static ChartTimeRange day(DateTime day) => ChartTimeRange(
        kind: ChartRangeKind.day,
        anchor: DateTime(day.year, day.month, day.day),
      );

  static ChartTimeRange week([DateTime? now]) =>
      ChartTimeRange(kind: ChartRangeKind.week, anchor: now ?? DateTime.now());

  static ChartTimeRange month([DateTime? now]) =>
      ChartTimeRange(kind: ChartRangeKind.month, anchor: now ?? DateTime.now());

  static ChartTimeRange calendarMonth(DateTime month) => ChartTimeRange(
        kind: ChartRangeKind.calendarMonth,
        anchor: DateTime(month.year, month.month, 1),
      );

  DateTime get from {
    final now = DateTime.now();
    switch (kind) {
      case ChartRangeKind.hour:
        return now.subtract(const Duration(hours: 1));
      case ChartRangeKind.day:
        return DateTime(anchor.year, anchor.month, anchor.day);
      case ChartRangeKind.week:
        return now.subtract(const Duration(days: 7));
      case ChartRangeKind.month:
        return now.subtract(const Duration(days: 30));
      case ChartRangeKind.calendarMonth:
        return DateTime(anchor.year, anchor.month, 1);
    }
  }

  DateTime get to {
    final now = DateTime.now();
    switch (kind) {
      case ChartRangeKind.hour:
      case ChartRangeKind.week:
      case ChartRangeKind.month:
        return now;
      case ChartRangeKind.day:
        final end = DateTime(anchor.year, anchor.month, anchor.day)
            .add(const Duration(days: 1));
        return end.isAfter(now) ? now : end;
      case ChartRangeKind.calendarMonth:
        final end = DateTime(anchor.year, anchor.month + 1, 1);
        return end.isAfter(now) ? now : end;
    }
  }

  Duration get span => to.difference(from);

  /// Можно ли тихо обновлять по таймеру опроса.
  bool get supportsLiveRefresh {
    final now = DateTime.now();
    switch (kind) {
      case ChartRangeKind.hour:
      case ChartRangeKind.week:
      case ChartRangeKind.month:
        return true;
      case ChartRangeKind.day:
        return anchor.year == now.year &&
            anchor.month == now.month &&
            anchor.day == now.day;
      case ChartRangeKind.calendarMonth:
        return anchor.year == now.year && anchor.month == now.month;
    }
  }

  String get titleLabel {
    switch (kind) {
      case ChartRangeKind.hour:
        return 'Последний час';
      case ChartRangeKind.day:
        return _fmtDay(from);
      case ChartRangeKind.week:
        return 'Последние 7 дней';
      case ChartRangeKind.month:
        return 'Последние 30 дней';
      case ChartRangeKind.calendarMonth:
        return _fmtMonth(from);
    }
  }

  String get intervalHint {
    switch (kind) {
      case ChartRangeKind.hour:
        return 'Интервал: последний час до текущего времени.';
      case ChartRangeKind.day:
        if (supportsLiveRefresh) {
          return 'Интервал: с полуночи до текущего времени.';
        }
        return 'Интервал: полные сутки выбранной даты.';
      case ChartRangeKind.week:
        return 'Интервал: последние 7 суток до текущего времени.';
      case ChartRangeKind.month:
        return 'Интервал: последние 30 суток до текущего времени.';
      case ChartRangeKind.calendarMonth:
        if (supportsLiveRefresh) {
          return 'Интервал: с 1-го числа до текущего времени.';
        }
        return 'Интервал: выбранный календарный месяц.';
    }
  }

  /// Формат оси X в зависимости от длины периода.
  String formatAxisTick(DateTime t) {
    final minutes = span.inMinutes;
    if (minutes <= 180) {
      return '${_pad2(t.hour)}:${_pad2(t.minute)}';
    }
    if (minutes <= 1440 * 2) {
      return '${_pad2(t.day)}.${_pad2(t.month)}\n${_pad2(t.hour)}:${_pad2(t.minute)}';
    }
    // Неделя / месяц: короче, в две строки — не вылезает за край.
    if (minutes <= 1440 * 40) {
      return '${_pad2(t.day)}.${_pad2(t.month)}\n${_pad2(t.hour)}:00';
    }
    return '${_pad2(t.day)}.${_pad2(t.month)}';
  }

  static String _fmtDay(DateTime d) =>
      '${_pad2(d.day)}.${_pad2(d.month)}.${d.year}';

  static String _fmtMonth(DateTime d) {
    const months = [
      'январь',
      'февраль',
      'март',
      'апрель',
      'май',
      'июнь',
      'июль',
      'август',
      'сентябрь',
      'октябрь',
      'ноябрь',
      'декабрь',
    ];
    return '${months[d.month - 1]} ${d.year}';
  }

  static String _pad2(int n) => n.toString().padLeft(2, '0');
}
