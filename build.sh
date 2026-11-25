#!/bin/bash
# Builds "build/Clipboard History.app" (Intel by default; ARCH=arm64 ./build.sh for Apple silicon).
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Clipboard History"
EXECUTABLE="ClipboardHistory"
ARCH="${ARCH:-x86_64}"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

mkdir -p "$BUILD_DIR"

# App icon (only regenerated when missing)
if [ ! -f "$BUILD_DIR/AppIcon.icns" ]; then
  echo "▸ Drawing app icon"
  ICON_TMP="$BUILD_DIR/icon-tmp"
  rm -rf "$ICON_TMP" && mkdir -p "$ICON_TMP/AppIcon.iconset"
  swiftc -O scripts/make_icon.swift -o "$ICON_TMP/make_icon"
  "$ICON_TMP/make_icon" "$ICON_TMP/icon_1024.png"
  for s in 16 32 128 256 512; do
    sips -z "$s" "$s" "$ICON_TMP/icon_1024.png" --out "$ICON_TMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$ICON_TMP/icon_1024.png" --out "$ICON_TMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICON_TMP/AppIcon.iconset" -o "$BUILD_DIR/AppIcon.icns"
  rm -rf "$ICON_TMP"
fi

echo "▸ Compiling ($ARCH)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 \
  -target "$ARCH-apple-macos13.0" \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/$EXECUTABLE"

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BUILD_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Signing (ad-hoc)"
codesign --force --sign - "$APP"

echo "✔ Built $APP"
