import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hydrowin/core/constants/app_constants.dart';
import 'package:hydrowin/data/local/secure_storage_factory.dart';
import 'package:hydrowin/domain/models/developer_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeveloperSettingsRepository {
  DeveloperSettingsRepository(this._prefs, this._secure);

  static const _settingsKey = 'developer_settings_v1';
  static const _passwordHashKey = 'developer_password_hash_v1';
  static const _legacyPasswordKey = 'developer_password_v1';

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;

  static Future<DeveloperSettingsRepository> create() async {
    final prefs = await SharedPreferences.getInstance();
    final repo = DeveloperSettingsRepository(prefs, createSecureStorage());
    await repo._migrateLegacyPassword();
    return repo;
  }

  Future<void> _migrateLegacyPassword() async {
    final legacy = _prefs.getString(_legacyPasswordKey);
    if (legacy == null || legacy.isEmpty) return;
    await setPassword(legacy);
    await _prefs.remove(_legacyPasswordKey);
  }

  DeveloperSettings load() {
    final raw = _prefs.getString(_settingsKey);
    if (raw == null || raw.isEmpty) return const DeveloperSettings();
    try {
      return DeveloperSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const DeveloperSettings();
    }
  }

  Future<void> save(DeveloperSettings settings) async {
    await _prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  bool get isUnlocked =>
      _prefs.getBool(AppConstants.prefsKeyDevUnlocked) ?? false;

  Future<void> setUnlocked(bool value) async {
    await _prefs.setBool(AppConstants.prefsKeyDevUnlocked, value);
  }

  String _hash(String password) {
    final bytes = utf8.encode('hydrowin-dev|$password');
    return sha256.convert(bytes).toString();
  }

  Future<bool> verifyPassword(String password) async {
    final stored = await _secure.read(key: _passwordHashKey);
    if (stored != null && stored.isNotEmpty) {
      return _hash(password) == stored;
    }
    final fallback = AppConstants.defaultDeveloperPassword;
    if (fallback.isEmpty) return false;
    return _hash(password) == _hash(fallback);
  }

  Future<void> setPassword(String password) async {
    await _secure.write(key: _passwordHashKey, value: _hash(password));
  }
}
