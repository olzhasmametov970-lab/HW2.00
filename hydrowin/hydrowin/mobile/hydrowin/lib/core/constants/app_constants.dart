abstract final class AppConstants {
  /// Сборка: `full` (облако + учётная запись) или `lite` (только BLE, без сервера).
  /// Пример: `--dart-define=APP_VARIANT=lite --flavor lite`
  static const appVariant = String.fromEnvironment(
    'APP_VARIANT',
    defaultValue: 'full',
  );

  static bool get isLite => appVariant.toLowerCase() == 'lite';
  static bool get isFull => !isLite;

  /// Демо завода без сервера на экране входа.
  /// Отключить: `--dart-define=ENABLE_DEMO=false`
  static const enableDemoFlag = bool.fromEnvironment(
    'ENABLE_DEMO',
    defaultValue: true,
  );

  static bool get demoAvailable => enableDemoFlag;

  /// Lite без активной демо-сессии — только BLE.
  static bool get isLiteBleOnly => isLite;

  static String get appName => isLite ? 'ГидроВин Lite' : 'ГидроВин';

  static const splashDuration = Duration(seconds: 2);

  /// BLE телеметрия v2: CH0–CH5 (все ADC1), 21 байт.
  static const telemetryPacketLength = 21;
  static const telemetryProtoVersion = 0x02;
  static const telemetryChannelCount = 6;

  /// Совместимость со старыми платами (v1: CH0–CH2, 14 байт).
  static const telemetryPacketLengthV1 = 14;
  static const telemetryProtoVersionV1 = 0x01;

  static const prefsKeyFirstLaunch = 'first_launch_done';
  static const prefsKeyWorkMode = 'work_mode';
  static const prefsKeyThemeMode = 'theme_mode';
  static const prefsKeySingleMachineId = 'single_machine_id';
  static const prefsKeyPollSeconds = 'poll_interval_seconds';
  static const prefsKeyDevUnlocked = 'developer_unlocked';
  static const prefsKeyBleAliases = 'ble_block_aliases_v1';

  /// Режимы работы приложения.
  static const workModeSingle = 'single';
  static const workModeFleet = 'fleet';

  /// Устаревшие значения (миграция со старых сборок).
  static const workModeBleLegacy = 'ble';
  static const workModeCloudLegacy = 'cloud';

  static const BLOCKLinkWifi = 'wifi';
  static const BLOCKLinkGsm = 'gsm';
  static const BLOCKLinkAuto = 'auto';

  /// Пароль разработчика только через сборку: `--dart-define=DEV_PASSWORD=...`
  /// Пустой = вход в developer-меню по умолчанию закрыт (пока не задан свой пароль).
  static const defaultDeveloperPassword = String.fromEnvironment(
    'DEV_PASSWORD',
    defaultValue: '',
  );

  /// Показывать пункт «Разработчик» в настройках.
  static const enableDeveloperMenu = bool.fromEnvironment(
    'ENABLE_DEVELOPER',
    defaultValue: false,
  );

  /// Release-сборка: сразу «Парк машин», без выбора на первом экране.
  static const presetCloudMode = bool.fromEnvironment(
    'PRESET_CLOUD',
    defaultValue: false,
  );
  static const localHistoryDays = 7;

  /// Макс. датчиков блока = 6 каналов ADC1 (CH0–CH5).
  static const hardwareAnalogChannels = 6;

  /// GPIO ADC1: ch0→35 … ch5→39 (стабильно с Wi‑Fi).
  static const adc1GpioPins = <int>[35, 34, 33, 32, 36, 39];

  static int gpioForChannel(int channel) {
    if (channel < 0 || channel >= adc1GpioPins.length) return -1;
    return adc1GpioPins[channel];
  }

  static const defaultPollSeconds = 5;
  static const minPollSeconds = 5;
  static const maxPollSeconds = 60;
}
