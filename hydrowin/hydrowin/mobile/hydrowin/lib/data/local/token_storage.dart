import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hydrowin/data/local/secure_storage_factory.dart';

class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? createSecureStorage();

  static const _keyAccess = 'access_token';
  static const _keyRefresh = 'refresh_token';
  static const _keyUserName = 'user_name';
  static const _keyUserEmail = 'user_email';
  static const _keyUserRole = 'user_role';
  static const _keyRememberLogin = 'remember_login';
  static const _keyRememberEmail = 'remember_email';
  /// Legacy — больше не пишем пароль; при чтении очищаем.
  static const _keyRememberPassword = 'remember_password';

  final FlutterSecureStorage _storage;

  Future<String?> getAccessToken() => _storage.read(key: _keyAccess);
  Future<String?> getRefreshToken() => _storage.read(key: _keyRefresh);

  Future<bool> hasSession() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  /// «Запомнить пользователя» на экране входа — только email, не пароль.
  Future<bool> getRememberLogin() async {
    final v = await _storage.read(key: _keyRememberLogin);
    return v == '1';
  }

  Future<({String email, String password})?> getRememberedCredentials() async {
    // Миграция: удалить ранее сохранённый plaintext password.
    await _storage.delete(key: _keyRememberPassword);
    if (!await getRememberLogin()) return null;
    final email = await _storage.read(key: _keyRememberEmail);
    if (email == null || email.isEmpty) return null;
    return (email: email, password: '');
  }

  Future<void> saveRememberedCredentials({
    required String email,
    String password = '',
  }) async {
    await _storage.write(key: _keyRememberLogin, value: '1');
    await _storage.write(key: _keyRememberEmail, value: email);
    // Пароль намеренно не храним (даже в secure storage).
    await _storage.delete(key: _keyRememberPassword);
  }

  Future<void> clearRememberedCredentials() async {
    await _storage.delete(key: _keyRememberLogin);
    await _storage.delete(key: _keyRememberEmail);
    await _storage.delete(key: _keyRememberPassword);
  }

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    String? userName,
    String? userEmail,
    String? userRole,
  }) async {
    await _storage.write(key: _keyAccess, value: accessToken);
    await _storage.write(key: _keyRefresh, value: refreshToken);
    if (userName != null) {
      await _storage.write(key: _keyUserName, value: userName);
    }
    if (userEmail != null) {
      await _storage.write(key: _keyUserEmail, value: userEmail);
    }
    if (userRole != null) {
      await _storage.write(key: _keyUserRole, value: userRole);
    }
  }

  Future<void> clear() async {
    await _clearAuthTokens();
    await _storage.delete(key: _keyUserName);
    await _storage.delete(key: _keyUserEmail);
    await _storage.delete(key: _keyUserRole);
  }

  Future<void> _clearAuthTokens() async {
    await _storage.delete(key: _keyAccess);
    await _storage.delete(key: _keyRefresh);
  }

  Future<String?> getUserName() => _storage.read(key: _keyUserName);
  Future<String?> getUserEmail() => _storage.read(key: _keyUserEmail);
  Future<String?> getUserRole() => _storage.read(key: _keyUserRole);

  Future<void> saveUserName(String name) =>
      _storage.write(key: _keyUserName, value: name);

  static bool get isWebStorage => kIsWeb;
}
