import 'dart:convert';

import 'package:hydrowin/core/constants/app_constants.dart';
import 'package:hydrowin/domain/models/sensor_config.dart';
import 'package:hydrowin/domain/models/sensor_type.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SensorConfigRepository {
  SensorConfigRepository(this._prefs);

  /// Общий набор (Full / пока нет привязки к блоку).
  static const _key = 'sensor_configs_v1';

  /// Lite: отдельный набор на каждый BLE-блок.
  static const _byDevicePrefix = 'sensor_configs_dev_v1_';

  final SharedPreferences _prefs;

  static Future<SensorConfigRepository> create() async {
    final prefs = await SharedPreferences.getInstance();
    return SensorConfigRepository(prefs);
  }

  static String normalizeDeviceKey(String deviceKey) {
    return deviceKey.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  String _deviceStorageKey(String deviceKey) =>
      '$_byDevicePrefix${normalizeDeviceKey(deviceKey)}';

  Future<List<SensorConfig>> load({String? deviceKey}) async {
    final key = deviceKey?.trim();
    if (key != null && key.isNotEmpty) {
      final raw = _prefs.getString(_deviceStorageKey(key));
      if (raw != null) {
        return _decode(raw);
      }
      // Новый блок: не наследуем чужие ENABLE с телефона.
      return SensorConfig.defaultSet(AppConstants.hardwareAnalogChannels);
    }

    final raw = _prefs.getString(_key);
    if (raw == null) {
      return SensorConfig.defaultSet(AppConstants.hardwareAnalogChannels);
    }
    return _decode(raw);
  }

  Future<void> save(List<SensorConfig> configs, {String? deviceKey}) async {
    final encoded = jsonEncode(configs.map((c) => c.toJson()).toList());
    final key = deviceKey?.trim();
    if (key != null && key.isNotEmpty) {
      await _prefs.setString(_deviceStorageKey(key), encoded);
      return;
    }
    await _prefs.setString(_key, encoded);
  }

  List<SensorConfig> _decode(String raw) {
    final list = jsonDecode(raw) as List<dynamic>;
    final loaded = list
        .map((e) => SensorConfig.fromJson(e as Map<String, dynamic>).repairThresholds())
        .toList();
    return _normalizeHardwareChannels(loaded);
  }

  List<SensorConfig> _normalizeHardwareChannels(List<SensorConfig> configs) {
    final byChannel = {
      for (final config in configs) config.channelIndex: config,
    };
    return List.generate(AppConstants.hardwareAnalogChannels, (channel) {
      return (byChannel[channel] ??
              SensorConfig.defaults(
                channel,
                channel == 0 ? SensorType.pressure : SensorType.temperature,
              ))
          .repairThresholds();
    });
  }
}
