#!/bin/bash
# 构建 Release 版并打包成带「安装说明」的 DMG（ad-hoc 签名，本地分发用）。
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> 生成 Xcode 工程"
xcodegen generate

echo "==> Release 构建（ad-hoc 签名）"
xcodebuild -project EasyContext.xcodeproj -scheme EasyContext -configuration Release \
  -derivedDataPath build-release \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES build

APP="build-release/Build/Products/Release/EasyContext.app"
[ -d "$APP" ] || { echo "构建产物缺失：$APP"; exit 1; }

echo "==> 封装 DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "packaging/安装说明.txt" "$STAGE/安装说明（必读）.txt"

mkdir -p dist
rm -f dist/EasyContext.dmg
hdiutil create -volname "Easy Context" -srcfolder "$STAGE" -ov -format UDZO dist/EasyContext.dmg >/dev/null
rm -rf "$STAGE"

echo "==> 完成：$(pwd)/dist/EasyContext.dmg"
ls -lh dist/EasyContext.dmg
