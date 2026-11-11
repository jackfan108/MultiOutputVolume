#!/bin/bash
# Builds build/MultiOutputVolume.app as a universal (Apple Silicon + Intel) binary.
# Usage: ./build.sh [--zip]   (--zip also writes build/MultiOutputVolume.zip for a release)
set -euo pipefail
cd "$(dirname "$0")"

MIN_MACOS=14.0
APP=build/MultiOutputVolume.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size icon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) icon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos$MIN_MACOS" -o "build/MultiOutputVolume-$arch" Sources/*.swift
done
lipo -create build/MultiOutputVolume-arm64 build/MultiOutputVolume-x86_64 -output "$APP/Contents/MacOS/MultiOutputVolume"
rm build/MultiOutputVolume-arm64 build/MultiOutputVolume-x86_64

cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
# Ad-hoc signatures change on every build, which leaves a stale Accessibility
# entry that looks enabled but no longer matches. Clear it so the app re-prompts.
tccutil reset Accessibility com.jackfan.MultiOutputVolume >/dev/null 2>&1 || true
echo "Built $APP"

if [[ "${1:-}" == "--zip" ]]; then
  rm -f build/MultiOutputVolume.zip
  ditto -c -k --keepParent "$APP" build/MultiOutputVolume.zip
  echo "Packaged build/MultiOutputVolume.zip"
fi
