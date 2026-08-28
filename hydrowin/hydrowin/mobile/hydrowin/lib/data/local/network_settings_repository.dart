import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hydrowin/data/local/secure_storage_factory.dart';
import 'package:hydrowin/domain/models/network_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Несекретные поля — SharedPreferences; пароли/ключи — SecureStorage.
class NetworkSettingsRepository {
  NetworkSettingsRepository(this._prefs, this._secure);

  static const _key = 'network_settings_v1';
  static const _secureKey = 'network_secrets_v1';

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;

  static Future<NetworkSettingsRepository> create() async {
    final prefs = await SharedPreferences.getInstance();
    final repo = NetworkSettingsRepository(prefs, createSecureStorage());
    await repo._migrateLegacySecrets();
    return repo;
  }

  Future<void> _migrateLegacySecrets() async {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final hasSecrets =
          (json['wifi_password'] as String?)?.isNotEmpty == true ||
          (json['gsm_apn_pass'] as String?)?.isNotEmpty == true ||
          (json['device_key'] as String?)?.isNotEmpty == true;
      if (!hasSecrets) return;

      final existingSecure = await _secure.read(key: _secureKey);
      if (existingSecure == null || existingSecure.isEmpty) {
        await _secure.write(
          key: _secureKey,
          value: jsonEncode({
            'wifi_password': json['wifi_password'] ?? '',
            'gsm_apn_pass': json['gsm_apn_pass'] ?? '',
            'device_key': json['device_key'] ?? '',
          }),
        );
      }

      json['wifi_password'] = '';
      json['gsm_apn_pass'] = '';
      json['device_key'] = '';
      await _prefs.setString(_key, jsonEncode(json));
    } catch (_) {}
  }

  Future<NetworkSettings> load() async {
    final raw = _prefs.getString(_key);
    var base = const NetworkSettings();
    if (raw != null && raw.isNotEmpty) {
      try {
        base = NetworkSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        base = const NetworkSettings();
      }
    }

    final secretsRaw = await _secure.read(key: _secureKey);
    if (secretsRaw == null || secretsRaw.isEmpty) return base;
    try {
      final secrets = jsonDecode(secretsRaw) as Map<String, dynamic>;
      return base.copyWith(
        wifiPassword: secrets['wifi_password'] as String? ?? base.wifiPassword,
        gsmApnPass: secrets['gsm_apn_pass'] as String? ?? base.gsmApnPass,
        deviceKey: secrets['device_key'] as String? ?? base.deviceKey,
      );
    } catch (_) {
      return base;
    }
  }

  Future<void> save(NetworkSettings settings) async {
    final publicJson = settings.toJson()
      ..['wifi_password'] = ''
      ..['gsm_apn_pass'] = ''
      ..['device_key'] = '';
    await _prefs.setString(_key, jsonEncode(publicJson));
    await _secure.write(
      key: _secureKey,
      value: jsonEncode({
        'wifi_password': settings.wifiPassword,
        'gsm_apn_pass': settings.gsmApnPass,
        'device_key': settings.deviceKey,
      }),
    );
  }
}
