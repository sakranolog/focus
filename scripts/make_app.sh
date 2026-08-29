#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "${UNIVERSAL:-0}" = "1" ]; then
  swift build -c release --arch arm64 --arch x86_64
  BIN=".build/apple/Products/Release/Focus"
else
  swift build -c release
  BIN=".build/release/Focus"
fi

APP="build/Focus.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Focus"
cp packaging/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
if [ -f packaging/AppIcon.icns ]; then
  cp packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
if [ -d assets/Music ]; then
  mkdir -p "$APP/Contents/Resources/Music"
  cp assets/Music/*.caf "$APP/Contents/Resources/Music/" 2>/dev/null || true
fi
codesign --force --sign - "$APP" > /dev/null 2>&1 || true
echo "Built $APP"
