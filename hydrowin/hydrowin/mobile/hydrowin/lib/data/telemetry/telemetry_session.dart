import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:hydrowin/core/ble/telemetry_packet.dart';
import 'package:hydrowin/core/constants/app_constants.dart';
import 'package:hydrowin/data/demo/lite_demo_fleet.dart';
import 'package:hydrowin/data/local/app_preferences.dart';
import 'package:hydrowin/data/local/readings_repository.dart';
import 'package:hydrowin/data/local/sensor_config_repository.dart';
import 'package:hydrowin/data/local/service_fault_journal.dart';
import 'package:hydrowin/data/notifications/alert_notification_service.dart';
import 'package:hydrowin/data/remote/machines_repository.dart';
import 'package:hydrowin/domain/loop_current.dart';
import 'package:hydrowin/domain/models/cloud_sensor.dart';
import 'package:hydrowin/domain/models/live_sensor_reading.dart';
import 'package:hydrowin/domain/models/sensor_config.dart';
import 'package:hydrowin/domain/models/sensor_status_level.dart';
import 'package:hydrowin/domain/models/sensor_type.dart';
import 'package:hydrowin/domain/sensor_threshold_evaluator.dart';

enum TelemetryConnectionMode {
  disconnected,
  connecting,
  connected,
  server,
  demo,
}

class TelemetrySession extends ChangeNotifier {
  TelemetrySession(
    this._sensorRepo,
    this._readingsRepo,
    this._alerts, {
    MachinesRepository? machines,
    AppPreferences? preferences,
    ServiceFaultJournal? faultJournal,
  }) : _machines = machines,
       _preferences = preferences,
       _faultJournal = faultJournal;

  final SensorConfigRepository _sensorRepo;
  final ReadingsRepository _readingsRepo;
  final AlertNotificationService _alerts;
  final MachinesRepository? _machines;
  final AppPreferences? _preferences;
  final ServiceFaultJournal? _faultJournal;

  List<SensorConfig> _configs = [];
  final Map<int, LiveSensorReading> _readings = {};
  TelemetryConnectionMode _mode = TelemetryConnectionMode.disconnected;
  String? _deviceLabel;
  String? _error;
  DateTime? _lastPacketAt;
  Timer? _serverTimer;
  Timer? _demoTimer;
  StreamSubscription<TelemetryPacket>? _bleSub;
  int _pollSeconds = AppConstants.defaultPollSeconds;
  String? _serverMachineId;
  LiteDemoMachine? _demoMachine;
  int _demoTick = 0;
  final math.Random _demoRandom = math.Random();
  /// Машина, с которой синхронизированы локальные пороги (BLE / облако).
  String? _boundMachineId;

  /// Lite: ключ BLE-блока (MAC/id), для которого хранятся локальные конфиги.
  String? _bleDeviceKey;

  /// Кэш listSensors — не дергаем API на каждом тике.
  List<CloudSensor>? _cachedSensors;
  DateTime? _cachedSensorsAt;
  static const _sensorCacheTtl = Duration(seconds: 60);

  int _pollRefreshGen = 0;

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
  String? get boundMachineId => _boundMachineId;
  String? get bleDeviceKey => _bleDeviceKey;

  bool get isLive =>
      _mode == TelemetryConnectionMode.connected ||
      _mode == TelemetryConnectionMode.server ||
      _mode == TelemetryConnectionMode.demo;

  bool get isDemo => _mode == TelemetryConnectionMode.demo;
  LiteDemoMachine? get demoMachine => _demoMachine;

  void _log(String message) {
    if (kDebugMode) debugPrint(message);
  }

  Future<void> loadConfigs({String? deviceKey}) async {
    if (deviceKey != null && deviceKey.trim().isNotEmpty) {
      _bleDeviceKey = deviceKey.trim();
    }
    _configs = await _sensorRepo.load(
      deviceKey: AppConstants.isLite ? _bleDeviceKey : null,
    );
    final prefs = _preferences;
    if (prefs != null) {
      _pollSeconds = prefs.pollSeconds;
    }
    notifyListeners();
  }

  Future<void> saveConfigs(List<SensorConfig> configs) async {
    _configs = configs;
    final enabled = {
      for (final c in configs)
        if (c.enabled) c.channelIndex,
    };
    // Иначе «Живые каналы» продолжают показывать старые reading с прошлым enabled.
    _readings.removeWhere((ch, _) => !enabled.contains(ch));
    await _sensorRepo.save(
      configs,
      deviceKey: AppConstants.isLite ? _bleDeviceKey : null,
    );
    // Конфиги изменились — сбрасываем кэш датчиков сервера.
    _invalidateSensorCache();
    notifyListeners();
  }

  /// Локальная подпись блока (на этом ПК/телефоне), не имя в эфире BLE.
  Future<void> setBleDisplayName(String name) async {
    final key = _bleDeviceKey;
    final prefs = _preferences;
    if (key == null || prefs == null) return;
    final trimmed = name.trim();
    await prefs.setBleAlias(key, trimmed.isEmpty ? null : trimmed);
    _deviceLabel = trimmed.isEmpty ? key : trimmed;
    notifyListeners();
  }

  String resolveBleLabel(String deviceId, String fallback) {
    return _preferences?.resolveBleLabel(deviceId, fallback) ?? fallback;
  }

  /// Подтянуть имя/шкалу/пороги из облака (Настройка датчиков) в локальный BLE.
  Future<void> applyCloudConfigs(
    List<SensorConfig> cloudConfigs, {
    String? machineId,
  }) async {
    final byChannel = {
      for (final c in cloudConfigs) c.channelIndex: c.repairThresholds(),
    };

    if (machineId != null) {
      _boundMachineId = machineId;
      final maxCh = AppConstants.hardwareAnalogChannels;
      final replaced = <SensorConfig>[];
      for (var ch = 0; ch < maxCh; ch++) {
        final cloud = byChannel[ch];
        if (cloud != null) {
          replaced.add(cloud);
        } else {
          final local = _configs.where((c) => c.channelIndex == ch).firstOrNull;
          replaced.add(
            (local ?? SensorConfig.defaults(ch, SensorType.pressure))
                .copyWith(enabled: false),
          );
        }
      }
      await saveConfigs(replaced);
      return;
    }

    if (cloudConfigs.isEmpty) return;
    final merged = <SensorConfig>[];
    final seen = <int>{};
    for (final local in _configs) {
      final cloud = byChannel[local.channelIndex];
      if (cloud != null) {
        merged.add(cloud);
        seen.add(local.channelIndex);
      } else {
        merged.add(local);
      }
    }
    for (final entry in byChannel.entries) {
      if (!seen.contains(entry.key)) {
        merged.add(entry.value);
      }
    }
    merged.sort((a, b) => a.channelIndex.compareTo(b.channelIndex));
    await saveConfigs(merged);
  }

  Future<void> syncConfigsFromMachine(String machineId) async {
    final machines = _machines;
    if (machines == null) return;
    try {
      final sensors = await machines.listSensors(machineId);
      await applyCloudConfigs(
        sensors.map((s) => s.config).toList(),
        machineId: machineId,
      );
    } catch (e) {
      _log('⚠️ [TelemetrySession] syncConfigsFromMachine: $e');
    }
  }

  Future<void> setPollSeconds(int seconds, {bool persist = true}) async {
    _pollSeconds = seconds.clamp(
      AppConstants.minPollSeconds,
      AppConstants.maxPollSeconds,
    );
    if (persist) {
      await _preferences?.setPollSeconds(_pollSeconds);
    }
    if (_mode == TelemetryConnectionMode.server) {
      _restartServerTimer();
    } else if (_mode == TelemetryConnectionMode.demo) {
      _demoTimer?.cancel();
      _demoTimer = Timer.periodic(Duration(seconds: _pollSeconds), (_) {
        final m = _demoMachine;
        if (m == null || _mode != TelemetryConnectionMode.demo) return;
        _demoTick++;
        _applyDemoTick(m, _configs, live: true);
      });
    }
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
    _boundMachineId = machineId;
    _deviceLabel = label ?? 'Сервер';
    _mode = TelemetryConnectionMode.connecting;
    _error = null;
    notifyListeners();

    await syncConfigsFromMachine(machineId);
    await _pollServerOnce();
    if (_mode == TelemetryConnectionMode.connecting) {
      _mode = TelemetryConnectionMode.server;
    }
    _restartServerTimer();
    notifyListeners();
  }

  Future<void> startBle({
    required String label,
    required Stream<TelemetryPacket> packetStream,
    String? machineId,
    String? deviceId,
  }) async {
    await disconnect();
    _boundMachineId = machineId;
    if (deviceId != null && deviceId.trim().isNotEmpty) {
      _bleDeviceKey = deviceId.trim();
    }
    final resolvedLabel = (_bleDeviceKey != null)
        ? resolveBleLabel(_bleDeviceKey!, label)
        : label;
    _deviceLabel = resolvedLabel;
    _mode = TelemetryConnectionMode.connecting;
    _error = null;
    notifyListeners();

    if (AppConstants.isLite && _bleDeviceKey != null) {
      // Каждый блок — свой набор enabled/имён/порогов на телефоне.
      _readings.clear();
      _configs = await _sensorRepo.load(deviceKey: _bleDeviceKey);
      final enabled = {
        for (final c in _configs)
          if (c.enabled) c.channelIndex,
      };
      _readings.removeWhere((ch, _) => !enabled.contains(ch));
    } else if (machineId != null) {
      await syncConfigsFromMachine(machineId);
    }

    _bleSub = packetStream.listen(
      ingestBlePacket,
      onError: (Object error) {
        _error = 'Ошибка Bluetooth: $error';
        notifyListeners();
      },
    );

    _mode = TelemetryConnectionMode.connected;
    notifyListeners();
  }

  /// Локальный демо-поток для Lite (без BLE и API).
  Future<void> startLiteDemo(LiteDemoMachine machine) async {
    await disconnect();
    _demoMachine = machine;
    _boundMachineId = machine.id;
    _bleDeviceKey = 'demo_${machine.id}';
    _deviceLabel = machine.listLabel;
    _demoTick = 0;
    _mode = TelemetryConnectionMode.connecting;
    _error = null;
    notifyListeners();

    final configs = LiteDemoFleet.sensorConfigsFor(machine);
    // В память сессии; на диск — под ключ демо, не затирая конфиги реальных плат.
    _configs = configs;
    await _sensorRepo.save(configs, deviceKey: _bleDeviceKey);
    await _seedDemoHistory(machine, configs);

    if (machine.scenario == LiteDemoScenario.offline) {
      _applyDemoTick(machine, configs, live: false);
      _mode = TelemetryConnectionMode.disconnected;
      _error = 'Демо: блок офлайн — нет живых данных';
      _lastPacketAt = DateTime.now().subtract(const Duration(hours: 6));
      notifyListeners();
      return;
    }

    _mode = TelemetryConnectionMode.demo;
    _applyDemoTick(machine, configs, live: true);
    _demoTimer?.cancel();
    _demoTimer = Timer.periodic(Duration(seconds: _pollSeconds), (_) {
      final m = _demoMachine;
      if (m == null || _mode != TelemetryConnectionMode.demo) return;
      _demoTick++;
      _applyDemoTick(m, _configs, live: true);
    });
    notifyListeners();
  }

  void _applyDemoTick(
    LiteDemoMachine machine,
    List<SensorConfig> configs, {
    required bool live,
  }) {
    final values = LiteDemoFleet.liveValues(
      machine.scenario,
      tick: _demoTick,
      random: _demoRandom,
    );
    final now = live
        ? DateTime.now()
        : DateTime.now().subtract(const Duration(hours: 6));
    for (var i = 0; i < configs.length && i < values.length; i++) {
      final config = configs[i];
      if (!config.enabled) continue;
      final value = values[i];
      final status = SensorThresholdEvaluator.evaluate(config, value);
      final fault = switch (machine.scenario) {
        LiteDemoScenario.offline => LoopFault.open,
        _ => LoopFault.none,
      };
      final currentMa = LoopCurrent.resolve(
        config: config,
        packetValue: fault == LoopFault.none ? value : 1.1,
        fault: fault,
      );
      _readings[config.channelIndex] = LiveSensorReading(
        config: config,
        value: fault == LoopFault.none ? value : 0,
        status: fault != LoopFault.none
            ? SensorStatusLevel.critical
            : status,
        updatedAt: now,
        fromDeviceStatus: fault != LoopFault.none,
        loopFault: fault,
        currentMa: currentMa,
      );
    }
    if (live) {
      _lastPacketAt = now;
      _error = null;
      notifyListeners();
      unawaited(_persistAndAlert());
    } else {
      notifyListeners();
    }
  }

  Future<void> _seedDemoHistory(
    LiteDemoMachine machine,
    List<SensorConfig> configs,
  ) async {
    // ~45 минут истории для графиков / «как будто уже работали».
    final points = 45;
    for (var step = points; step >= 1; step--) {
      final values = LiteDemoFleet.liveValues(
        machine.scenario == LiteDemoScenario.offline
            ? LiteDemoScenario.ok
            : machine.scenario,
        tick: points - step,
        random: _demoRandom,
      );
      final at = DateTime.now().subtract(Duration(minutes: step));
      final batch = <int, LiveSensorReading>{};
      for (var i = 0; i < configs.length && i < values.length; i++) {
        final config = configs[i];
        if (!config.enabled) continue;
        final value = values[i];
        batch[config.channelIndex] = LiveSensorReading(
          config: config,
          value: value,
          status: SensorThresholdEvaluator.evaluate(config, value),
          updatedAt: at,
        );
      }
      if (batch.isNotEmpty) {
        await _readingsRepo.insertFromSession(batch);
      }
    }
  }

  Future<void> disconnect() async {
    _serverTimer?.cancel();
    _serverTimer = null;
    _demoTimer?.cancel();
    _demoTimer = null;
    await _bleSub?.cancel();
    _bleSub = null;
    _mode = TelemetryConnectionMode.disconnected;
    _deviceLabel = null;
    _serverMachineId = null;
    _boundMachineId = null;
    _demoMachine = null;
    _demoTick = 0;
    _readings.clear();
    _lastPacketAt = null;
    _error = null;
    _invalidateSensorCache();
    _lastPersistedValues.clear();
    _lastPersistedStatus.clear();
    _pollRefreshGen = 0;
    await _alerts.clearLiveSummary();
    notifyListeners();
  }

  void _invalidateSensorCache() {
    _cachedSensors = null;
    _cachedSensorsAt = null;
  }

  void _restartServerTimer() {
    _serverTimer?.cancel();
    unawaited(_pollServerOnce());
    _serverTimer = Timer.periodic(Duration(seconds: _pollSeconds), (_) {
      unawaited(_pollServerOnce());
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
    final gen = ++_pollRefreshGen;

    _log('⚡ [TelemetrySession] Опрос машины "$machineId"');

    try {
      final sensors = await _getSensorsCached(machines, machineId);
      _log('ℹ️ [TelemetrySession] Датчиков: ${sensors.length}');

      if (sensors.isEmpty) {
        _error = 'На сервере нет датчиков для этой машины';
        notifyListeners();
        return;
      }

      final live = await machines.getMachineLive(machineId);

      var received = false;
      for (final reading in live.sensors) {
        final sensor = sensors
            .where((s) => s.id == reading.id)
            .firstOrNull;
        if (sensor == null) continue;
        final config = _configs
            .where((c) => c.channelIndex == sensor.config.channelIndex)
            .firstOrNull;
        if (config == null || !config.enabled) continue;
        if (reading.value == null) continue;

        var fault = LoopCurrent.faultFromCloud(
          apiFault: reading.fault,
          currentMa: reading.currentMa,
          value: reading.value!,
          type: config.type,
        );
        if (fault == LoopFault.none) {
          fault = switch (reading.status.toLowerCase()) {
            'open' => LoopFault.open,
            'short' => LoopFault.short,
            _ => LoopFault.none,
          };
        }
        final status = SensorThresholdEvaluator.evaluate(
          config,
          reading.value!,
        );
        final level = fault != LoopFault.none
            ? SensorStatusLevel.critical
            : status;
        _readings[config.channelIndex] = LiveSensorReading(
          config: config,
          value: fault == LoopFault.none ? reading.value! : 0.0,
          status: level,
          updatedAt: (reading.ts ?? DateTime.now()).toLocal(),
          loopFault: fault,
          fromDeviceStatus: fault != LoopFault.none,
          currentMa: LoopCurrent.cloudCurrentMa(
            apiCurrentMa: reading.currentMa,
            fault: fault,
            value: reading.value!,
            config: config,
          ),
        );
        received = true;
      }

      if (gen != _pollRefreshGen) return;

      if (received) {
        _lastPacketAt = DateTime.now();
        _error = null;
        _mode = TelemetryConnectionMode.server;
        notifyListeners();
        await _persistAndAlert();
        _log('✅ [TelemetrySession] Данные обновлены.');
      } else if (_readings.isNotEmpty) {
        // Опрос прошёл, но новых точек нет — оставляем последние значения.
        _lastPacketAt = DateTime.now();
        _error = null;
        notifyListeners();
        _log('ℹ️ [TelemetrySession] Нет новых точек, показаны последние значения.');
      } else {
        _error = 'Нет свежих данных с сервера';
        notifyListeners();
        _log('❌ [TelemetrySession] Нет точек ни по одному датчику.');
      }
    } catch (e) {
      if (gen != _pollRefreshGen) return;
      _error = 'Ошибка связи с сервером: $e';
      notifyListeners();
      _log('🚨 [TelemetrySession] ОШИБКА: $e');
      // При ошибке сбрасываем кэш — следующий тик перезапросит listSensors.
      _invalidateSensorCache();
    }
  }

  void _onPacket(TelemetryPacket packet) {
    _lastPacketAt = DateTime.now();

    for (final ch in packet.channels) {
      final config = _configs
          .where((c) => c.channelIndex == ch.channelIndex)
          .firstOrNull;
      if (config == null || !config.enabled) continue;

      // Статус с платы (обрыв/КЗ) важнее локальных порогов по value.
      final fromDevice =
          ch.loopFault != LoopFault.none ||
          ch.level == SensorStatusLevel.warning ||
          ch.level == SensorStatusLevel.critical;
      final status = fromDevice
          ? ch.level
          : SensorThresholdEvaluator.evaluate(config, ch.value);

      // При обрыве/КЗ в value может быть реальный ток (мА) с платы.
      final engineeringValue =
          ch.loopFault == LoopFault.none ? ch.value : 0.0;
      final currentMa = LoopCurrent.resolve(
        config: config,
        packetValue: ch.value,
        fault: ch.loopFault,
      );

      _readings[ch.channelIndex] = LiveSensorReading(
        config: config,
        value: engineeringValue,
        status: status,
        updatedAt: packet.timestamp,
        fromDeviceStatus: fromDevice,
        loopFault: ch.loopFault,
        currentMa: currentMa,
      );
    }
    notifyListeners();
    _persistAndAlert();
  }

  void ingestBlePacket(TelemetryPacket packet) {
    _mode = TelemetryConnectionMode.connected;
    _error = null;
    _onPacket(packet);
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

      // Алерты и гарантийный журнал — по всем актуальным значениям.
      for (final r in _readings.values) {
        await _alerts.maybeNotify(r);
        await _faultJournal?.maybeRecord(r, deviceLabel: _deviceLabel);
      }
      await _updateLiveSummary();
    } catch (_) {}
  }

  Future<void> _updateLiveSummary() async {
    if (_readings.isEmpty) return;
    final title = _deviceLabel == null
        ? 'ГидроВин · датчики'
        : 'ГидроВин · $_deviceLabel';
    final sorted = _readings.values.toList()
      ..sort((a, b) => a.config.channelIndex.compareTo(b.config.channelIndex));
    final body = sorted
        .map((r) => '${r.config.name}: ${r.formattedValue}')
        .join('\n');
    await _alerts.updateLiveSummary(title, body);
  }

  @override
  void dispose() {
    _serverTimer?.cancel();
    _demoTimer?.cancel();
    _bleSub?.cancel();
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
