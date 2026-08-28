// lib/data/remote/machines_repository.dart
//
// Что исправлено:
// 1. getReadings() теперь ходит на /v1/machines/{ip}/readings
//    вместо /v1/sensors/{id}/readings — это единственный эндпойнт,
//    который отдаёт данные вместе с правильным channel_index.
// 2. Убран лишний вызов listSensors() внутри getReadings() —
//    channel_index теперь берётся из переданного параметра (caller знает его).
// 3. getReadings() принимает channelIndex явно, чтобы не делать
//    лишний сетевой запрос при каждом обновлении.
// 4. Добавлен недостающий метод updateSensorConfig для сохранения порогов.
// 5. Добавлено умное слияние (дедупликация) по IP-адресу: статус активности
//    и время синхронизации от сырого ID чипа переносятся на человеческую карточку "001".

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hydrowin/data/demo/demo_fleet_data.dart';
import 'package:hydrowin/data/local/fleet_registry_repository.dart';
import 'package:hydrowin/data/remote/api_client.dart';
import 'package:hydrowin/domain/models/cloud_sensor.dart';
import 'package:hydrowin/domain/models/fleet_machine_entry.dart';
import 'package:hydrowin/domain/models/live_telemetry.dart';
import 'package:hydrowin/domain/models/machine_summary.dart';
import 'package:hydrowin/domain/models/readings_series.dart';

class MachinesRepository {
  MachinesRepository(
    this._api, {
    FleetRegistryRepository? fleetRegistry,
  }) : _fleetRegistry = fleetRegistry;

  final ApiClient _api;
  final FleetRegistryRepository? _fleetRegistry;

  int get _demoTick => DateTime.now().millisecondsSinceEpoch ~/ 4000;

  Future<List<FleetMachineEntry>> _localFleet() async {
    final repo = _fleetRegistry;
    if (repo == null) return [];
    return repo.load();
  }

  Future<MachineListResponse> listMachines({
    String? status,
    String? query,
  }) async {
    if (DemoSession.isActive) {
      return DemoFleetData.listResponse(status: status, query: query);
    }
    try {
      // Статус фильтруем на клиенте после скрытия локальных машин,
      // чтобы чипы ОК / Внимание / … считались по видимому парку.
      final queryParams = <String, String>{};
      if (query != null && query.isNotEmpty) queryParams['q'] = query;

      final json = await _api.get('/machines', query: queryParams);
      final response = MachineListResponse.fromJson(json);

      // 1. Смержили локальные IP из реестра
      final merged = _mergeLocalIps(response);

      // 2. Склеиваем дубликаты: переносим статус "Критично" на карточку "001"
      final dedupedItems = _deduplicateByIp(merged.items);

      // 3. Пересчитываем totals по красивому списку, чтобы чипы сверху не врали
      final dedupedResponse = MachineListResponse(
        items: dedupedItems,
        totals: _totalsFrom(dedupedItems),
      );

      final visible = _withoutHidden(dedupedResponse);
      return _applyStatusFilter(visible, status);
    } on TimeoutException {
      rethrow;
    } catch (_) {
      final local = _withoutHidden(
        await _machinesFromLocalRegistry(status: null, query: query),
      );
      return _applyStatusFilter(local, status);
    }
  }

  /// Убирает машины, скрытые свайпом в приложении (сервер не трогаем).
  MachineListResponse _withoutHidden(MachineListResponse response) {
    final hidden = _fleetRegistry?.loadHiddenMachineIds() ?? {};
    if (hidden.isEmpty) {
      return MachineListResponse(
        items: response.items,
        totals: _totalsFrom(response.items),
      );
    }

    final items = response.items.where((m) => !hidden.contains(m.id)).toList();
    return MachineListResponse(items: items, totals: _totalsFrom(items));
  }

  MachineListResponse _applyStatusFilter(
    MachineListResponse response,
    String? status,
  ) {
    if (status == null || status.isEmpty) return response;
    final items = response.items.where((m) => m.status.name == status).toList();
    return MachineListResponse(items: items, totals: response.totals);
  }

  FleetTotals _totalsFrom(List<MachineSummary> items) {
    var ok = 0;
    var warning = 0;
    var critical = 0;
    var offline = 0;
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
    return FleetTotals(
      total: items.length,
      ok: ok,
      warning: warning,
      critical: critical,
      offline: offline,
    );
  }

  /// Убирает дубли с одним IP / одной сетевой меткой (оставляем «живую» машину).
  bool _looksLikeIp(String s) {
    final parts = s.split('.');
    if (parts.length != 4) return false;
    return parts.every((p) {
      final n = int.tryParse(p);
      return n != null && n >= 0 && n <= 255;
    });
  }

  String? _networkKey(MachineSummary m) {
    final ip = m.ipAddress?.trim();
    if (ip != null && ip.isNotEmpty && _looksLikeIp(ip)) return ip;
    final loc = m.locationLabel.trim();
    if (_looksLikeIp(loc)) return loc;
    return null;
  }

  MachineListResponse _mergeLocalIps(MachineListResponse response) {
    final local = _fleetRegistry?.load() ?? [];
    if (local.isEmpty) return response;

    final byServerId = {
      for (final e in local)
        if (e.serverId != null) e.serverId!: e,
    };
    final byNumber = {for (final e in local) e.number: e};

    // IP → все serverId из локального реестра с этим IP
    final serverIdsByIp = <String, Set<String>>{};
    for (final e in local) {
      final ip = e.ipAddress.trim();
      if (ip.isEmpty) continue;
      serverIdsByIp.putIfAbsent(ip, () => {}).add(e.serverId ?? e.id);
    }

    final merged = response.items.map((m) {
      var reg = byServerId[m.id] ?? byNumber[m.code.replaceAll('#', '')];
      // Если у другой локальной записи тот же IP — тоже проставим
      if (reg == null) {
        for (final e in local) {
          final ip = e.ipAddress.trim();
          if (ip.isEmpty) continue;
          final ids = serverIdsByIp[ip] ?? {};
          if (ids.contains(m.id)) {
            reg = e;
            break;
          }
        }
      }
      if (reg == null) return m;
      return m.copyWith(ipAddress: reg.ipAddress);
    }).toList();

    // Второй проход: если в реестре один IP на несколько машин — всем проставить его
    final ipForId = <String, String>{};
    for (final e in local) {
      final ip = e.ipAddress.trim();
      if (ip.isEmpty) continue;
      if (e.serverId != null) ipForId[e.serverId!] = ip;
      ipForId[e.id] = ip;
      ipForId[e.number] = ip;
    }

    final stamped = merged.map((m) {
      final ip =
          m.ipAddress ?? ipForId[m.id] ?? ipForId[m.code.replaceAll('#', '')];
      if (ip == null || ip == m.ipAddress) return m;
      return m.copyWith(ipAddress: ip);
    }).toList();

    return MachineListResponse(items: stamped, totals: response.totals);
  }

  Future<MachineListResponse> _machinesFromLocalRegistry({
    String? status,
    String? query,
  }) async {
    final local = await _localFleet();
    var items = local
        .map(
          (e) => MachineSummary(
            id: e.serverId ?? e.id,
            code: e.displayCode,
            name: e.name,
            model: e.model ?? '—',
            status: MachineStatus.offline,
            locationLabel: 'Локальный реестр',
            operatorName: '—',
            ipAddress: e.ipAddress,
          ),
        )
        .toList();

    if (query != null && query.trim().isNotEmpty) {
      final q = query.toLowerCase();
      items = items
          .where(
            (m) =>
                m.code.toLowerCase().contains(q) ||
                m.name.toLowerCase().contains(q) ||
                (m.ipAddress ?? '').contains(q),
          )
          .toList();
    }

    return MachineListResponse(
      items: items,
      totals: FleetTotals(
        total: items.length,
        ok: 0,
        warning: 0,
        critical: 0,
        offline: items.length,
      ),
    );
  }

  Future<MachineSummary?> getMachine(String ipAddress) async {
    if (DemoSession.isActive) {
      return DemoSession.machine(ipAddress);
    }
    final local = await _localFleet();
    final reg = local.where((e) => e.ipAddress == ipAddress).firstOrNull;
    try {
      final json = await _api.get(
        '/machines/${Uri.encodeComponent(ipAddress)}',
      );
      final machine = MachineSummary.fromJson(json);
      if (reg != null) {
        return machine.copyWith(ipAddress: reg.ipAddress);
      }
      return machine;
    } catch (_) {
      if (reg == null) return null;
      return MachineSummary(
        id: reg.serverId ?? reg.id,
        code: reg.displayCode,
        name: reg.name,
        model: reg.model ?? '—',
        status: MachineStatus.offline,
        locationLabel: 'Локальный реестр',
        operatorName: '—',
        ipAddress: reg.ipAddress,
      );
    }
  }

  /// Сохраняет пороги датчика на сервере (PUT /machines/{ip}/sensors).
  Future<CloudSensor?> updateSensorConfig(
    String ipAddress,
    CloudSensor sensor,
  ) async {
    if (DemoSession.isActive) {
      final updated = await updateSensors(ipAddress, [sensor]);
      return updated?.where((s) => s.id == sensor.id).firstOrNull ?? sensor;
    }
    final all = await updateSensors(ipAddress, [sensor]);
    if (all == null) return null;
    return all.where((s) => s.id == sensor.id).firstOrNull ?? sensor;
  }

  /// Сохраняет пороги нескольких датчиков одним PUT.
  Future<List<CloudSensor>?> updateSensors(
    String ipAddress,
    List<CloudSensor> sensors,
  ) async {
    if (DemoSession.isActive) {
      final current = List<CloudSensor>.from(DemoSession.sensors(ipAddress));
      for (final s in sensors) {
        final idx = current.indexWhere((c) => c.id == s.id);
        if (idx >= 0) {
          current[idx] = s;
        } else {
          current.add(s);
        }
      }
      DemoSession.putSensors(ipAddress, current);
      return current;
    }
    try {
      final path = '/machines/${Uri.encodeComponent(ipAddress)}/sensors';
      final raw = await _api.putList(
        path,
        body: sensors.map((s) => s.toApiJson()).toList(),
      );
      return raw
          .map((e) => CloudSensor.fromApiJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Ошибка обновления порогов датчиков на сервере: $e');
      return null;
    }
  }

  /// Обновление текстовых сведений и GPS машины.
  Future<MachineSummary?> updateMachineDetails(
    String machineKey, {
    String? code,
    String? name,
    String? operatorName,
    String? locationLabel,
    double? pumpOnPressureBar,
    double? pumpOnTemperatureC,
    String? description,
    String? photoBase64,
    bool clearPhoto = false,
    MachineGps? gps,
  }) async {
    if (DemoSession.isActive) {
      final m = DemoSession.machine(machineKey);
      if (m == null) return null;
      final updated = m.copyWith(
        code: code,
        name: name,
        operatorName: operatorName,
        locationLabel: locationLabel,
        pumpOnPressureBar: pumpOnPressureBar,
        pumpOnTemperatureC: pumpOnTemperatureC,
        description: description,
        clearPhoto: clearPhoto,
        gps: gps,
      );
      DemoSession.putMachine(updated);
      return updated;
    }
    final body = <String, dynamic>{};
    if (code != null) body['code'] = code;
    if (name != null) body['name'] = name;
    if (operatorName != null) body['operator_name'] = operatorName;
    if (locationLabel != null) body['location_label'] = locationLabel;
    if (pumpOnPressureBar != null) {
      body['pump_on_pressure_bar'] = pumpOnPressureBar;
    }
    if (pumpOnTemperatureC != null) {
      body['pump_on_temperature_c'] = pumpOnTemperatureC;
    }
    if (description != null) body['description'] = description;
    if (photoBase64 != null) body['photo_base64'] = photoBase64;
    if (clearPhoto) body['clear_photo'] = true;
    if (gps != null) body['gps'] = gps.toJson();

    final path = '/machines/${Uri.encodeComponent(machineKey)}';
    final json = await _api.put(path, body: body);
    final updated = MachineSummary.fromJson(json);

    final local = await _localFleet();
    final reg = local
        .where(
          (e) =>
              e.ipAddress == machineKey ||
              e.serverId == machineKey ||
              e.id == machineKey,
        )
        .firstOrNull;
    if (reg != null) {
      return updated.copyWith(ipAddress: reg.ipAddress);
    }
    return updated;
  }

  Future<MachineGeofence?> getGeofence(String machineId) async {
    if (DemoSession.isActive) {
      return DemoSession.machine(machineId)?.geofence;
    }
    final json = await _api.get('/machines/id/$machineId/geofence');
    final lat = json['center_lat'];
    final lon = json['center_lon'];
    final radius = json['radius_m'];
    if (lat == null || lon == null || radius == null) return null;
    return MachineGeofence.fromJson(json);
  }

  Future<MachineGeofence> saveGeofence(
    String machineId,
    MachineGeofence geofence,
  ) async {
    if (DemoSession.isActive) {
      final m = DemoSession.machine(machineId);
      if (m != null) {
        DemoSession.putMachine(
          MachineSummary(
            id: m.id,
            code: m.code,
            name: m.name,
            model: m.model,
            status: m.status,
            locationLabel: m.locationLabel,
            operatorName: m.operatorName,
            headlineAlert: m.headlineAlert,
            engineHours: m.engineHours,
            uptimeHours: m.uptimeHours,
            pumpHours: m.pumpHours,
            pumpStarts: m.pumpStarts,
            pumpOnPressureBar: m.pumpOnPressureBar,
            pumpOnTemperatureC: m.pumpOnTemperatureC,
            lastSeenAt: m.lastSeenAt,
            ipAddress: m.ipAddress,
            access: m.access,
            canConfigure: m.canConfigure,
            canReassign: m.canReassign,
            ownerOrgName: m.ownerOrgName,
            organizationId: m.organizationId,
            gps: m.gps,
            geofence: geofence,
            description: m.description,
            photoUrl: m.photoUrl,
          ),
        );
      }
      return geofence;
    }
    final json = await _api.put(
      '/machines/id/$machineId/geofence',
      body: geofence.toJson(),
    );
    return MachineGeofence.fromJson(json);
  }

  Future<List<MachineTrackPoint>> getTrack(
    String machineId, {
    DateTime? from,
    DateTime? to,
    int limit = 500,
  }) async {
    if (DemoSession.isActive) {
      return DemoFleetData.track(machineId).take(limit).toList();
    }
    final query = <String, String>{'limit': '$limit'};
    if (from != null) query['from'] = from.toUtc().toIso8601String();
    if (to != null) query['to'] = to.toUtc().toIso8601String();
    final json = await _api.get('/machines/id/$machineId/track', query: query);
    final items = json['items'] as List<dynamic>? ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(MachineTrackPoint.fromJson)
        .toList();
  }

  /// Убирает машину только из локального списка «Парк».
  /// На сервере машина и история показаний НЕ удаляются.
  Future<bool> hideMachineFromFleet(MachineSummary machine) async {
    final repo = _fleetRegistry;
    if (repo != null) {
      await repo.hideMachineId(machine.id);

      final entries = repo.load();
      final filtered = entries
          .where(
            (e) =>
                e.serverId != machine.id &&
                e.id != machine.id &&
                !(machine.ipAddress != null &&
                    machine.ipAddress!.isNotEmpty &&
                    e.ipAddress == machine.ipAddress),
          )
          .toList();
      if (filtered.length != entries.length) {
        await repo.save(filtered);
      }
    }
    return true;
  }

  /// Возвращает машину в локальный список «Парк» (сервер не меняется).
  Future<void> unhideMachineFromFleet(String machineId) async {
    await _fleetRegistry?.unhideMachineId(machineId);
  }

  /// Жёстко удаляет машину на сервере (история датчиков тоже).
  Future<void> deleteMachineOnServer(String machineId) async {
    await _api.delete('/machines/id/$machineId');
    await _fleetRegistry?.hideMachineId(machineId);
  }

  Future<List<CloudSensor>> listSensors(String ipAddress) async {
    if (DemoSession.isActive) {
      return DemoSession.sensors(ipAddress);
    }
    try {
      final raw = await _api.getList(
        '/machines/${Uri.encodeComponent(ipAddress)}/sensors',
      );
      return raw
          .map((e) => CloudSensor.fromApiJson(e as Map<String, dynamic>))
          .toList();
    } on TimeoutException {
      rethrow;
    } catch (_) {
      return [];
    }
  }

  /// Каталог типов датчиков с сервера.
  Future<List<Map<String, dynamic>>> fetchSensorCatalog() async {
    final json = await _api.get('/sensor-catalog');
    final items = json['items'] as List<dynamic>? ?? [];
    return items.cast<Map<String, dynamic>>();
  }

  /// Добавляет датчик на машину (POST /machines/{key}/sensors).
  Future<CloudSensor?> addSensor(
    String machineKey, {
    required String type,
    String? name,
    int? channelIndex,
  }) async {
    final body = <String, dynamic>{'type': type};
    if (name != null && name.isNotEmpty) body['name'] = name;
    if (channelIndex != null) body['channel_index'] = channelIndex;
    final json = await _api.post(
      '/machines/${Uri.encodeComponent(machineKey)}/sensors',
      body: body,
      auth: true,
    );
    return CloudSensor.fromApiJson(json);
  }

  /// Удаляет датчик с машины (DELETE /machines/{key}/sensors/{id}).
  Future<void> deleteSensor(String machineKey, String sensorId) async {
    await _api.delete(
      '/machines/${Uri.encodeComponent(machineKey)}/sensors/'
      '${Uri.encodeComponent(sensorId)}',
    );
  }

  /// Создаёт машину (+ опционально плату). Ключ device_key — один раз в ответе.
  Future<Map<String, dynamic>> createMachine({
    required String code,
    required String name,
    String model = '',
    String locationLabel = '',
    String? deviceId,
    String? manufacturerOrganizationId,
  }) async {
    final body = <String, dynamic>{
      'code': code.trim(),
      'name': name.trim(),
      'model': model.trim(),
      'location_label': locationLabel.trim(),
    };
    if (deviceId != null && deviceId.trim().isNotEmpty) {
      body['device_id'] = deviceId.trim();
    }
    if (manufacturerOrganizationId != null &&
        manufacturerOrganizationId.isNotEmpty) {
      body['manufacturer_organization_id'] = manufacturerOrganizationId;
    }
    return _api.post('/machines', body: body, auth: true);
  }

  /// Список плат (device_id) на машине. Ключи API не возвращаются.
  Future<List<Map<String, dynamic>>> listMachineDevices(
    String machineId,
  ) async {
    final json = await _api.get(
      '/machines/id/${Uri.encodeComponent(machineId)}/devices',
    );
    final items = json['items'] as List<dynamic>? ?? [];
    return items.cast<Map<String, dynamic>>();
  }

  /// Создаёт новый X-Device-Key для платы. Ключ возвращается один раз.
  Future<Map<String, dynamic>> createMachineDevice(
    String machineId, {
    String? deviceId,
  }) async {
    final body = <String, dynamic>{};
    if (deviceId != null && deviceId.trim().isNotEmpty) {
      body['device_id'] = deviceId.trim();
    }
    return _api.post(
      '/machines/id/${Uri.encodeComponent(machineId)}/devices',
      body: body,
      auth: true,
    );
  }

  /// Получить историю показаний датчика.
  Future<ReadingsSeries> getReadings(
    String ipAddress,
    String sensorId, {
    DateTime? from,
    DateTime? to,
    int? minutes,
    int channelIndex = 0,
  }) async {
    final DateTime endTime = to ?? DateTime.now();
    final DateTime startTime =
        from ??
        (minutes != null
            ? endTime.subtract(Duration(minutes: minutes))
            : endTime.subtract(const Duration(hours: 1)));

    if (DemoSession.isActive) {
      return DemoFleetData.readings(
        machineId: ipAddress,
        sensorId: sensorId,
        from: startTime,
        to: endTime,
        channelIndex: channelIndex,
      );
    }

    final path = '/machines/${Uri.encodeComponent(ipAddress)}/readings';
    final query = <String, String>{
      'sensor_id': sensorId,
      'from': startTime.toUtc().toIso8601String(),
      'to': endTime.toUtc().toIso8601String(),
    };

    if (kDebugMode) {
      debugPrint(
        '🌐 [MachinesRepository] GET $path?sensor_id=$sensorId'
        ' from=${startTime.toUtc()} to=${endTime.toUtc()}',
      );
    }

    final json = await _api.get(path, query: query);
    return ReadingsSeries.fromApiJson(json, channelIndex: channelIndex);
  }

  /// Последние показания всех датчиков машины (1 запрос).
  Future<MachineLiveSnapshot> getMachineLive(String machineKey) async {
    if (DemoSession.isActive) {
      return DemoFleetData.machineLive(machineKey, tick: _demoTick);
    }
    final path = '/machines/${Uri.encodeComponent(machineKey)}/live';
    final json = await _api.get(path);
    return MachineLiveSnapshot.fromJson(json);
  }

  /// Последние показания всего парка (1 запрос).
  Future<FleetLiveSnapshot> getFleetLive() async {
    if (DemoSession.isActive) {
      return DemoFleetData.fleetLive(tick: _demoTick);
    }
    final json = await _api.get('/fleet/live');
    return FleetLiveSnapshot.fromJson(json);
  }

  /// Склеивает дубли одного IP: оставляем карточку с живыми данными,
  /// подтягиваем короткий/человечный code с «настроенной» записи, если есть.
  List<MachineSummary> _deduplicateByIp(List<MachineSummary> items) {
    int score(MachineSummary m) {
      var s = 0;
      if (m.lastSeenAt != null) {
        s += m.lastSeenAt!.millisecondsSinceEpoch ~/ 1000;
      }
      switch (m.status) {
        case MachineStatus.critical:
          s += 500;
        case MachineStatus.warning:
          s += 400;
        case MachineStatus.ok:
          s += 300;
        case MachineStatus.offline:
          s += 0;
      }
      // Живой блок с длинным кодом важнее «пустой» карточки 001
      if (RegExp(r'^\d{10,}$').hasMatch(m.code)) s += 80;
      return s;
    }

    bool isHumanCode(String code) => !RegExp(r'^\d{10,}$').hasMatch(code);

    final byKey = <String, MachineSummary>{};
    final noKey = <MachineSummary>[];

    for (final m in items) {
      final key = _networkKey(m);
      if (key == null) {
        noKey.add(m);
        continue;
      }
      final prev = byKey[key];
      if (prev == null) {
        byKey[key] = m;
        continue;
      }

      // Выбираем «живую» запись как основу
      final live = score(m) >= score(prev) ? m : prev;
      final other = identical(live, m) ? prev : m;

      // Если у одной короткий код (001), а у другой длинный — показываем короткий,
      // но id/статус/время берём у живой (чтобы графики не ломались).
      final preferCode = isHumanCode(other.code) && !isHumanCode(live.code)
          ? other.code
          : live.code;
      final preferName =
          (other.name.isNotEmpty &&
              other.name != 'Станок' &&
              other.name != 'машина' &&
              (live.name == 'Станок' || live.name == 'машина'))
          ? other.name
          : live.name;
      final preferLocation =
          (!_looksLikeIp(other.locationLabel) &&
              other.locationLabel.isNotEmpty &&
              (_looksLikeIp(live.locationLabel) || live.locationLabel.isEmpty))
          ? other.locationLabel
          : live.locationLabel;

      byKey[key] = live.copyWith(
        code: preferCode,
        name: preferName,
        locationLabel: preferLocation,
        operatorName: live.operatorName.isNotEmpty
            ? live.operatorName
            : other.operatorName,
        status: live.status,
        lastSeenAt: live.lastSeenAt ?? other.lastSeenAt,
        ipAddress: live.ipAddress ?? other.ipAddress ?? key,
      );
    }

    return [...byKey.values, ...noKey];
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
