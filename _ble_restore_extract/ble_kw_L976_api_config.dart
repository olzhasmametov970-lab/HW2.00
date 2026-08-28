abstract final class ApiConfig {
  static const String _fromEnv = String.fromEnvironment('API_BASE_URL');

  /// Production API за Caddy (HTTPS).
  /// Сейчас: sslip.io → 5.165.27.141 (без DNS на REG.RU).
  /// Позже: https://api.hydrowin.ru/v1 после A-записи.
  /// Override: --dart-define=API_BASE_URL=...
  static String get defaultBaseUrl {
    if (_fromEnv.isNotEmpty) return _fromEnv;
    return 'https://5-165-27-141.sslip.io/v1';
  }

  /// Переходный HTTP (пока Caddy не поднят).
  static const localBaseUrl = 'http://5.165.27.141:8090/v1';
}
