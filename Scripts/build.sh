#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/WoWCreate.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"

rm -rf "$APP"
mkdir -p "$MACOS" "$CONTENTS/Resources"

GIT_SHORT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo nogit)"
if ! git -C "$ROOT" diff --quiet 2>/dev/null; then
  GIT_SHORT="${GIT_SHORT}-dirty"
fi
BUILD_TIME="$(date '+%Y-%m-%d %H:%M')"

clang -fobjc-arc -O2 -std=gnu11 \
  -framework AppKit \
  -framework ApplicationServices \
  -framework CoreGraphics \
  -framework Vision \
  -framework Carbon \
  -framework QuartzCore \
  "$ROOT/Sources/WoWCreate/main.m" \
  "$ROOT/Sources/WoWCreate/AppDelegate.m" \
  "$ROOT/Sources/WoWCreate/FlowEngine.m" \
  "$ROOT/Sources/WoWCreate/FlowProfile.m" \
  "$ROOT/Sources/WoWCreate/ScreenCapture.m" \
  "$ROOT/Sources/WoWCreate/HotKeyMonitor.m" \
  -o "$MACOS/WoWCreate"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>WoWCreate</string>
  <key>CFBundleIdentifier</key><string>local.wowcreate.app</string>
  <key>CFBundleName</key><string>WoWCreate</string>
  <key>CFBundleDisplayName</key><string>WoWCreate</string>
  <key>CFBundleShortVersionString</key><string>0.2.2</string>
  <key>CFBundleVersion</key><string>${GIT_SHORT}</string>
  <key>WoWCreateBuildTime</key><string>${BUILD_TIME}</string>
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
import zlib
from pathlib import Path

def render(size):
    scale = 2 if size <= 128 else 1
    big = size * scale
    pixels = bytearray(big * big * 4)
    center = big / 2
    outer = big * 0.46
    inner = big * 0.37
    for y in range(big):
        dy = y + 0.5 - center
        row = y * big * 4
        for x in range(big):
            dx = x + 0.5 - center
            radius = (dx * dx + dy * dy) ** 0.5
            off = row + x * 4
            if radius > outer:
                continue
            if radius > inner:
                pixels[off:off + 4] = b"\xff\xbc\x2e\xff"
            else:
                pixels[off:off + 4] = b"\x74\x00\x00\xff"
    if scale == 1:
        return bytes(pixels)
    out = bytearray(size * size * 4)
    for y in range(size):
        for x in range(size):
            r = g = b = a = 0
            for sy in (0, 1):
                for sx in (0, 1):
                    off = ((y * scale + sy) * big + x * scale + sx) * 4
                    r += pixels[off]
                    g += pixels[off + 1]
                    b += pixels[off + 2]
                    a += pixels[off + 3]
            off = (y * size + x) * 4
            out[off:off + 4] = bytes((r // 4, g // 4, b // 4, a // 4))
    return bytes(out)

def png_chunk(chunk_type: bytes, data: bytes) -> bytes:
    return (struct.pack(">I", len(data)) + chunk_type + data +
            struct.pack(">I", zlib.crc32(chunk_type + data) & 0xFFFFFFFF))

def png_for(size):
    rgba = render(size)
    raw = bytearray()
    for y in range(size):
        raw.append(0)
        raw += rgba[y * size * 4:(y + 1) * size * 4]
    return (b"\x89PNG\r\n\x1a\n" +
            png_chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)) +
            png_chunk(b"IDAT", zlib.compress(bytes(raw), 9)) +
            png_chunk(b"IEND", b""))

entries = [(16, b"icp4"), (32, b"icp5"), (32, b"ic11"), (64, b"icp6"),
           (64, b"ic12"), (128, b"ic07"), (256, b"ic08"), (256, b"ic13"),
           (512, b"ic09"), (512, b"ic14"), (1024, b"ic10")]
cache = {}
body = bytearray()
for size, tag in entries:
    if size not in cache:
        cache[size] = png_for(size)
    data = cache[size]
    body += tag + struct.pack(">I", 8 + len(data)) + data

out = Path(sys.argv[1])
out.write_bytes(b"icns" + struct.pack(">I", 8 + len(body)) + bytes(body))
PY

touch "$APP"
echo "built: $APP"
