# Настройки release-сборок ГидроВин (один раз — во все .apk / .exe / web)
# Меняйте только этот файл перед сборкой.

# Публичный API (Caddy HTTPS → Ubuntu VM). Не использовать :8090 снаружи — порт закрыт.
$ReleaseApiUrl = "https://app.hydrowin.ru/v1"

# true = приложение сразу открывает вход в облако (без выбора режима)
$ReleasePresetCloud = $true

# true = кнопка «Демо завода (без сервера)» на экране входа
$ReleaseEnableDemo = $true

# CARTO basemaps (карта). Ключ: carto.com/basemaps/apikey
$ReleaseCartoBasemapKey = "cb1_29zg_1_2bf178ba6304923c3f84296b"