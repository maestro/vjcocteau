#!/bin/bash
# VJ Cocteau.app を dist/ に作ります。
# 使い方: scripts/package.sh [--universal]
#   環境変数 SIGN_ID に Developer ID Application の証明書名を渡すと、その証明書で署名します。
#   未指定なら ad-hoc 署名です(自分の Mac で動かす用)。
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="VJ Cocteau"
VERSION="${VERSION:-0.1.0}"
ARCHS=()
[[ "${1:-}" == "--universal" ]] && ARCHS=(--arch arm64 --arch x86_64)

swift build -c release ${ARCHS[@]+"${ARCHS[@]}"}
BIN_DIR="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)"

APP="dist/$NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/VJCocteau" "$APP/Contents/MacOS/VJCocteau"
# Effect と Shader を含むリソースは、Contents/Resources に置きます(Bundle.module がここを探します)。
cp -R "$BIN_DIR/VJCocteau_VJCocteau.bundle" "$APP/Contents/Resources/"
# アプリアイコン(Resources/AppIcon.icns。作り方は scripts/make-icon.swift を参照)。
cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>VJCocteau</string>
    <key>CFBundleIdentifier</key><string>com.vjcocteau.app</string>
    <key>CFBundleName</key><string>$NAME</string>
    <key>CFBundleDisplayName</key><string>$NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>会場の音から BPM を検出するために、音声入力を使います。 / Audio input is used to detect the BPM from the venue sound.</string>
</dict>
</plist>
PLIST

if [[ -n "${SIGN_ID:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" \
    --entitlements scripts/VJCocteau.entitlements "$APP"
else
  codesign --force --sign - --entitlements scripts/VJCocteau.entitlements "$APP"
fi
codesign --verify --strict "$APP"

ditto -c -k --keepParent "$APP" "dist/VJ-Cocteau-$VERSION.zip"
echo "作成しました: $APP / dist/VJ-Cocteau-$VERSION.zip"
