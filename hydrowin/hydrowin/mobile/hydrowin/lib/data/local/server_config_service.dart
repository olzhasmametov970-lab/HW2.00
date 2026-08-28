import 'package:hydrowin/core/api/api_config.dart';
import 'package:hydrowin/data/local/developer_settings_repository.dart';
import 'package:hydrowin/domain/models/developer_settings.dart';

/// Вычисляет URL API для приложения (с учётом режима разработчика).
class ServerConfigService {
  ServerConfigService(this._developerRepo);

  final DeveloperSettingsRepository _developerRepo;

  String resolveApiBaseUrl() {
    final dev = _developerRepo.load();
    if (dev.isConfigured) {
      final url = dev.apiBaseUrl;
      if (ApiConfig.shouldPreferProduction(url)) {
        return ApiConfig.productionBaseUrl;
      }
      return url;
    }
    return ApiConfig.defaultBaseUrl;
  }

  DeveloperSettings get developerSettings => _developerRepo.load();
}
