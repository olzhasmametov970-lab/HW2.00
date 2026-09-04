import 'dart:async';

import 'package:hydrowin/core/api/api_exception.dart';
import 'package:hydrowin/core/api/session_expired_exception.dart';
import 'package:hydrowin/data/demo/demo_fleet_data.dart';
import 'package:hydrowin/data/local/token_storage.dart';
import 'package:hydrowin/data/remote/api_client.dart';
import 'package:hydrowin/domain/models/auth_tokens.dart';
import 'package:hydrowin/domain/user_roles.dart';

class AuthRepository {
  AuthRepository(this._api, this._tokens);

  final ApiClient _api;
  final TokenStorage _tokens;

  Future<bool> isLoggedIn() => _tokens.hasSession();

  Future<bool> isDemoSession() async {
    if (DemoSession.isActive) return true;
    final token = await _tokens.getAccessToken();
    return token != null && token.startsWith('demo-');
  }

  Future<String?> currentRole() => _tokens.getUserRole();

  Future<bool> isAdmin() async {
    return UserRoles.isAdmin(await _tokens.getUserRole());
  }

  Future<bool> canConfigureHardware() async => isAdmin();

  /// Офлайн-демо завода: парк, графики, уведомления без API.
  Future<AuthTokens> loginDemo() async {
    DemoSession.start();
    final tokens = DemoFleetData.authTokens();
    await _persist(tokens);
    return tokens;
  }

  Future<AuthTokens> login({
    required String email,
    required String password,
  }) async {
    DemoSession.stop();
    final json = await _api.post(
      '/auth/login',
      body: {'email': email.trim(), 'password': password},
    );
    final tokens = AuthTokens.fromJson(json);
    await _persist(tokens);
    return tokens;
  }

  Future<AuthTokens> register({
    required String name,
    required String email,
    required String password,
    required String organizationName,
    required bool termsAccepted,
  }) async {
    DemoSession.stop();
    final json = await _api.post(
      '/auth/register',
      body: {
        'name': name.trim(),
        'email': email.trim(),
        'password': password,
        'organization_name': organizationName.trim(),
        'terms_accepted': termsAccepted,
      },
    );
    final tokens = AuthTokens.fromJson(json);
    await _persist(tokens);
    return tokens;
  }

  /// Смена своего пароля: текущий + новый.
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    if (DemoSession.isActive) {
      throw ApiException(
        400,
        'В демо-режиме смена пароля недоступна',
        code: 'demo',
      );
    }
    await _api.post(
      '/auth/change-password',
      body: {
        'old_password': oldPassword,
        'new_password': newPassword,
      },
      auth: true,
    );
    final remembered = await _tokens.getRememberedCredentials();
    if (remembered != null) {
      await _tokens.saveRememberedCredentials(email: remembered.email);
    }
  }

  Future<void> logout() async {
    final wasDemo = DemoSession.isActive || await isDemoSession();
    if (!wasDemo) {
      final refresh = await _tokens.getRefreshToken();
      if (refresh != null && refresh.isNotEmpty) {
        try {
          await _api.post(
            '/auth/logout',
            body: {'refresh_token': refresh},
            auth: true,
          );
        } catch (_) {}
      }
    }
    DemoSession.stop();
    await _tokens.clear();
  }

  Future<String?> currentUserName() async {
    return _tokens.getUserName();
  }

  Future<void> _persist(AuthTokens tokens) async {
    await _tokens.saveTokens(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      userName: tokens.user.name,
      userEmail: tokens.user.email,
      userRole: tokens.user.role,
    );
  }

  String humanizeError(Object error) {
    if (error is TimeoutException) {
      return 'Сервер не ответил вовремя. Проверьте связь и нажмите «Повторить».';
    }
    if (error is SessionExpiredException) {
      return 'Сессия истекла. Войдите снова.';
    }
    if (error is ApiException) {
      if (error.statusCode == 401) {
        return 'Неверный email или пароль';
      }
      if (error.code == 'wrong_password') {
        return 'Неверный текущий пароль';
      }
      if (error.code == 'same_password') {
        return 'Новый пароль должен отличаться от текущего';
      }
      if (error.code == 'weak_password') {
        return error.message.isNotEmpty
            ? error.message
            : 'Пароль слишком простой';
      }
      if (error.statusCode == 403) {
        return 'Недостаточно прав для этого действия';
      }
      if (error.statusCode == 404) {
        return error.message.isNotEmpty && error.message != 'Not Found'
            ? error.message
            : 'Данные не найдены на сервере';
      }
      return error.message;
    }
    return 'Нет связи с сервером. Проверьте интернет.';
  }
}
