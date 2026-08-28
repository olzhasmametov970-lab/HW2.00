import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hydrowin/core/constants/app_constants.dart';
import 'package:hydrowin/data/local/sensor_config_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppPreferences {
  AppPreferences(this._prefs);

  final SharedPreferences _prefs;

  static Future<AppPreferences> create() async {
    final prefs = await SharedPreferences.getInstance();
    return AppPreferences(prefs);
  }

  bool get isFirstLaunchDone =>
      _prefs.getBool(AppConstants.prefsKeyFirstLaunch) ?? false;

  Future<void> setFirstLaunchDone() =>
      _prefs.setBool(AppConstants.prefsKeyFirstLaunch, true);

  String? get workMode {
    final raw = _prefs.getString(AppConstants.prefsKeyWorkMode);
    return _migrateWorkMode(raw);
  }

  Future<void> setWorkMode(String mode) =>
      _prefs.setString(AppConstants.prefsKeyWorkMode, mode);

  String? get singleMachineId =>
      _prefs.getString(AppConstants.prefsKeySingleMachineId);

  Future<void> setSingleMachineId(String? id) async {
    if (id == null || id.isEmpty) {
      await _prefs.remove(AppConstants.prefsKeySingleMachineId);
    } else {
      await _prefs.setString(AppConstants.prefsKeySingleMachineId, id);
    }
  }

  int get pollSeconds {
    final raw = _prefs.getInt(AppConstants.prefsKeyPollSeconds);
    return (raw ?? AppConstants.defaultPollSeconds).clamp(
      AppConstants.minPollSeconds,
      AppConstants.maxPollSeconds,
    );
  }

  Future<void> setPollSeconds(int seconds) async {
    final clamped = seconds.clamp(
      AppConstants.minPollSeconds,
      AppConstants.maxPollSeconds,
    );
    await _prefs.setInt(AppConstants.prefsKeyPollSeconds, clamped);
  }

  /// По умолчанию тёмная ops-тема; `light` / `system` — по выбору пользователя.
  ThemeMode get themeMode {
    final raw = _prefs.getString(AppConstants.prefsKeyThemeMode);
    return switch (raw) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.dark,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
      ThemeMode.dark => 'dark',
    };
    await _prefs.setString(AppConstants.prefsKeyThemeMode, value);
  }

  /// Локальные имена BLE-блоков (ключ = MAC/id, значение = подпись).
  Map<String, String> bleAliases() {
    final raw = _prefs.getString(AppConstants.prefsKeyBleAliases);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries)
          if (e.key is String &&
              e.value is String &&
              (e.value as String).trim().isNotEmpty)
            SensorConfigRepository.normalizeDeviceKey(e.key as String):
                (e.value as String).trim(),
      };
    } catch (_) {
      return {};
    }
  }

  String? bleAliasFor(String deviceId) {
    final key = SensorConfigRepository.normalizeDeviceKey(deviceId);
    if (key.isEmpty) return null;
    return bleAliases()[key];
  }

  Future<void> setBleAlias(String deviceId, String? alias) async {
    final key = SensorConfigRepository.normalizeDeviceKey(deviceId);
    if (key.isEmpty) return;
    final map = Map<String, String>.from(bleAliases());
    final trimmed = alias?.trim() ?? '';
    if (trimmed.isEmpty) {
      map.remove(key);
    } else {
      map[key] = trimmed;
    }
    await _prefs.setString(AppConstants.prefsKeyBleAliases, jsonEncode(map));
  }

  String resolveBleLabel(String deviceId, String fallback) {
    return bleAliasFor(deviceId) ?? fallback;
  }

  static String? _migrateWorkMode(String? raw) {
    if (raw == null) return null;
    if (raw == AppConstants.workModeBleLegacy) {
      return AppConstants.workModeSingle;
    }
    if (raw == AppConstants.workModeCloudLegacy) {
      return AppConstants.workModeFleet;
    }
    return raw;
  }
}
