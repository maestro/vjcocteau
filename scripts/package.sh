#!/bin/bash
# VJ Cocteau.app を dist/ に作ります(xcodegen と Xcode が必要です)。
# 使い方: scripts/package.sh [--universal]
#   環境変数 SIGN_ID に Developer ID Application の証明書名を渡すと、その証明書で署名します。
#   未指定なら ad-hoc 署名です(自分の Mac で動かす用)。
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="VJ Cocteau"
VERSION="$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)"
ARCHS="arm64"
[[ "${1:-}" == "--universal" ]] && ARCHS="arm64 x86_64"

xcodegen generate --quiet
ARGS=(-project VJCocteau.xcodeproj -scheme VJCocteau -configuration Release
      -derivedDataPath build/DD ARCHS="$ARCHS" ONLY_ACTIVE_ARCH=NO)
if [[ -n "${SIGN_ID:-}" ]]; then
  ARGS+=(CODE_SIGN_IDENTITY="$SIGN_ID" OTHER_CODE_SIGN_FLAGS="--timestamp")
fi
xcodebuild "${ARGS[@]}" build | tail -3

rm -rf dist && mkdir -p dist
cp -R "build/DD/Build/Products/Release/$NAME.app" dist/
codesign --verify --strict "dist/$NAME.app"
ditto -c -k --keepParent "dist/$NAME.app" "dist/VJ-Cocteau-$VERSION.zip"
echo "作成しました: dist/$NAME.app / dist/VJ-Cocteau-$VERSION.zip"
