import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hydrowin/core/ble/telemetry_packet.dart';
import 'package:hydrowin/data/ble/demo_telemetry.dart';
import 'package:hydrowin/core/constants/app_constants.dart';
import 'package:hydrowin/data/local/app_preferences.dart';
import 'package:hydrowin/data/local/readings_repository.dart';
import 'package:hydrowin/data/local/sensor_config_repository.dart';
import 'package:hydrowin/data/notifications/alert_notification_service.dart';
import 'package:hydrowin/data/remote/machines_repository.dart';
import 'package:hydrowin/domain/models/cloud_sensor.dart';
import 'package:hydrowin/domain/models/live_sensor_reading.dart';
import 'package:hydrowin/domain/models/sensor_config.dart';
import 'package:hydrowin/domain/sensor_threshold_evaluator.dart';

enum TelemetryConnectionMode {
  disconnected,
  connecting,
  connected,
  demo,
  server,
}

class TelemetrySession extends ChangeNotifier {
  TelemetrySession(
    this._sensorRepo,
    this._readingsRepo,
    this._alerts, {
    MachinesRepository? machines,
    AppPreferences? preferences,
  })  : _machines = machines,
        _preferences = preferences;

  final SensorConfigRepository _sensorRepo;
  final ReadingsRepository _readingsRepo;
  final AlertNotificationService _alerts;
  final MachinesRepository? _machines;
  final AppPreferences? _preferences;

  List<SensorConfig> _configs = [];
  final Map<int, LiveSensorReading> _readings = {};
  TelemetryConnectionMode _mode = TelemetryConnectionMode.disconnected;
  String? _deviceLabel;
  String? _error;
  DateTime? _lastPacketAt;
  Timer? _demoTimer;
  Timer? _serverTimer;
  int _pollSeconds = AppConstants.defaultPollSeconds;
  String? _serverMachineId;

  /// Кэш listSensors — не дергаем API на каждом тике.
  List<CloudSensor>? _cachedSensors;
  DateTime? _cachedSensorsAt;
  static const _sensorCacheTtl = Duration(seconds: 60);

  bool _pollInFlight = false;

  /// Последние значения, записанные в SQLite (чтобы не писать без изменений).
  final Map<int, double> _lastPersistedValues = {};
  final Map<int, String> _lastPersistedStatus = {};

  List<SensorConfig> get configs => List.unmodifiable(_configs);
  Map<int, LiveSensorReading> get readings => Map.unmodifiable(_readings);
  TelemetryConnectionMode get mode => _mode;
  String? get deviceLabel => _deviceLabel;
  String? get error => _error;
  DateTime? get lastPacketAt => _lastPacketAt;
  int get pollSeconds => _pollSeconds;

  bool get isLive =>
      _mode == TelemetryConnectionMode.connected ||
      _mode == TelemetryConnectionMode.demo ||
      _mode == TelemetryConnectionMode.server;

  void _log(String message) {
    if (kDebugMode) debugPrint(message);
  }

  Future<void> loadConfigs() async {
    _configs = await _sensorRepo.load();
    final prefs = _preferences;
    if (prefs != null) {
      _pollSeconds = prefs.pollSeconds;
    }
    notifyListeners();
  }

  Future<void> saveConfigs(List<SensorConfig> configs) async {
    _configs = configs;
    await _sensorRepo.save(configs);
    // Конфиги изменились — сбрасываем кэш датчиков сервера.
    _invalidateSensorCache();
    notifyListeners();
  }

  Future<void> setPollSeconds(int seconds, {bool persist = true}) async {
    _pollSeconds = seconds.clamp(
      AppConstants.minPollSeconds,
      AppConstants.maxPollSeconds,
    );
    if (persist) {
      await _preferences?.setPollSeconds(_pollSeconds);
    }
    if (_mode == TelemetryConnectionMode.demo) {
      _restartDemoTimer();
    } else if (_mode == TelemetryConnectionMode.server) {
      _restartServerTimer();
    }
    notifyListeners();
  }

  Future<void> startDemo() async {
    await disconnect();
    _deviceLabel = 'Демо (без сервера)';
    _mode = TelemetryConnectionMode.demo;
    _restartDemoTimer();
    _onPacket(DemoTelemetry.next(_configs));
    notifyListeners();
  }

  Future<void> startServerPolling({
    required String machineId,
    String? label,
  }) async {
    if (_machines == null) {
      _error = 'Сервер недоступен';
      notifyListeners();
      return;
    }

    await disconnect();
    _serverMachineId = machineId;
    _deviceLabel = label ?? 'Сервер';
    _mode = TelemetryConnectionMode.connecting;
    _error = null;
    notifyListeners();

    await _pollServerOnce();
    if (_mode == TelemetryConnectionMode.connecting) {
      _mode = TelemetryConnectionMode.server;
    }
    _restartServerTimer();
    notifyListeners();
  }

  Future<void> disconnect() async {
    _demoTimer?.cancel();
    _demoTimer = null;
    _serverTimer?.cancel();
    _serverTimer = null;
    _mode = TelemetryConnectionMode.disconnected;
    _deviceLabel = null;
    _serverMachineId = null;
    _readings.clear();
    _lastPacketAt = null;
    _error = null;
    _invalidateSensorCache();
    _lastPersistedValues.clear();
    _lastPersistedStatus.clear();
    _pollInFlight = false;
    notifyListeners();
  }

  void _invalidateSensorCache() {
    _cachedSensors = null;
    _cachedSensorsAt = null;
  }

  void _restartDemoTimer() {
    _demoTimer?.cancel();
    _demoTimer = Timer.periodic(Duration(seconds: _pollSeconds), (_) {
      DemoTelemetry.bumpTemperature();
      _onPacket(DemoTelemetry.next(_configs));
    });
  }

  void _restartServerTimer() {
    _serverTimer?.cancel();
    _serverTimer = Timer.periodic(Duration(seconds: _pollSeconds), (_) {
      _pollServerOnce();
    });
  }

  Future<List<CloudSensor>> _getSensorsCached(
    MachinesRepository machines,
    String machineId,
  ) async {
    final now = DateTime.now();
    final cached = _cachedSensors;
    final cachedAt = _cachedSensorsAt;
    if (cached != null &&
        cachedAt != null &&
        now.difference(cachedAt) < _sensorCacheTtl) {
      return cached;
    }

    final sensors = await machines.listSensors(machineId);
    _cachedSensors = sensors;
    _cachedSensorsAt = now;
    return sensors;
  }

  bool _valueChanged(LiveSensorReading reading) {
    final ch = reading.config.channelIndex;
    final prev = _lastPersistedValues[ch];
    final prevStatus = _lastPersistedStatus[ch];
    if (prev == null || prevStatus == null) return true;
    if (prevStatus != reading.status.name) return true;
    // Игнорируем микрошум ADC (~0.05 единицы шкалы).
    return (prev - reading.value).abs() >= 0.05;
  }

  Future<void> _pollServerOnce() async {
    final machines = _machines;
    final machineId = _serverMachineId;
    if (machines == null || machineId == null) return;
    if (_pollInFlight) return;
    _pollInFlight = true;

    _log('⚡ [TelemetrySession] Опрос машины "$machineId"');

    try {
      final sensors = await _getSensorsCached(machines, machineId);
      _log('ℹ️ [TelemetrySession] Датчиков: ${sensors.length}');

      if (sensors.isEmpty) {
        _error = 'На сервере нет датчиков для этой машины';
        notifyListeners();
        return;
      }

      final lookbackMinutes = (_pollSeconds * 3 / 60).ceil().clamp(5, 30);

      // Готовим пары (config, sensor) для параллельного опроса.
      final jobs = <({SensorConfig config, CloudSensor sensor})>[];
      for (final sensor in sensors) {
        final config = _configs
            .where((c) => c.channelIndex == sensor.config.channelIndex)
            .firstOrNull;
        if (config == null) {
          _log(
            '⚠️ [TelemetrySession] Пропуск "${sensor.id}": '
            'нет локальной настройки канала ${sensor.config.channelIndex}',
          );
          continue;
        }
        if (!config.enabled) continue;
        jobs.add((config: config, sensor: sensor));
      }

      if (jobs.isEmpty) {
        _error = 'Нет включённых датчиков для опроса';
        notifyListeners();
        return;
      }

      // Параллельные getReadings вместо последовательных.
      final results = await Future.wait(
        jobs.map((job) async {
          final series = await machines.getReadings(
            machineId,
            job.sensor.id,
            minutes: lookbackMinutes,
            channelIndex: job.sensor.config.channelIndex,
          );
          return (config: job.config, series: series);
        }),
      );

      var received = false;
      for (final result in results) {
        if (result.series.points.isEmpty) continue;
        final last = result.series.points.last;
        final status =
            SensorThresholdEvaluator.evaluate(result.config, last.value);
        _readings[result.config.channelIndex] = LiveSensorReading(
          config: result.config,
          value: last.value,
          status: status,
          updatedAt: last.recordedAt.toLocal(),
        );
        received = true;
      }

      if (received) {
        _lastPacketAt = DateTime.now();
        _error = null;
        _mode = TelemetryConnectionMode.server;
        notifyListeners();
        await _persistAndAlert();
        _log('✅ [TelemetrySession] Данные обновлены.');
      } else {
        _error = 'Нет свежих данных с сервера';
        notifyListeners();
        _log('❌ [TelemetrySession] Нет точек ни по одному датчику.');
      }
    } catch (e) {
      _error = 'Ошибка связи с сервером: $e';
      notifyListeners();
      _log('🚨 [TelemetrySession] ОШИБКА: $e');
      // При ошибке сбрасываем кэш — следующий тик перезапросит listSensors.
      _invalidateSensorCache();
    } finally {
      _pollInFlight = false;
    }
  }

  void _onPacket(TelemetryPacket packet) {
    _lastPacketAt = DateTime.now();

    for (final ch in packet.channels) {
      final config = _configs
          .where((c) => c.channelIndex == ch.channelIndex)
          .firstOrNull;
      if (config == null || !config.enabled) continue;

      final status = SensorThresholdEvaluator.evaluate(config, ch.value);
      _readings[ch.channelIndex] = LiveSensorReading(
        config: config,
        value: ch.value,
        status: status,
        updatedAt: packet.timestamp,
      );
    }
    notifyListeners();
    _persistAndAlert();
  }

  Future<void> _persistAndAlert() async {
    if (_readings.isEmpty) return;
    try {
      final changed = <int, LiveSensorReading>{};
      for (final entry in _readings.entries) {
        if (_valueChanged(entry.value)) {
          changed[entry.key] = entry.value;
        }
      }

      if (changed.isNotEmpty) {
        await _readingsRepo.insertFromSession(changed);
        for (final r in changed.values) {
          _lastPersistedValues[r.config.channelIndex] = r.value;
          _lastPersistedStatus[r.config.channelIndex] = r.status.name;
        }
      }

      // Алерты — по всем актуальным значениям (не только изменённым).
      for (final r in _readings.values) {
        await _alerts.maybeNotify(r);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _demoTimer?.cancel();
    _serverTimer?.cancel();
    super.dispose();
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
