#!/usr/bin/env bash
#
# 在 macOS 上构建并打包 ipa。需要 Xcode 15+ 与 xcodegen。
#
#   APP_GROUP=group.com.yourteam.mt2ios.WQ \
#   TEAM_ID=ABCDE12345 \
#   BUNDLE_ID=com.yourteam.mt2ios \
#   ./scripts/build-ipa.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."

command -v xcodegen >/dev/null 2>&1 || { echo "缺少 xcodegen：brew install xcodegen"; exit 1; }
command -v xcodebuild >/dev/null 2>&1 || { echo "缺少 xcodebuild：装 Xcode"; exit 1; }

BUNDLE_ID="${BUNDLE_ID:-com.example.mt2ios}"
APP_GROUP="${APP_GROUP:-group.com.example.mt2ios.WQ}"
TEAM_ID="${TEAM_ID:-}"

echo "==> Bundle ID : $BUNDLE_ID"
echo "==> App Group : $APP_GROUP"
echo "==> Team ID   : ${TEAM_ID:-<未指定，将使用 Xcode 里已登录的账号>}"

xcodegen generate

SIGN_ARGS=(CODE_SIGN_STYLE=Automatic)
if [[ -n "$TEAM_ID" ]]; then
  SIGN_ARGS+=("DEVELOPMENT_TEAM=$TEAM_ID")
fi

xcodebuild \
  -project mt2ios.xcodeproj \
  -scheme mt2ios \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath build \
  -allowProvisioningUpdates \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  WQ_APP_GROUP="$APP_GROUP" \
  "${SIGN_ARGS[@]}" \
  build

APP="build/Build/Products/Release-iphoneos/MT2iOS.app"
[[ -d "$APP" ]] || { echo "构建产物不存在：$APP"; exit 1; }

rm -rf build/Payload build/MT2iOS.ipa
mkdir -p build/Payload
cp -R "$APP" build/Payload/
(cd build && zip -qry MT2iOS.ipa Payload)

echo
echo "==> ipa: $(pwd)/build/MT2iOS.ipa"
echo "==> 用 SideStore / AltStore / Sideloadly / LiveContainer 安装，别用企业证书"
