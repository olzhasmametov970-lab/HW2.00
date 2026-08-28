import 'dart:convert';

import 'package:hydrowin/domain/models/fleet_machine_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FleetRegistryRepository {
  FleetRegistryRepository(this._prefs);

  static const _key = 'fleet_registry_v1';
  /// Машины, скрытые свайпом в «Парке»: только локально, на сервере остаются.
  static const _hiddenKey = 'fleet_hidden_machine_ids_v1';

  final SharedPreferences _prefs;

  static Future<FleetRegistryRepository> create() async {
    final prefs = await SharedPreferences.getInstance();
    return FleetRegistryRepository(prefs);
  }

  List<FleetMachineEntry> load() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => FleetMachineEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<FleetMachineEntry> entries) async {
    final json = entries.map((e) => e.toJson()).toList();
    await _prefs.setString(_key, jsonEncode(json));
  }

  Future<FleetMachineEntry?> findById(String id) async {
    return load().where((e) => e.id == id).firstOrNull;
  }

  Set<String> loadHiddenMachineIds() {
    final raw = _prefs.getStringList(_hiddenKey);
    if (raw == null || raw.isEmpty) return {};
    return raw.toSet();
  }

  Future<void> hideMachineId(String machineId) async {
    if (machineId.isEmpty) return;
    final ids = loadHiddenMachineIds()..add(machineId);
    await _prefs.setStringList(_hiddenKey, ids.toList());
  }

  Future<void> unhideMachineId(String machineId) async {
    final ids = loadHiddenMachineIds()..remove(machineId);
    await _prefs.setStringList(_hiddenKey, ids.toList());
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
