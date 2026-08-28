import 'package:hydrowin/core/constants/app_constants.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static AppDatabase? _instance;

  static Future<AppDatabase> open() async {
    if (_instance != null) return _instance!;
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'hydrowin.db');
    final db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await _createV1(db);
        await _createServiceFaults(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createServiceFaults(db);
        }
      },
    );
    _instance = AppDatabase._(db);
    return _instance!;
  }

  static Future<void> _createV1(Database db) async {
    await db.execute('''
      CREATE TABLE readings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        channel_index INTEGER NOT NULL,
        value REAL NOT NULL,
        status TEXT NOT NULL,
        recorded_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_readings_ch_time ON readings(channel_index, recorded_at)',
    );
  }

  static Future<void> _createServiceFaults(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS service_faults (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        channel_index INTEGER NOT NULL,
        sensor_name TEXT NOT NULL,
        title TEXT NOT NULL,
        detail TEXT NOT NULL,
        status TEXT NOT NULL,
        loop_fault TEXT NOT NULL,
        current_ma REAL,
        engineering_value REAL,
        device_label TEXT,
        recorded_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_service_faults_time '
      'ON service_faults(recorded_at DESC)',
    );
  }

  static Future<void> close() async {
    await _instance?.db.close();
    _instance = null;
  }
}

extension ReadingRetention on AppDatabase {
  int get retentionMs => AppConstants.localHistoryDays * 24 * 60 * 60 * 1000;
}
