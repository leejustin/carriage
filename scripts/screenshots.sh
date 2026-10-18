#!/bin/zsh
# Captures App Store screenshots from the simulator with demo content.
#
#   scripts/screenshots.sh "iPhone 18 Pro Max"            # regular iPhone (6.9-inch set)
#   scripts/screenshots.sh "iPhone Duo"                    # once Xcode 27.1 has the Duo simulator
#
# Uses a Debug build, because the demo content and scene staging are debug-only.
set -euo pipefail
DEVICE=${1:-"iPhone 18 Pro Max"}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/docs/screenshots/${DEVICE// /-}"
DERIVED="${TMPDIR:-/tmp}/carriage-screenshots"
mkdir -p "$OUT"

UDID=$(xcrun simctl list devices available | grep -F "$DEVICE (" | head -1 | grep -oE '[0-9A-F-]{36}')
[[ -n "$UDID" ]] || { echo "No simulator named $DEVICE"; exit 1; }
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3

xcodebuild -project "$ROOT/Carriage.xcodeproj" -scheme Carriage -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$DERIVED" build -quiet
APP="$DERIVED/Build/Products/Debug-iphonesimulator/Carriage.app"

# The Duo's half-folded and flat layouts are real on a Duo simulator; elsewhere they're simulated.
FOLD=regular
[[ "$DEVICE" == *Duo* ]] && FOLD=off

shoot() {
  local name=$1; shift
  xcrun simctl terminate "$UDID" com.leejustin.carriage 2>/dev/null || true
  xcrun simctl uninstall "$UDID" com.leejustin.carriage 2>/dev/null || true
  xcrun simctl install "$UDID" "$APP"
  xcrun simctl launch "$UDID" com.leejustin.carriage -seedDemo -seenOnboarding YES -foldSimulation "$FOLD" "$@" >/dev/null
  sleep 4
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null
  echo "  $name"
}

echo "Screenshots for $DEVICE → $OUT"
shoot 01-typing
shoot 02-focus -screenshotScene focus
shoot 03-library -screenshotScene library
shoot 04-night -nightDesk on -finish enamel
shoot 05-cherry -finish cherry -keyboardStyle split
xcrun simctl status_bar "$UDID" clear
