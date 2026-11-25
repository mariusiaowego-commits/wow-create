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
  "$ROOT/Sources/WoWCreate/FlowEngine.m" \
  "$ROOT/Sources/WoWCreate/FlowProfile.m" \
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
  <key>CFBundleIconFile</key><string>AppIcon</string>
</dict>
</plist>
PLIST

python3 - "$CONTENTS/Resources/AppIcon.icns" <<'PY'
import struct
import sys
from pathlib import Path

size = 512
rgba = bytearray()
for y in range(size):
    for x in range(size):
        dx = x - size / 2
        dy = y - size / 2
        radius = (dx * dx + dy * dy) ** 0.5
        if radius > size * 0.46:
            rgba += bytes((0, 0, 0, 0))
        elif radius > size * 0.37:
            rgba += bytes((255, 188, 46, 255))
        else:
            rgba += bytes((116, 0, 0, 255))

def png_chunk(chunk_type: bytes, data: bytes) -> bytes:
    return (struct.pack(">I", len(data)) + chunk_type + data +
            struct.pack(">I", __import__("zlib").crc32(chunk_type + data) & 0xFFFFFFFF))

raw = bytearray()
for y in range(size):
    raw.append(0)
    raw += rgba[y * size * 4:(y + 1) * size * 4]

png = (b"\x89PNG\r\n\x1a\n" +
       png_chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)) +
       png_chunk(b"IDAT", __import__("zlib").compress(bytes(raw), 9)) +
       png_chunk(b"IEND", b""))

out = Path(sys.argv[1])
out.write_bytes(b"icns" + struct.pack(">I", 8 + len(png)) + b"ic11" + png)
PY

touch "$APP"
echo "built: $APP"
