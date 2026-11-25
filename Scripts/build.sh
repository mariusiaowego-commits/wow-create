#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/WoWCreate.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"

rm -rf "$APP"
mkdir -p "$MACOS" "$CONTENTS/Resources"

clang -fobjc-arc -O2 -std=gnu11 \
  -framework AppKit \
  -framework ApplicationServices \
  -framework CoreGraphics \
  -framework Vision \
  -framework Carbon \
  "$ROOT/Sources/WoWCreate/main.m" \
  "$ROOT/Sources/WoWCreate/AppDelegate.m" \
  "$ROOT/Sources/WoWCreate/AutomationEngine.m" \
  "$ROOT/Sources/WoWCreate/ScreenCapture.m" \
  "$ROOT/Sources/WoWCreate/HotKeyMonitor.m" \
  -o "$MACOS/WoWCreate"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>WoWCreate</string>
  <key>CFBundleIdentifier</key><string>local.wowcreate.app</string>
  <key>CFBundleName</key><string>WoWCreate</string>
  <key>CFBundleDisplayName</key><string>WoWCreate</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>LSUIElement</key><false/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

touch "$APP"
echo "built: $APP"
