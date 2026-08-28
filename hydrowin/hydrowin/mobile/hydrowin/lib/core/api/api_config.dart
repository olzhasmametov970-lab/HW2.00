abstract final class ApiConfig {
  static const String _fromEnv = String.fromEnvironment('API_BASE_URL');

  /// Публичный API + кабинет на одном хосте (Ubuntu Caddy).
  static const productionBaseUrl = 'https://app.hydrowin.ru/v1';

  /// Локальная отладка API (только LAN / docker).
  static const localBaseUrl = 'http://127.0.0.1:8090/v1';

  /// Override: --dart-define=API_BASE_URL=...
  /// Старые сборки (sslip / api.… / :8090) переводятся на production.
  static String get defaultBaseUrl {
    if (_fromEnv.isNotEmpty) {
      if (_isObsoleteApiUrl(_fromEnv)) return productionBaseUrl;
      return _fromEnv;
    }
    return productionBaseUrl;
  }

  static bool _isObsoleteApiUrl(String url) {
    final u = url.toLowerCase();
    return u.contains('sslip.io') ||
        u.contains('5-165-27-141') ||
        u.contains('5.165.27.141:8090') ||
        u.contains('192.168.1.57:8090') ||
        u.contains('192.168.1.58:8090') ||
        u.contains('://api.hydrowin.ru/');
  }

  static bool shouldPreferProduction(String current) {
    if (current.trim().isEmpty) return false;
    return _isObsoleteApiUrl(current);
  }
}
