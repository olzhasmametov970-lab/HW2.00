# Сборка ГидроВин для iOS

> **Важно:** IPA / запуск на iPhone собираются **только на Mac** с Xcode.
> На Windows можно подготовить код (уже сделано), но `flutter build ios` здесь не выполнится.

## Что уже настроено в проекте

- Папка `ios/` (bundle id: `ru.hydrowin.hydrowin`)
- `Info.plist`: Bluetooth Always / Peripheral, Location When In Use, background `bluetooth-central`
- `Podfile`: CocoaPods + `PERMISSION_BLUETOOTH`, location, notifications
- `AppDelegate`: регистрация `flutter_local_notifications`
- Dart: BLE включён на iOS (`isSupported`), запрос `Permission.bluetooth`

## Требования (Mac)

1. macOS + [Xcode](https://developer.apple.com/xcode/) 15+
2. [Flutter](https://docs.flutter.dev/get-started/install/macos) 3.11+
3. CocoaPods: `sudo gem install cocoapods`
4. Apple ID (бесплатно для своего iPhone) или Apple Developer ($99/год для TestFlight / App Store)

```bash
flutter doctor
flutter config --enable-ios
```

## Разработка на устройстве / симуляторе

```bash
cd mobile/hydrowin
flutter pub get
cd ios && pod install && cd ..

# Симулятор (без реального BLE)
flutter run -d "iPhone 16" --dart-define=API_BASE_URL=https://api.hydrowin.ru/v1

# Физический iPhone (USB, доверять компьютеру)
flutter devices
flutter run -d <deviceId> --dart-define=API_BASE_URL=https://api.hydrowin.ru/v1
```

В Xcode: откройте `ios/Runner.xcworkspace` → Signing & Capabilities → выберите Team (ваш Apple ID).

## Release (IPA для установки / TestFlight)

```bash
cd mobile/hydrowin
flutter pub get
cd ios && pod install && cd ..

flutter build ipa --release \
  --dart-define=API_BASE_URL=https://api.hydrowin.ru/v1 \
  --dart-define=PRESET_CLOUD=true
```

**Результат:** `build/ios/ipa/*.ipa`

Или через скрипт (на Mac):

```bash
chmod +x scripts/build-ios.sh
./scripts/build-ios.sh https://api.hydrowin.ru/v1
```

Загрузка в TestFlight: Xcode → Organizer → Distribute App, либо:

```bash
xcrun altool --upload-app --type ios -f build/ios/ipa/*.ipa \
  --apiKey … --apiIssuer …
```

## BLE на iPhone

1. Bluetooth **включён**
2. Настройки → ГидроВин → разрешить Bluetooth (после первого скана)
3. В приложении: **Настройки → Подключить блок по Bluetooth → Найти блоки**
4. Рядом должна быть плата с NimBLE: имя `HydroWin-…`

Симулятор iOS **не имеет** реального BLE — проверяйте на устройстве.

## Режимы

| Режим | iOS |
|-------|-----|
| Облако (парк, графики) | ✅ |
| BLE у машины | ✅ (физический iPhone) |
| Демо без сервера | debug / `ENABLE_DEMO` |

## Частые проблемы

| Проблема | Что сделать |
|----------|-------------|
| `No valid code signing` | Xcode → Runner → Signing → Team |
| `pod: command not found` | `sudo gem install cocoapods` |
| Пустой скан BLE | Физический телефон; разрешения; плата advertising |
| ATS / HTTP blocked | Используйте HTTPS API (`https://…/v1`) |
