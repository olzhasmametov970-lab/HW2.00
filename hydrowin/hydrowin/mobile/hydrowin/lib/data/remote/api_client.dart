import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:hydrowin/core/api/api_config.dart';
import 'package:hydrowin/core/api/api_exception.dart';
import 'package:hydrowin/core/api/session_expired_exception.dart';
import 'package:hydrowin/data/local/token_storage.dart';

class ApiClient {
  ApiClient(this._tokens, {http.Client? httpClient, String? baseUrl})
    : _http = httpClient ?? http.Client(),
      baseUrl = baseUrl ?? ApiConfig.defaultBaseUrl;

  final TokenStorage _tokens;
  final http.Client _http;
  String baseUrl;

  /// Без таймаута HTTP может висеть бесконечно → вечный спиннер в UI.
  static const Duration requestTimeout = Duration(seconds: 20);

  Uri _uri(String path, {Map<String, String>? query}) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalized').replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    bool auth = true,
  }) async {
    final response = await _performGet(path, query: query, auth: auth);
    return _decodeMapOrThrow(response);
  }

  Future<List<dynamic>> getList(
    String path, {
    Map<String, String>? query,
    bool auth = true,
  }) async {
    final response = await _performGet(path, query: query, auth: auth);
    final decoded = _decodeBody(response);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decoded is List<dynamic>) return decoded;
      throw ApiException(response.statusCode, 'Ожидался JSON-массив в ответе');
    }
    throw _errorFrom(response, decoded);
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    bool auth = false,
  }) async {
    final response = await _performPost(path, body: body, auth: auth);
    return _parseMapResponse(response);
  }

  /// Отправка одиночного объекта на сервер (Обновление данных машины и т.д.)
  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
  }) async {
    final response = await _performPut(path, body: body, auth: auth);
    return _parseMapResponse(response);
  }

  Future<List<dynamic>> putList(
    String path, {
    required List<Map<String, dynamic>> body,
    bool auth = true,
  }) async {
    final response = await _performPut(path, body: body, auth: auth);
    final decoded = _decodeBody(response);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decoded is List<dynamic>) return decoded;
      return const [];
    }
    throw _errorFrom(response, decoded);
  }

  Future<void> delete(String path, {bool auth = true}) async {
    final response = await _performDelete(path, auth: auth);
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw _errorFrom(response, _decodeBody(response));
  }

  Future<Map<String, String>> _authHeaders({required bool auth}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (!auth) return headers;

    final token = await _tokens.getAccessToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<http.Response> _performPost(
    String path, {
    Map<String, dynamic>? body,
    bool auth = false,
    bool isRetry = false,
  }) async {
    final response = await _http
        .post(
          _uri(path),
          headers: await _authHeaders(auth: auth),
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(requestTimeout);

    if (response.statusCode == 401 && auth && !isRetry) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        return _performPost(path, body: body, auth: auth, isRetry: true);
      }
      await _handleSessionExpired();
    }

    return response;
  }

  Future<http.Response> _performPut(
    String path, {
    dynamic body,
    bool auth = true,
    bool isRetry = false,
  }) async {
    final response = await _http
        .put(
          _uri(path),
          headers: await _authHeaders(auth: auth),
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(requestTimeout);

    if (response.statusCode == 401 && auth && !isRetry) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        return _performPut(path, body: body, auth: auth, isRetry: true);
      }
      await _handleSessionExpired();
    }

    return response;
  }

  Future<http.Response> _performDelete(
    String path, {
    bool auth = true,
    bool isRetry = false,
  }) async {
    final response = await _http
        .delete(
          _uri(path),
          headers: await _authHeaders(auth: auth),
        )
        .timeout(requestTimeout);

    if (response.statusCode == 401 && auth && !isRetry) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        // Здесь исправлено: возвращен первый позиционный аргумент path
        return _performDelete(path, auth: auth, isRetry: true);
      }
      await _handleSessionExpired();
    }

    return response;
  }

  Future<http.Response> _performGet(
    String path, {
    Map<String, String>? query,
    bool auth = true,
    bool isRetry = false,
  }) async {
    final response = await _http
        .get(
          _uri(path, query: query),
          headers: await _authHeaders(auth: auth),
        )
        .timeout(requestTimeout);

    if (response.statusCode == 401 && auth && !isRetry) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        return _performGet(path, query: query, auth: auth, isRetry: true);
      }
      await _handleSessionExpired();
    }

    return response;
  }

  Future<void> _handleSessionExpired() async {
    await _tokens.clear();
    throw const SessionExpiredException();
  }

  Future<bool> _tryRefresh() async {
    final refresh = await _tokens.getRefreshToken();
    if (refresh == null || refresh.isEmpty) return false;

    try {
      final response = await _http
          .post(
            _uri('/auth/refresh'),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'refresh_token': refresh}),
          )
          .timeout(requestTimeout);
      if (response.statusCode != 200) return false;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      await _tokens.saveTokens(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Object? _decodeBody(http.Response response) {
    if (response.body.isEmpty) return null;
    try {
      return jsonDecode(response.body);
    } on FormatException {
      // Сервер вернул plain-text (например "Internal Server Error") вместо JSON
      return response.body;
    }
  }

  Map<String, dynamic> _decodeMapOrThrow(http.Response response) {
    final decoded = _decodeBody(response);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded == null) return <String, dynamic>{};
      throw ApiException(response.statusCode, 'Ожидался JSON-объект в ответе');
    }
    throw _errorFrom(response, decoded);
  }

  ApiException _errorFrom(http.Response response, Object? decoded) {
    // FastAPI wraps payloads as {"detail": ...} (string, object, or list).
    Object? payload = decoded;
    if (decoded is Map<String, dynamic> && decoded.containsKey('detail')) {
      payload = decoded['detail'];
    }

    if (payload is Map<String, dynamic>) {
      final message = payload['message'] as String? ??
          'Ошибка сервера (${response.statusCode})';
      return ApiException(
        response.statusCode,
        message,
        code: payload['code'] as String?,
      );
    }
    if (payload is List && payload.isNotEmpty) {
      // Pydantic validation: [{loc, msg, type}, ...]
      final first = payload.first;
      if (first is Map<String, dynamic>) {
        final msg = first['msg'] as String? ?? 'Некорректные данные';
        final loc = first['loc'];
        final where = loc is List && loc.isNotEmpty ? loc.last.toString() : null;
        return ApiException(
          response.statusCode,
          where != null ? '$msg ($where)' : msg,
          code: 'validation_error',
        );
      }
    }
    if (payload is String && payload.isNotEmpty) {
      return ApiException(response.statusCode, payload);
    }
    return ApiException(
      response.statusCode,
      'Ошибка сервера (${response.statusCode})',
    );
  }

  Map<String, dynamic> _parseMapResponse(http.Response response) {
    final decoded = _decodeBody(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decoded is Map<String, dynamic>) return decoded;
      return <String, dynamic>{};
    }

    throw _errorFrom(response, decoded);
  }

  void dispose() => _http.close();
}
