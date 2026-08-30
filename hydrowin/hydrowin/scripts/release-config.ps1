# Настройки release-сборок ГидроВин (один раз — во все .apk / .exe / web)
# Меняйте только этот файл перед сборкой.

# Публичный API (Caddy HTTPS → Ubuntu VM). Не использовать :8090 снаружи — порт закрыт.
$ReleaseApiUrl = "https://app.hydrowin.ru/v1"

# true = приложение сразу открывает вход в облако (без выбора режима)
$ReleasePresetCloud = $true

# true = кнопка «Демо завода (без сервера)» на экране входа
$ReleaseEnableDemo = $true

# CARTO basemaps (карта). Задайте перед сборкой: $env:CARTO_BASEMAP_KEY = "..."
# Ключ: carto.com/basemaps/apikey — не хранить в git.
$ReleaseCartoBasemapKey = $env:CARTO_BASEMAP_KEY