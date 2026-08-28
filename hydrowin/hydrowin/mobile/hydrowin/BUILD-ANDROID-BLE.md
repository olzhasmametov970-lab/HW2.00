# BLE build notes (Android / Windows)

HydroWin BLE: Android first; Windows via WinRT plugin.

## Added dependencies

- `flutter_blue_plus` (^2.x, pulls `flutter_blue_plus_winrt` on Windows)
- `flutter_local_notifications`
- `permission_handler`

## Android requirements

- `minSdk = 21`
- Manifest permissions:
  - `BLUETOOTH`
  - `BLUETOOTH_ADMIN`
  - `BLUETOOTH_SCAN`
  - `BLUETOOTH_CONNECT`
  - `ACCESS_COARSE_LOCATION`
  - `ACCESS_FINE_LOCATION`
  - `POST_NOTIFICATIONS`
  - `INTERNET`

## Windows requirements

- Bluetooth adapter enabled in Windows settings
- `flutter_blue_plus` 2.x → endorsed `flutter_blue_plus_winrt`
- Build: `flutter build windows` (CMake suppresses WinRT `/wd4864` for newer MSVC)

## Verify

```bash
flutter pub get
flutter analyze
```

## BLE flow

1. Open `Настройки` → `Подключить блок по Bluetooth`
2. Scan for `HydroWin-*`
3. Connect to the block
4. Send Wi‑Fi / API settings
5. Confirm live telemetry (Android: live summary notification; Windows: on-screen gauges)
