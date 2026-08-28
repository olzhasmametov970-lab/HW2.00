import 'package:flutter/material.dart';
import 'package:hydrowin/features/chart/chart_time_range.dart';

/// Чипы периода: час / день / неделя / месяц / календарный месяц.
class ChartRangeSelector extends StatelessWidget {
  const ChartRangeSelector({
    required this.value,
    required this.onChanged,
    this.compact = false,
    super.key,
  });

  final ChartTimeRange value;
  final ValueChanged<ChartTimeRange> onChanged;
  final bool compact;

  Future<void> _pickDay(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: value.kind == ChartRangeKind.day ? value.anchor : DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('ru'),
    );
    if (picked == null) return;
    onChanged(ChartTimeRange.day(picked));
  }

  Future<void> _pickCalendarMonth(BuildContext context) async {
    final now = DateTime.now();
    var year = value.kind == ChartRangeKind.calendarMonth
        ? value.anchor.year
        : now.year;
    var month = value.kind == ChartRangeKind.calendarMonth
        ? value.anchor.month
        : now.month;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            title: const Text('Выбор месяца'),
            content: Row(
              children: [
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Месяц'),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        isExpanded: true,
                        value: month,
                        items: [
                          for (var m = 1; m <= 12; m++)
                            DropdownMenuItem(
                              value: m,
                              child: Text(_monthName(m)),
                            ),
                        ],
                        onChanged: (v) {
                          if (v != null) setLocal(() => month = v);
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Год'),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        isExpanded: true,
                        value: year,
                        items: [
                          for (var y = now.year; y >= 2020; y--)
                            DropdownMenuItem(value: y, child: Text('$y')),
                        ],
                        onChanged: (v) {
                          if (v != null) setLocal(() => year = v);
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('ОК'),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true) return;
    // Не даём выбрать будущий месяц.
    final candidate = DateTime(year, month, 1);
    final firstThisMonth = DateTime(now.year, now.month, 1);
    if (candidate.isAfter(firstThisMonth)) return;
    onChanged(ChartTimeRange.calendarMonth(candidate));
  }

  static String _monthName(int m) {
    const names = [
      'Январь',
      'Февраль',
      'Март',
      'Апрель',
      'Май',
      'Июнь',
      'Июль',
      'Август',
      'Сентябрь',
      'Октябрь',
      'Ноябрь',
      'Декабрь',
    ];
    return names[m - 1];
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: compact ? 6 : 8,
      runSpacing: 8,
      children: [
        for (final kind in ChartRangeKind.values)
          ChoiceChip(
            label: Text(kind.shortLabel),
            selected: value.kind == kind,
            onSelected: (_) async {
              switch (kind) {
                case ChartRangeKind.hour:
                  onChanged(ChartTimeRange.hour());
                case ChartRangeKind.day:
                  if (value.kind == ChartRangeKind.day) {
                    await _pickDay(context);
                  } else {
                    onChanged(ChartTimeRange.day(DateTime.now()));
                  }
                case ChartRangeKind.week:
                  onChanged(ChartTimeRange.week());
                case ChartRangeKind.month:
                  onChanged(ChartTimeRange.month());
                case ChartRangeKind.calendarMonth:
                  await _pickCalendarMonth(context);
              }
            },
          ),
        if (value.kind == ChartRangeKind.day)
          IconButton(
            tooltip: 'Выбрать день',
            visualDensity: VisualDensity.compact,
            onPressed: () => _pickDay(context),
            icon: const Icon(Icons.calendar_today, size: 20),
          ),
      ],
    );
  }
}
