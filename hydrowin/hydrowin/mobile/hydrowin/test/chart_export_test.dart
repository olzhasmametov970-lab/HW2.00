import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydrowin/core/theme/app_theme.dart';
import 'package:hydrowin/domain/models/reading_point.dart';
import 'package:hydrowin/features/chart/chart_export.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getDownloadsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hydrowin_export_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  final points = [
    ReadingPoint(
      channelIndex: 0,
      value: 120.5,
      status: SensorStatusLevel.ok,
      recordedAt: DateTime.utc(2026, 7, 15, 10),
    ),
    ReadingPoint(
      channelIndex: 0,
      value: 180,
      status: SensorStatusLevel.warning,
      recordedAt: DateTime.utc(2026, 7, 15, 11),
    ),
  ];

  final stats = ReadingStats(
    avg: 150.25,
    min: 120.5,
    max: 180,
    pctInNorm: 50,
    pctWarning: 50,
    pctCritical: 0,
    warningCount: 1,
    criticalCount: 0,
    count: 2,
    BLOCKOnlineMinutes: 60,
    pumpRunMinutes: 30,
    pumpStarts: 1,
  );

  test('CSV export writes utf-8 file with points and stats', () async {
    final file = await ChartExport.save(
      format: ChartExportFormat.csv,
      points: points,
      sensorName: 'Давление',
      unit: 'бар',
      rangeStart: DateTime.utc(2026, 7, 15),
      rangeEnd: DateTime.utc(2026, 7, 16),
      stats: stats,
      machineLabel: '001',
    );

    expect(file.path.endsWith('.csv'), isTrue);
    final text = await file.readAsString();
    expect(text, contains('Давление'));
    expect(text, contains('avg,150.25'));
    expect(text, contains('120.5,ok'));
  });

  test('Excel export writes xlsx with ZIP signature', () async {
    final file = await ChartExport.save(
      format: ChartExportFormat.xlsx,
      points: points,
      sensorName: 'Давление',
      unit: 'бар',
      rangeStart: DateTime.utc(2026, 7, 15),
      rangeEnd: DateTime.utc(2026, 7, 16),
      stats: stats,
    );

    expect(file.path.endsWith('.xlsx'), isTrue);
    final bytes = await file.readAsBytes();
    // XLSX = ZIP: PK
    expect(bytes[0], 0x50);
    expect(bytes[1], 0x4B);
    expect(bytes.length, greaterThan(100));
  });
}
