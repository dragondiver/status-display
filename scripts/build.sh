#!/bin/bash
# Baut build/StatusDisplay.app (universal, ad-hoc signiert).
set -euo pipefail
cd "$(dirname "$0")/.."
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}" --product StatusDisplay
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/StatusDisplay"
APP=build/StatusDisplay.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/StatusDisplay"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "$APP"
