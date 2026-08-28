import 'dart:math' as math;

import 'package:hydrowin/domain/models/machine_summary.dart';
import 'package:hydrowin/domain/models/sensor_config.dart';
import 'package:hydrowin/domain/models/sensor_type.dart';

/// Сценарий демо-машины: какие «живые» значения генерировать.
enum LiteDemoScenario { ok, warning, critical, offline }

/// Локальный демо-парк для ГидроВин Lite (без сервера и BLE).
abstract final class LiteDemoFleet {
  static const machines = <LiteDemoMachine>[
    LiteDemoMachine(
      id: 'lite-demo-ural-ks',
      code: '001',
      name: 'КС-4572 «Урал»',
      model: 'Автокран 25 т',
      locationLabel: 'Площадка Север',
      operatorName: 'Иванов А.',
      scenario: LiteDemoScenario.ok,
      description: 'Рабочий цикл без замечаний. Демо-данные.',
      engineHours: 4120,
    ),
    LiteDemoMachine(
      id: 'lite-demo-hitachi',
      code: '014',
      name: 'Hitachi ZX330',
      model: 'Экскаватор',
      locationLabel: 'Карьер Восток',
      operatorName: 'Петров С.',
      scenario: LiteDemoScenario.warning,
      headlineAlert: 'Температура гидромотора выше нормы',
      description: 'Давление в норме, греется контур.',
      engineHours: 2890,
    ),
    LiteDemoMachine(
      id: 'lite-demo-liebherr',
      code: '027',
      name: 'Liebherr LTM 1090',
      model: 'Мобильный кран 90 т',
      locationLabel: 'Стройплощадка Центр',
      operatorName: 'Сидоров В.',
      scenario: LiteDemoScenario.critical,
      headlineAlert: 'Критическое давление на стреле',
      description: 'Демо: превышен порог по давлению.',
      engineHours: 1560,
    ),
    LiteDemoMachine(
      id: 'lite-demo-amkodor',
      code: '033',
      name: 'Amkodor 332C',
      model: 'Фронтальный погрузчик',
      locationLabel: 'Склад Юг',
      operatorName: '—',
      scenario: LiteDemoScenario.offline,
      headlineAlert: 'Нет связи с блоком',
      description: 'Демо: машина в парке, блок выключен.',
      engineHours: 8740,
    ),
    LiteDemoMachine(
      id: 'lite-demo-palfinger',
      code: '041',
      name: 'Palfinger PK 23500',
      model: 'Кран-манипулятор',
      locationLabel: 'База сервиса',
      operatorName: 'Козлов Д.',
      scenario: LiteDemoScenario.ok,
      description: 'После ТО, стабильные показания.',
      engineHours: 980,
    ),
  ];

  static LiteDemoMachine? byId(String id) {
    for (final m in machines) {
      if (m.id == id) return m;
    }
    return null;
  }

  static MachineListResponse asListResponse() {
    final items = machines.map((m) => m.toSummary()).toList();
    var ok = 0, warning = 0, critical = 0, offline = 0;
    for (final m in items) {
      switch (m.status) {
        case MachineStatus.ok:
          ok++;
        case MachineStatus.warning:
          warning++;
        case MachineStatus.critical:
          critical++;
        case MachineStatus.offline:
          offline++;
      }
    }
    return MachineListResponse(
      items: items,
      totals: FleetTotals(
        total: items.length,
        ok: ok,
        warning: warning,
        critical: critical,
        offline: offline,
      ),
    );
  }

  /// Конфиг датчиков под демо-машину (3 канала как у блока).
  static List<SensorConfig> sensorConfigsFor(LiteDemoMachine machine) {
    return [
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
      SensorConfig(
        channelIndex: 1,
        name: machine.scenario == LiteDemoScenario.warning
            ? 'Гидромотор'
            : 'Температура масла',
        type: SensorType.temperature,
        scaleMin: -20,
        scaleMax: 120,
        normMin: 40,
        normMax: 85,
        warnHigh: 90,
        criticalHigh: 95,
      ),
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
    ];
  }

  /// Базовые значения каналов [P, T, Q] для сценария (+ лёгкий шум снаружи).
  static List<double> baseValues(LiteDemoScenario scenario) {
    return switch (scenario) {
      LiteDemoScenario.ok => [185.0, 62.0, 12.5],
      LiteDemoScenario.warning => [210.0, 92.0, 14.0],
      LiteDemoScenario.critical => [335.0, 78.0, 11.0],
      LiteDemoScenario.offline => [0.0, 18.0, 0.0],
    };
  }

  static List<double> liveValues(
    LiteDemoScenario scenario, {
    required int tick,
    math.Random? random,
  }) {
    final rnd = random ?? math.Random();
    final base = baseValues(scenario);
    if (scenario == LiteDemoScenario.offline) {
      return base;
    }
    final wave = math.sin(tick / 4.0);
    return [
      (base[0] + wave * 8 + rnd.nextDouble() * 3 - 1.5).clamp(0, 400),
      (base[1] + wave * 2 + rnd.nextDouble() * 1.5 - 0.7).clamp(-20, 120),
      (base[2] + wave * 0.6 + rnd.nextDouble() * 0.4 - 0.2).clamp(0, 50),
    ];
  }
}

class LiteDemoMachine {
  const LiteDemoMachine({
    required this.id,
    required this.code,
    required this.name,
    required this.model,
    required this.locationLabel,
    required this.operatorName,
    required this.scenario,
    this.headlineAlert,
    this.description = '',
    this.engineHours,
  });

  final String id;
  final String code;
  final String name;
  final String model;
  final String locationLabel;
  final String operatorName;
  final LiteDemoScenario scenario;
  final String? headlineAlert;
  final String description;
  final double? engineHours;

  MachineStatus get status => switch (scenario) {
        LiteDemoScenario.ok => MachineStatus.ok,
        LiteDemoScenario.warning => MachineStatus.warning,
        LiteDemoScenario.critical => MachineStatus.critical,
        LiteDemoScenario.offline => MachineStatus.offline,
      };

  MachineSummary toSummary() {
    final now = DateTime.now();
    return MachineSummary(
      id: id,
      code: code,
      name: name,
      model: model,
      status: status,
      locationLabel: locationLabel,
      operatorName: operatorName,
      headlineAlert: headlineAlert,
      engineHours: engineHours,
      lastSeenAt: scenario == LiteDemoScenario.offline
          ? now.subtract(const Duration(hours: 6))
          : now.subtract(Duration(seconds: 5 + code.hashCode.abs() % 40)),
      description: description,
      canConfigure: true,
    );
  }

  String get listLabel => '$code · $name';
}
