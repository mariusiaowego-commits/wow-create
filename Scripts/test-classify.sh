#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="/tmp/wow-classify-test"
FIXTURES="${1:-$ROOT/Tests/fixtures}"

clang -fobjc-arc -O2 -std=gnu11 -I"$ROOT/Sources/WoWCreate" \
  -framework Foundation \
  -framework AppKit \
  -framework ApplicationServices \
  -framework CoreGraphics \
  "$ROOT/Tests/classify_test.m" \
  "$ROOT/Sources/WoWCreate/FlowProfile.m" \
  "$ROOT/Sources/WoWCreate/ScreenCapture.m" \
  -o "$OUT"

"$OUT" "$FIXTURES"
