#!/usr/bin/env bash
# Сборка IPA ГидроВин — только на macOS + Xcode.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Ошибка: сборка iOS возможна только на Mac (сейчас: $(uname -s))" >&2
  exit 1
fi

API_URL="${1:-https://api.hydrowin.ru/v1}"
PRESET_CLOUD="${PRESET_CLOUD:-true}"
ENABLE_DEMO="${ENABLE_DEMO:-false}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/mobile/hydrowin"

DEFINES=(--dart-define="API_BASE_URL=$API_URL")
if [[ "$PRESET_CLOUD" == "true" ]]; then
  DEFINES+=(--dart-define=PRESET_CLOUD=true)
fi
if [[ "$ENABLE_DEMO" == "true" ]]; then
  DEFINES+=(--dart-define=ENABLE_DEMO=true)
fi

cd "$APP"
flutter pub get
(cd ios && pod install)

flutter build ipa --release "${DEFINES[@]}"

IPA_DIR="$APP/build/ios/ipa"
echo ""
echo "IPA: $IPA_DIR"
ls -la "$IPA_DIR"/*.ipa 2>/dev/null || echo "(откройте Xcode Organizer, если ipa ещё не экспортирован)"
