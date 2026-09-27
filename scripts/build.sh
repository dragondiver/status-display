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
cp "$BIN" "$APP/Contents/MacOS/StatusDisplay"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "$APP"
