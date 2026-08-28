import 'package:flutter/material.dart';
import 'package:hydrowin/features/chart/chart_export.dart';

enum ChartExportAction {
  todayCsv,
  todayXlsx,
  todayPdf,
  period,
}

/// Кнопка AppBar: экспорт текущего дня или произвольного периода.
class ChartExportButton extends StatelessWidget {
  const ChartExportButton({
    required this.onTodayExport,
    required this.onPeriodExport,
    super.key,
  });

  final ValueChanged<ChartExportFormat> onTodayExport;
  final VoidCallback onPeriodExport;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ChartExportAction>(
      tooltip: 'Экспорт',
      icon: const Icon(Icons.download),
      onSelected: (action) {
        switch (action) {
          case ChartExportAction.todayCsv:
            onTodayExport(ChartExportFormat.csv);
          case ChartExportAction.todayXlsx:
            onTodayExport(ChartExportFormat.xlsx);
          case ChartExportAction.todayPdf:
            onTodayExport(ChartExportFormat.pdf);
          case ChartExportAction.period:
            onPeriodExport();
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          enabled: false,
          child: Text('Текущий день', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        PopupMenuItem(
          value: ChartExportAction.todayCsv,
          child: Text('CSV'),
        ),
        PopupMenuItem(
          value: ChartExportAction.todayXlsx,
          child: Text('Excel (.xlsx)'),
        ),
        PopupMenuItem(
          value: ChartExportAction.todayPdf,
          child: Text('PDF-отчёт'),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: ChartExportAction.period,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.date_range),
            title: Text('За период…'),
            subtitle: Text('например, полгода'),
          ),
        ),
      ],
    );
  }
}
