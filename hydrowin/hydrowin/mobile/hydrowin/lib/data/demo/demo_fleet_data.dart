import 'dart:math' as math;

import 'package:hydrowin/domain/models/auth_tokens.dart';
import 'package:hydrowin/domain/models/cloud_organization.dart';
import 'package:hydrowin/domain/models/cloud_sensor.dart';
import 'package:hydrowin/domain/models/cloud_user.dart';
import 'package:hydrowin/domain/models/live_telemetry.dart';
import 'package:hydrowin/domain/models/machine_summary.dart';
import 'package:hydrowin/domain/models/reading_point.dart';
import 'package:hydrowin/domain/models/readings_series.dart';
import 'package:hydrowin/domain/models/sensor_config.dart';
import 'package:hydrowin/domain/models/sensor_status_level.dart';
import 'package:hydrowin/domain/models/sensor_type.dart';
import 'package:hydrowin/domain/sensor_threshold_evaluator.dart';
import 'package:hydrowin/data/remote/events_repository.dart';
import 'package:hydrowin/data/remote/notifications_repository.dart';

/// Флаг офлайн-демо (заводской UI без сервера).
abstract final class DemoSession {
  static bool isActive = false;
  static NotificationSettingsModel notificationSettings =
      const NotificationSettingsModel(
        critical: ChannelPrefs(),
        warning: ChannelPrefs(),
        quietHours: QuietHoursPrefs(),
        contacts: AlertContactsPrefs(),
      );
  static final List<MachineEventItem> events = [];
  static final Map<String, List<CloudSensor>> _sensorsByMachine = {};
  static final Map<String, MachineSummary> _machines = {};

  static void reset() {
    isActive = false;
    notificationSettings = DemoFleetData.defaultNotificationSettings;
    events
      ..clear()
      ..addAll(DemoFleetData.seedEvents());
    _sensorsByMachine
      ..clear()
      ..addAll(DemoFleetData.seedSensors());
    _machines
      ..clear()
      ..addAll({for (final m in DemoFleetData.seedMachines()) m.id: m});
  }

  static void start() {
    reset();
    isActive = true;
  }

  static void stop() {
    isActive = false;
  }

  static List<MachineSummary> machines({String? status, String? query}) {
    var items = _machines.values.toList();
    if (status != null && status.isNotEmpty) {
      items = items.where((m) => m.status.name == status).toList();
    }
    if (query != null && query.trim().isNotEmpty) {
      final q = query.trim().toLowerCase();
      items = items
          .where(
            (m) =>
                m.code.toLowerCase().contains(q) ||
                m.name.toLowerCase().contains(q) ||
                m.model.toLowerCase().contains(q) ||
                m.locationLabel.toLowerCase().contains(q),
          )
          .toList();
    }
    return items;
  }

  static MachineSummary? machine(String id) =>
      _machines[id] ??
      _machines.values.where((m) => m.ipAddress == id || m.code == id).firstOrNull;

  static void putMachine(MachineSummary m) => _machines[m.id] = m;

  static List<CloudSensor> sensors(String machineId) {
    final m = machine(machineId);
    final key = m?.id ?? machineId;
    return List.unmodifiable(_sensorsByMachine[key] ?? const []);
  }

  static void putSensors(String machineId, List<CloudSensor> sensors) {
    final m = machine(machineId);
    final key = m?.id ?? machineId;
    _sensorsByMachine[key] = List.of(sensors);
  }
}

extension _FirstOrNullDemo<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}

/// Демо-данные парка завода (графики, live, события, уведомления).
abstract final class DemoFleetData {
  static const orgId = 'demo-org-factory';
  static const userId = 'demo-user-admin';

  static AuthTokens authTokens() {
    return AuthTokens(
      accessToken: 'demo-access',
      refreshToken: 'demo-refresh',
      expiresIn: 86400,
      user: currentUser(),
    );
  }

  static OrgMeResponse orgMe() {
    return const OrgMeResponse(
      organization: CloudOrganization(
        id: orgId,
        name: 'Завод «Севергидро» (демо)',
        orgType: 'client',
      ),
      isManufacturer: false,
      isPlatform: false,
      isClient: true,
    );
  }

  static CloudUser currentUser() {
    return const CloudUser(
      id: userId,
      name: 'Админ завода (демо)',
      email: 'demo@hydrowin.local',
      role: 'admin',
      organizationId: orgId,
      organization: CloudOrganization(
        id: orgId,
        name: 'Завод «Севергидро» (демо)',
        orgType: 'client',
      ),
      firstName: 'Админ',
      lastName: 'Демо',
      phone: '+7 900 000-00-00',
    );
  }

  static NotificationSettingsModel get defaultNotificationSettings =>
      const NotificationSettingsModel(
        critical: ChannelPrefs(
          push: true,
          sound: true,
          vibration: true,
          email: true,
          telegram: true,
        ),
        warning: ChannelPrefs(
          push: true,
          sound: false,
          vibration: true,
          email: false,
          telegram: true,
        ),
        quietHours: QuietHoursPrefs(enabled: true, from: '22:00', to: '07:00'),
        contacts: AlertContactsPrefs(
          email: 'alerts@severgidro.demo',
          telegram: '@severgidro_alerts',
        ),
        policyDescription:
            'Демо-политика: критичные — все каналы; внимание — push/Telegram.',
      );

  static List<MachineSummary> seedMachines() {
    final now = DateTime.now();
    return [
      MachineSummary(
        id: 'demo-m-001',
        code: '001',
        name: 'КС-4572 «Урал»',
        model: 'Автокран 25 т',
        status: MachineStatus.ok,
        locationLabel: 'Площадка Север',
        operatorName: 'Иванов А.',
        engineHours: 4120,
        uptimeHours: 38,
        pumpHours: 1200,
        pumpStarts: 840,
        lastSeenAt: now.subtract(const Duration(seconds: 12)),
        ipAddress: '10.10.1.11',
        organizationId: orgId,
        ownerOrgName: 'Завод «Севергидро»',
        canConfigure: true,
        gps: const MachineGps(lat: 55.7558, lon: 37.6173, accuracyM: 12),
        geofence: const MachineGeofence(
          name: 'Площадка Север',
          centerLat: 55.7558,
          centerLon: 37.6173,
          radiusM: 250,
          enabled: true,
          inside: true,
        ),
        description: 'Рабочий цикл без замечаний.',
      ),
      MachineSummary(
        id: 'demo-m-014',
        code: '014',
        name: 'Hitachi ZX330',
        model: 'Экскаватор',
        status: MachineStatus.warning,
        locationLabel: 'Карьер Восток',
        operatorName: 'Петров С.',
        headlineAlert: 'Температура гидромотора выше нормы',
        engineHours: 2890,
        uptimeHours: 22,
        pumpHours: 980,
        pumpStarts: 620,
        lastSeenAt: now.subtract(const Duration(seconds: 18)),
        ipAddress: '10.10.1.14',
        organizationId: orgId,
        ownerOrgName: 'Завод «Севергидро»',
        canConfigure: true,
        gps: const MachineGps(lat: 55.78, lon: 37.65, accuracyM: 18),
        description: 'Давление в норме, греется контур.',
      ),
      MachineSummary(
        id: 'demo-m-027',
        code: '027',
        name: 'Liebherr LTM 1090',
        model: 'Мобильный кран 90 т',
        status: MachineStatus.critical,
        locationLabel: 'Стройплощадка Центр',
        operatorName: 'Сидоров В.',
        headlineAlert: 'Критическое давление на стреле',
        engineHours: 1560,
        uptimeHours: 6,
        pumpHours: 540,
        pumpStarts: 210,
        lastSeenAt: now.subtract(const Duration(seconds: 9)),
        ipAddress: '10.10.1.27',
        organizationId: orgId,
        ownerOrgName: 'Завод «Севергидро»',
        canConfigure: true,
        gps: const MachineGps(lat: 55.74, lon: 37.60, accuracyM: 9),
        description: 'Превышен порог по давлению.',
      ),
      MachineSummary(
        id: 'demo-m-033',
        code: '033',
        name: 'Amkodor 332C',
        model: 'Фронтальный погрузчик',
        status: MachineStatus.offline,
        locationLabel: 'Склад Юг',
        operatorName: '—',
        headlineAlert: 'Нет связи с блоком',
        engineHours: 8740,
        lastSeenAt: now.subtract(const Duration(hours: 6)),
        ipAddress: '10.10.1.33',
        organizationId: orgId,
        ownerOrgName: 'Завод «Севергидро»',
        canConfigure: true,
        description: 'Машина в парке, блок выключен.',
      ),
      MachineSummary(
        id: 'demo-m-041',
        code: '041',
        name: 'Palfinger PK 23500',
        model: 'Кран-манипулятор',
        status: MachineStatus.ok,
        locationLabel: 'База сервиса',
        operatorName: 'Козлов Д.',
        engineHours: 980,
        uptimeHours: 14,
        pumpHours: 310,
        pumpStarts: 150,
        lastSeenAt: now.subtract(const Duration(seconds: 25)),
        ipAddress: '10.10.1.41',
        organizationId: orgId,
        ownerOrgName: 'Завод «Севергидро»',
        canConfigure: true,
        gps: const MachineGps(lat: 55.76, lon: 37.58, accuracyM: 15),
        description: 'После ТО, стабильные показания.',
      ),
    ];
  }

  static Map<String, List<CloudSensor>> seedSensors() {
    CloudSensor s(String id, SensorConfig c) => CloudSensor(id: id, config: c);

    List<CloudSensor> trio(String mid, {required bool hot, required bool overPressure}) {
      return [
        s(
          '$mid-s0',
          SensorConfig(
            channelIndex: 0,
            name: 'Стрела / давление',
            type: SensorType.pressure,
            scaleMin: 0,
            scaleMax: 400,
            normMin: 100,
            normMax: 250,
            warnHigh: 300,
            criticalHigh: 320,
            criticalLow: 90,
          ),
        ),
        s(
          '$mid-s1',
          SensorConfig(
            channelIndex: 1,
            name: hot ? 'Гидромотор' : 'Температура масла',
            type: SensorType.temperature,
            scaleMin: -20,
            scaleMax: 120,
            normMin: 40,
            normMax: 85,
            warnHigh: 90,
            criticalHigh: 95,
          ),
        ),
        s(
          '$mid-s2',
          SensorConfig(
            channelIndex: 2,
            name: 'Основная линия',
            type: SensorType.flow,
            scaleMin: 0,
            scaleMax: 50,
            normMin: 8,
            normMax: 18,
            warnHigh: 22,
            criticalHigh: 28,
          ),
        ),
      ];
    }

    return {
      'demo-m-001': trio('demo-m-001', hot: false, overPressure: false),
      'demo-m-014': trio('demo-m-014', hot: true, overPressure: false),
      'demo-m-027': trio('demo-m-027', hot: false, overPressure: true),
      'demo-m-033': trio('demo-m-033', hot: false, overPressure: false),
      'demo-m-041': trio('demo-m-041', hot: false, overPressure: false),
    };
  }

  static List<double> baseValues(MachineStatus status) {
    return switch (status) {
      MachineStatus.ok => [185.0, 62.0, 12.5],
      MachineStatus.warning => [210.0, 92.0, 14.0],
      MachineStatus.critical => [335.0, 78.0, 11.0],
      MachineStatus.offline => [0.0, 18.0, 0.0],
    };
  }

  static List<double> liveValues(MachineStatus status, {required int tick}) {
    final base = baseValues(status);
    if (status == MachineStatus.offline) return base;
    final wave = math.sin(tick / 5.0);
    final rnd = math.Random(tick + status.index * 17);
    return [
      (base[0] + wave * 8 + rnd.nextDouble() * 2 - 1).clamp(0, 400),
      (base[1] + wave * 2 + rnd.nextDouble() - 0.5).clamp(-20, 120),
      (base[2] + wave * 0.5 + rnd.nextDouble() * 0.3 - 0.15).clamp(0, 50),
    ];
  }

  static MachineListResponse listResponse({String? status, String? query}) {
    final items = DemoSession.machines(status: status, query: query);
    return MachineListResponse(items: items, totals: totalsOf(items));
  }

  static FleetTotals totalsOf(List<MachineSummary> items) {
    return FleetTotals(
      total: items.length,
      ok: items.where((m) => m.status == MachineStatus.ok).length,
      warning: items.where((m) => m.status == MachineStatus.warning).length,
      critical: items.where((m) => m.status == MachineStatus.critical).length,
      offline: items.where((m) => m.status == MachineStatus.offline).length,
    );
  }

  static MachineLiveSnapshot machineLive(String machineId, {int tick = 0}) {
    final m = DemoSession.machine(machineId);
    if (m == null) {
      return MachineLiveSnapshot(
        machineId: machineId,
        code: '',
        status: MachineStatus.offline,
        sensors: const [],
      );
    }
    final sensors = DemoSession.sensors(m.id);
    final values = liveValues(m.status, tick: tick);
    final now = DateTime.now();
    final liveSensors = <SensorLiveReading>[];
    for (var i = 0; i < sensors.length; i++) {
      final s = sensors[i];
      final v = i < values.length ? values[i] : 0.0;
      final level = m.status == MachineStatus.offline
          ? SensorStatusLevel.offline
          : SensorThresholdEvaluator.evaluate(s.config, v);
      liveSensors.add(
        SensorLiveReading(
          id: s.id,
          channel: s.config.channelIndex,
          name: s.config.name,
          unit: s.config.unit,
          value: m.status == MachineStatus.offline ? null : v,
          ts: m.status == MachineStatus.offline ? m.lastSeenAt : now,
          status: level.name,
        ),
      );
    }
    return MachineLiveSnapshot(
      machineId: m.id,
      code: m.code,
      status: m.status,
      lastSeenAt: m.lastSeenAt,
      sensors: liveSensors,
    );
  }

  static FleetLiveSnapshot fleetLive({int tick = 0}) {
    final machines = DemoSession.machines()
        .map((m) => machineLive(m.id, tick: tick))
        .toList();
    return FleetLiveSnapshot(machines: machines, at: DateTime.now());
  }

  static ReadingsSeries readings({
    required String machineId,
    required String sensorId,
    required DateTime from,
    required DateTime to,
    int channelIndex = 0,
  }) {
    final m = DemoSession.machine(machineId);
    final sensors = DemoSession.sensors(machineId);
    final sensor = sensors.where((s) => s.id == sensorId).firstOrNull;
    final ch = sensor?.config.channelIndex ?? channelIndex;
    final status = m?.status ?? MachineStatus.ok;
    final unit = sensor?.config.unit ?? '';
    final points = <ReadingPoint>[];
    final spanMin = to.difference(from).inMinutes.clamp(5, 24 * 60);
    final step = spanMin > 180 ? 5 : 1;
    var tick = 0;
    for (var min = 0; min <= spanMin; min += step) {
      final at = from.add(Duration(minutes: min));
      if (at.isAfter(to)) break;
      final values = liveValues(status, tick: tick++);
      final idx = ch.clamp(0, values.length - 1);
      final value = values[idx];
      final level = status == MachineStatus.offline
          ? SensorStatusLevel.offline
          : SensorThresholdEvaluator.evaluate(
              sensor?.config ?? SensorConfig.defaults(ch, SensorType.pressure),
              value,
            );
      points.add(
        ReadingPoint(
          channelIndex: ch,
          value: value,
          status: level,
          recordedAt: at,
        ),
      );
    }
    return ReadingsSeries(sensorId: sensorId, unit: unit, points: points);
  }

  static List<MachineEventItem> seedEvents() {
    final now = DateTime.now();
    return [
      MachineEventItem(
        id: 'demo-ev-1',
        machineId: 'demo-m-027',
        sensorId: 'demo-m-027-s0',
        type: 'threshold',
        severity: 'critical',
        message: 'Давление на стреле выше критического порога',
        ts: now.subtract(const Duration(minutes: 8)),
        acknowledged: false,
        machineCode: '027',
        machineName: 'Liebherr LTM 1090',
      ),
      MachineEventItem(
        id: 'demo-ev-2',
        machineId: 'demo-m-014',
        sensorId: 'demo-m-014-s1',
        type: 'threshold',
        severity: 'warning',
        message: 'Температура гидромотора выше нормы',
        ts: now.subtract(const Duration(minutes: 22)),
        acknowledged: false,
        machineCode: '014',
        machineName: 'Hitachi ZX330',
      ),
      MachineEventItem(
        id: 'demo-ev-3',
        machineId: 'demo-m-033',
        type: 'offline',
        severity: 'warning',
        message: 'Блок не выходит на связь более 6 часов',
        ts: now.subtract(const Duration(hours: 6)),
        acknowledged: true,
        machineCode: '033',
        machineName: 'Amkodor 332C',
      ),
      MachineEventItem(
        id: 'demo-ev-4',
        machineId: 'demo-m-001',
        type: 'info',
        severity: 'info',
        message: 'Начало смены · оператор Иванов А.',
        ts: now.subtract(const Duration(hours: 3)),
        acknowledged: true,
        machineCode: '001',
        machineName: 'КС-4572 «Урал»',
      ),
    ];
  }

  static List<MachineTrackPoint> track(String machineId) {
    final m = DemoSession.machine(machineId);
    final gps = m?.gps;
    if (gps == null) return const [];
    final now = DateTime.now();
    return List.generate(12, (i) {
      final t = now.subtract(Duration(minutes: (11 - i) * 5));
      final a = i / 12 * math.pi * 2;
      return MachineTrackPoint(
        lat: gps.lat + math.sin(a) * 0.0015,
        lon: gps.lon + math.cos(a) * 0.0015,
        ts: t,
        accuracyM: gps.accuracyM,
      );
    });
  }

  static List<AuditLogItem> auditLog() {
    final now = DateTime.now();
    return [
      AuditLogItem(
        id: 'demo-audit-1',
        action: 'login',
        severity: 'info',
        message: 'Вход в демо-режим завода',
        ts: now.subtract(const Duration(minutes: 1)),
        actorEmail: 'demo@hydrowin.local',
      ),
      AuditLogItem(
        id: 'demo-audit-2',
        action: 'threshold_update',
        severity: 'info',
        message: 'Изменены пороги датчика «Гидромотор» на 014',
        ts: now.subtract(const Duration(hours: 5)),
        actorEmail: 'demo@hydrowin.local',
      ),
    ];
  }
}
