# Сборка приложений ГидроВин (Web, Windows, Android, iOS)

## Все три сразу → папка `release/`

**Один клик (из корня проекта):** `Собрать-приложения.bat`

| Платформа | Готовый файл | Запуск |
|-----------|--------------|--------|
| Android | `release/android/GidroVin.apk` | Установить APK |
| Windows | `release/windows/Запуск ГидроВин.bat` | Один клик |
| Web | `release/web/Запуск ГидроВин.bat` | Один клик |
| iOS | только на Mac → IPA / TestFlight | см. [BUILD-IOS.md](BUILD-IOS.md) |

Настройки API: `scripts/release-config.ps1`  
Подробно: [`docs/BUILD-RELEASE.md`](../../docs/BUILD-RELEASE.md)

---

Один Flutter-проект — Android / Windows / Web / **iOS**. Замените `api.hydrowin.ru` на ваш API-домен.

## Требования

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.11+
- **Android:** Android Studio, SDK, USB-отладка или эмулятор
- **Windows:** Visual Studio 2022 с «Desktop development with C++»
- **Web:** Chrome
- **iOS:** **Mac** + Xcode + CocoaPods (на Windows IPA собрать нельзя)

Проверка:

```powershell
flutter doctor
```

---

## URL API при сборке

Все release-сборки указывают на ваш сервер:

```powershell
$api = "https://api.hydrowin.ru/v1"
```

Локальная разработка против Docker API:

```powershell
$api = "http://localhost:8090/v1"
```

---

## 1. Android (APK)

Нужен **flavor** (`full` или `lite`) — иначе Gradle не соберёт.

### Полная версия (облако + BLE)

```powershell
cd mobile\hydrowin
flutter pub get
flutter build apk --release --flavor full --dart-define=APP_VARIANT=full --dart-define=API_BASE_URL=https://api.hydrowin.ru/v1
```

**Результат:** `build\app\outputs\flutter-apk\app-full-release.apk`  
Пакет: `ru.hydrowin.hydrowin`

Или из корня репозитория: `.\scripts\build-android.ps1 -Variant full`

### Lite (только Bluetooth, без сервера)

```powershell
cd mobile\hydrowin
flutter pub get
flutter build apk --release --flavor lite --dart-define=APP_VARIANT=lite --dart-define=ENABLE_DEMO=true
```

**Результат:** `build\app\outputs\flutter-apk\app-lite-release.apk`  
Пакет: `ru.hydrowin.hydrowin.lite` (ставится рядом с полной версией)

В Lite после splash: **главная** → Bluetooth **или демо-парк** (5 учебных машин с живыми шкалами без BLE).

Или один клик: `Собрать-Lite-APK.bat` → копия в `C:\GidroVin\Android\GidroVin-Lite.apk`

Установка на телефон: скопируйте APK, разрешите установку из неизвестных источников.

Для Google Play — позже `flutter build appbundle --flavor full` / `--flavor lite`.

---

## 2. Windows (exe) — для ноутбука

На ноутбуке Flutter не нужен: копируете папку или ZIP целиком.

### Lite (только Bluetooth) — скинуть на ноутбук

Один клик: `Собрать-Lite-Windows.bat`

Или:

```powershell
.\scripts\build-windows.ps1 -Variant lite
```

**Готово к передаче:**
- папка `C:\GidroVin\Windows_Lite\` — скопировать на флешку / по сети
- архив `C:\GidroVin\GidroVin-Lite-Windows.zip` — можно отправить в мессенджер

На ноутбуке: распаковать ZIP → `START.bat` (или `hydrowin.exe`). Нужен Windows 10/11 x64 и Bluetooth.

### Полная версия (облако + BLE)

```powershell
.\scripts\build-windows.ps1 -Variant full -ApiUrl "https://api.hydrowin.ru/v1"
```

Или вручную:

```powershell
cd mobile\hydrowin
flutter pub get
flutter config --enable-windows-desktop
flutter build windows --release --dart-define=APP_VARIANT=full --dart-define=API_BASE_URL=https://api.hydrowin.ru/v1
```

**Результат:** `build\windows\x64\runner\Release\` — папка с `hydrowin.exe`.

> BLE на Windows через WinRT: нужен включённый Bluetooth. Lite работает без сервера.

---

## 3. Web (браузер) — только Full

Облачное приложение в браузере (логин, парк, графики). BLE / Lite на сайте нет.

```powershell
cd hydrowin   # корень репо с scripts/
.\scripts\build-web.ps1 -ApiUrl "https://app.hydrowin.ru/v1"
```

Скрипт собирает с `APP_VARIANT=full` и копирует в:
- `release\web\` (+ START.bat для локальной проверки)
- `backend\web\` — отдаёт Caddy как `https://<домен>/`

**Выкладка на Ubuntu** (из Windows PowerShell):

```powershell
scp -r C:\Users\Admin2\Desktop\HW2.0\hydrowin\hydrowin\backend\web hydrowin@192.168.1.57:~/hydrowin-backend/
scp C:\Users\Admin2\Desktop\HW2.0\hydrowin\hydrowin\backend\Caddyfile hydrowin@192.168.1.57:~/hydrowin-backend/
ssh hydrowin@192.168.1.57 "cd ~/hydrowin-backend && docker compose up -d caddy"
```

Открыть: `https://app.hydrowin.ru/`  
API: `https://app.hydrowin.ru/v1/...`

В `.env`: `API_DOMAIN=app.hydrowin.ru`, `APP_DOMAIN=app.hydrowin.ru`.

> BLE в браузере почти не работает — web только для Full (облако).
---

## 4. iOS (iPhone / iPad) — только на Mac

Подробно: [BUILD-IOS.md](BUILD-IOS.md)

```bash
cd mobile/hydrowin
flutter pub get
cd ios && pod install && cd ..
flutter build ipa --release --dart-define=API_BASE_URL=https://api.hydrowin.ru/v1
```

Или: `./scripts/build-ios.sh https://api.hydrowin.ru/v1`

**Результат:** `build/ios/ipa/*.ipa` → TestFlight / устройство через Xcode.

---

## Быстрые скрипты (из корня репозитория)

```powershell
.\scripts\build-android.ps1 -Variant full -ApiUrl "https://api.hydrowin.ru/v1"
.\scripts\build-android.ps1 -Variant lite
.\scripts\build-windows.ps1 -ApiUrl "https://api.hydrowin.ru/v1"
.\scripts\build-web.ps1 -ApiUrl "https://api.hydrowin.ru/v1"
# iOS — на Mac:
# ./scripts/build-ios.sh https://api.hydrowin.ru/v1
```

---

## Демо завода (full и lite)

Офлайн-режим с парком, графиками, уведомлениями и GSM без сервера (`ENABLE_DEMO=true` по умолчанию).

- **Full:** экран входа → «Демо завода (без сервера)»
- **Lite:** главная → «Демо завода» (тот же UI парка)

Сборка уже передаёт `--dart-define=ENABLE_DEMO=true`.

