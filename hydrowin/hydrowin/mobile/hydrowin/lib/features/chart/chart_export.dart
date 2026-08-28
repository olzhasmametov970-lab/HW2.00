import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hydrowin/domain/models/reading_point.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

enum ChartExportFormat {
  csv,
  xlsx,
  pdf;

  String get label => switch (this) {
    ChartExportFormat.csv => 'CSV',
    ChartExportFormat.xlsx => 'Excel (.xlsx)',
    ChartExportFormat.pdf => 'PDF-отчёт',
  };

  String get extension => switch (this) {
    ChartExportFormat.csv => 'csv',
    ChartExportFormat.xlsx => 'xlsx',
    ChartExportFormat.pdf => 'pdf',
  };
}

/// Экспорт точек графика и статистики: CSV / Excel / PDF.
abstract final class ChartExport {
  static Future<File> save({
    required ChartExportFormat format,
    required List<ReadingPoint> points,
    required String sensorName,
    required String unit,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    ReadingStats? stats,
    String? machineLabel,
    double? engineHours,
    String? resolutionNote,
  }) async {
    final bytes = switch (format) {
      ChartExportFormat.csv => Uint8List.fromList(
        utf8.encode(
          _buildCsv(
            points: points,
            sensorName: sensorName,
            unit: unit,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            stats: stats,
            machineLabel: machineLabel,
            engineHours: engineHours,
            resolutionNote: resolutionNote,
          ),
        ),
      ),
      ChartExportFormat.xlsx => _buildXlsx(
        points: points,
        sensorName: sensorName,
        unit: unit,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        stats: stats,
        machineLabel: machineLabel,
        engineHours: engineHours,
        resolutionNote: resolutionNote,
      ),
      ChartExportFormat.pdf => await _buildPdf(
        points: points,
        sensorName: sensorName,
        unit: unit,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        stats: stats,
        machineLabel: machineLabel,
        engineHours: engineHours,
        resolutionNote: resolutionNote,
      ),
    };

    final dir =
        await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final safeName = sensorName
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .trim()
        .replaceAll(' ', '_');
    final fileName =
        'hydrowin_${safeName}_${DateFormat('yyyyMMdd').format(rangeStart)}.${format.extension}';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static String _buildCsv({
    required List<ReadingPoint> points,
    required String sensorName,
    required String unit,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    ReadingStats? stats,
    String? machineLabel,
    double? engineHours,
    String? resolutionNote,
  }) {
    final buf = StringBuffer()
      ..writeln('sensor,unit,from,to,machine')
      ..writeln(
        '"$sensorName","$unit",'
        '"${rangeStart.toIso8601String()}","${rangeEnd.toIso8601String()}",'
        '"${machineLabel ?? ''}"',
      );

    if (stats != null) {
      buf
        ..writeln('metric,value')
        ..writeln('avg,${stats.avg}')
        ..writeln('min,${stats.min}')
        ..writeln('max,${stats.max}')
        ..writeln('pct_in_norm,${stats.pctInNorm}')
        ..writeln('pct_warning,${stats.pctWarning}')
        ..writeln('pct_critical,${stats.pctCritical}')
        ..writeln('block_online_min,${stats.BLOCKOnlineMinutes}');
      if (stats.pumpRunMinutes != null) {
        buf.writeln('pump_run_min,${stats.pumpRunMinutes}');
      }
      if (stats.pumpStarts != null) {
        buf.writeln('pump_starts,${stats.pumpStarts}');
      }
      if (engineHours != null) {
        buf.writeln('engine_hours,$engineHours');
      }
      if (resolutionNote != null && resolutionNote.isNotEmpty) {
        buf.writeln('aggregation,"$resolutionNote"');
      }
    }

    buf.writeln('ts,value,status');
    final tsFmt = DateFormat('yyyy-MM-dd HH:mm:ss');
    for (final p in points) {
      buf.writeln(
        '${tsFmt.format(p.recordedAt.toLocal())},${p.value},${p.status.name}',
      );
    }
    return buf.toString();
  }

  static Uint8List _buildXlsx({
    required List<ReadingPoint> points,
    required String sensorName,
    required String unit,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    ReadingStats? stats,
    String? machineLabel,
    double? engineHours,
    String? resolutionNote,
  }) {
    final excel = Excel.createExcel();
    final summaryName = 'Сводка';
    final defaultSheet = excel.getDefaultSheet()!;
    excel.rename(defaultSheet, summaryName);
    final summary = excel[summaryName];

    void row(int r, List<String> cells) {
      for (var c = 0; c < cells.length; c++) {
        summary
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
            .value = TextCellValue(
          cells[c],
        );
      }
    }

    row(0, ['HydroWin — экспорт датчика']);
    row(1, ['Датчик', sensorName]);
    row(2, ['Единица', unit]);
    row(3, ['Машина', machineLabel ?? '—']);
    row(4, [
      'Период',
      '${DateFormat('dd.MM.yyyy HH:mm').format(rangeStart.toLocal())} — '
          '${DateFormat('dd.MM.yyyy HH:mm').format(rangeEnd.toLocal())}',
    ]);
    row(5, ['Точек', '${points.length}']);

    var r = 7;
    if (stats != null) {
      row(r++, ['Статистика', 'Значение']);
      row(r++, ['Среднее', stats.avg.toStringAsFixed(2)]);
      row(r++, ['Минимум', stats.min.toStringAsFixed(2)]);
      row(r++, ['Максимум', stats.max.toStringAsFixed(2)]);
      row(r++, ['В норме, %', stats.pctInNorm.toStringAsFixed(1)]);
      row(r++, ['Warning, %', stats.pctWarning.toStringAsFixed(1)]);
      row(r++, ['Критично, %', stats.pctCritical.toStringAsFixed(1)]);
      row(r++, [
        'Блок онлайн, мин',
        stats.BLOCKOnlineMinutes.toStringAsFixed(1),
      ]);
      if (stats.pumpRunMinutes != null) {
        row(r++, ['Насос, мин', stats.pumpRunMinutes!.toStringAsFixed(1)]);
      }
      if (stats.pumpStarts != null) {
        row(r++, ['Запусков насоса', '${stats.pumpStarts}']);
      }
      if (engineHours != null) {
        row(r++, ['Моточасы', engineHours.toStringAsFixed(1)]);
      }
      if (resolutionNote != null && resolutionNote.isNotEmpty) {
        row(r++, ['Агрегация', resolutionNote]);
      }
      r++;
    }

    final data = excel['Данные'];
    data.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value =
        TextCellValue('Время');
    data.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0)).value =
        TextCellValue('Значение');
    data.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 0)).value =
        TextCellValue('Статус');

    final tsFmt = DateFormat('yyyy-MM-dd HH:mm:ss');
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      data
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1))
          .value = TextCellValue(
        tsFmt.format(p.recordedAt.toLocal()),
      );
      data
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1))
          .value = DoubleCellValue(
        p.value,
      );
      data
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: i + 1))
          .value = TextCellValue(
        p.status.name,
      );
    }

    final encoded = excel.encode();
    if (encoded == null) {
      throw StateError('Не удалось сформировать Excel-файл');
    }
    return Uint8List.fromList(encoded);
  }

  static Future<Uint8List> _buildPdf({
    required List<ReadingPoint> points,
    required String sensorName,
    required String unit,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    ReadingStats? stats,
    String? machineLabel,
    double? engineHours,
    String? resolutionNote,
  }) async {
    final fonts = await _loadPdfFonts();
    final doc = pw.Document();
    final dateFmt = DateFormat('dd.MM.yyyy HH:mm');
    final tsFmt = DateFormat('dd.MM.yyyy HH:mm:ss');

    String dur(double minutes) {
      final rounded = minutes.round();
      return '${rounded ~/ 60}ч ${rounded % 60}мин';
    }

    final metaRows = <List<String>>[
      ['Датчик', sensorName],
      ['Единица', unit],
      if (machineLabel != null && machineLabel.isNotEmpty)
        ['Машина', machineLabel],
      [
        'Период',
        '${dateFmt.format(rangeStart.toLocal())} — ${dateFmt.format(rangeEnd.toLocal())}',
      ],
      ['Точек', '${points.length}'],
    ];

    final statRows = <List<String>>[];
    if (stats != null) {
      statRows.addAll([
        ['Среднее', '${stats.avg.toStringAsFixed(1)} $unit'],
        ['Минимум', '${stats.min.toStringAsFixed(1)} $unit'],
        ['Максимум', '${stats.max.toStringAsFixed(1)} $unit'],
        ['Время в норме', '${stats.pctInNorm.toStringAsFixed(0)}%'],
        ['Warning', '${stats.pctWarning.toStringAsFixed(0)}%'],
        ['Критично', '${stats.pctCritical.toStringAsFixed(0)}%'],
        ['Работа блока', dur(stats.BLOCKOnlineMinutes)],
      ]);
      if (stats.pumpRunMinutes != null) {
        statRows.add(['Работа насоса', dur(stats.pumpRunMinutes!)]);
      }
      if (stats.pumpStarts != null) {
        statRows.add(['Запусков насоса', '${stats.pumpStarts}']);
      }
      if (engineHours != null) {
        statRows.add(['Моточасы', dur(engineHours * 60)]);
      }
      if (resolutionNote != null && resolutionNote.isNotEmpty) {
        statRows.add(['Агрегация', resolutionNote]);
      }
    }

    // В PDF — сводка + таблица точек (многостраничная).
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'HydroWin — отчёт по датчику',
              style: pw.TextStyle(font: fonts.bold, fontSize: 16),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Стр. ${context.pageNumber} / ${context.pagesCount}',
              style: pw.TextStyle(font: fonts.regular, fontSize: 9),
            ),
            pw.Divider(),
          ],
        ),
        build: (context) {
          final widgets = <pw.Widget>[
            _pdfKeyValueTable(metaRows, fonts),
            pw.SizedBox(height: 16),
          ];

          if (statRows.isNotEmpty) {
            widgets.addAll([
              pw.Text(
                'Статистика за период',
                style: pw.TextStyle(font: fonts.bold, fontSize: 13),
              ),
              pw.SizedBox(height: 8),
              _pdfKeyValueTable(statRows, fonts),
              pw.SizedBox(height: 16),
            ]);
          }

          widgets.addAll([
            pw.Text(
              'Показания',
              style: pw.TextStyle(font: fonts.bold, fontSize: 13),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: ['Время', 'Значение', 'Статус'],
              data: [
                for (final p in points)
                  [
                    tsFmt.format(p.recordedAt.toLocal()),
                    p.value.toStringAsFixed(2),
                    p.status.name,
                  ],
              ],
              headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 9),
              cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 8),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFE8EEF5),
              ),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerRight,
                2: pw.Alignment.center,
              },
              border: pw.TableBorder.all(
                color: const PdfColor.fromInt(0xFFCCCCCC),
                width: 0.4,
              ),
            ),
          ]);

          return widgets;
        },
      ),
    );

    return Uint8List.fromList(await doc.save());
  }

  static pw.Widget _pdfKeyValueTable(List<List<String>> rows, _PdfFonts fonts) {
    return pw.Table(
      columnWidths: {
        0: const pw.FlexColumnWidth(1.2),
        1: const pw.FlexColumnWidth(2),
      },
      children: [
        for (final row in rows)
          pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 3),
                child: pw.Text(
                  row[0],
                  style: pw.TextStyle(font: fonts.bold, fontSize: 10),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 3),
                child: pw.Text(
                  row[1],
                  style: pw.TextStyle(font: fonts.regular, fontSize: 10),
                ),
              ),
            ],
          ),
      ],
    );
  }

  static Future<_PdfFonts> _loadPdfFonts() async {
    try {
      final regularData = await rootBundle.load(
        'assets/fonts/NotoSans-Regular.ttf',
      );
      final boldData = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
      return _PdfFonts(
        regular: pw.Font.ttf(regularData),
        bold: pw.Font.ttf(boldData),
      );
    } catch (_) {
      // Fallback: шрифты Google (кэш printing) — для кириллицы.
      final regular = await PdfGoogleFonts.notoSansRegular();
      final bold = await PdfGoogleFonts.notoSansBold();
      return _PdfFonts(regular: regular, bold: bold);
    }
  }
}

class _PdfFonts {
  const _PdfFonts({required this.regular, required this.bold});
  final pw.Font regular;
  final pw.Font bold;
}
