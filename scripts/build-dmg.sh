#!/bin/bash
# 构建 Release 版并打包成「带窗口样式 + 安装说明」的 DMG（ad-hoc 签名，本地分发用）。
# 用 dmgbuild 直接写 .DS_Store，不依赖 Finder 自动化。
#
# 背景图：packaging/dmg-bg.png（要改版式时运行 packaging/make-dmg-bg.swift 重新生成，
#         图标位置在 packaging/dmg-settings.py 里同步调整）。
set -euo pipefail
cd "$(dirname "$0")/.."

VOL="Easy Context"
APP="build-release/Build/Products/Release/EasyContext.app"

echo "==> 生成 Xcode 工程"
xcodegen generate

echo "==> Release 构建（ad-hoc 签名）"
xcodebuild -project EasyContext.xcodeproj -scheme EasyContext -configuration Release \
  -derivedDataPath build-release \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES build
[ -d "$APP" ] || { echo "构建产物缺失：$APP"; exit 1; }

echo "==> 准备 dmgbuild（独立 venv）"
VENV=".venv-dmg"
if [ ! -x "$VENV/bin/dmgbuild" ]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet --upgrade pip dmgbuild
fi

echo "==> 打包 DMG"
TMP="$(mktemp -d)"
cp "packaging/安装说明.txt" "$TMP/安装说明（必读）.txt"  # DMG 内显示名
hdiutil detach "/Volumes/$VOL" >/dev/null 2>&1 || true
mkdir -p dist; rm -f dist/EasyContext.dmg
"$VENV/bin/dmgbuild" -s packaging/dmg-settings.py \
  -D app="$APP" \
  -D notes="$TMP/安装说明（必读）.txt" \
  -D volicon="$APP/Contents/Resources/AppIcon.icns" \
  "$VOL" dist/EasyContext.dmg
rm -rf "$TMP"

echo "==> 完成：$(pwd)/dist/EasyContext.dmg"
ls -lh dist/EasyContext.dmg
