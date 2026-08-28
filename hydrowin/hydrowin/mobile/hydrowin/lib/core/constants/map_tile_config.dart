/// Тайлы карты (CARTO Voyager). Ключ — при сборке:
/// `--dart-define=CARTO_BASEMAP_KEY=...` (см. scripts/release-config.ps1).
abstract final class MapTileConfig {
  static const cartoBasemapKey = String.fromEnvironment(
    'CARTO_BASEMAP_KEY',
    defaultValue: '',
  );

  static const _voyagerRasterBase =
      'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';

  static String get cartoVoyagerRasterUrl {
    final key = cartoBasemapKey.trim();
    if (key.isEmpty) return _voyagerRasterBase;
    return '$_voyagerRasterBase?key=$key';
  }
}
