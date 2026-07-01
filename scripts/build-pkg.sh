#!/bin/bash
# 构建 Release 版并打包成【不签名】的 .pkg 安装包（本地/内部分发用）。
#
# 亮点：安装前自动关闭正在运行的 EasyContext 及其 FinderSync 扩展，解决
#      “项目 EasyContext.app 正在使用中、无法覆盖”的问题；安装后以登录
#      用户身份重启 App（脚本见 packaging/pkg-scripts/）。
#
# 无 Apple 账号版本：pkg 不签名。首次安装会被 Gatekeeper 拦，用户需：
#   · 右键点 pkg → 打开 → 再点“打开”；或
#   · 终端执行：sudo installer -pkg dist/EasyContext.pkg -target /
# 想去掉该警告需付费 Developer ID 证书 + 公证（见 README「已知限制 · 分发」）。
#
# 用法：scripts/build-pkg.sh            # 版本号自动从 app Info.plist 读取
#      VERSION=1.2 scripts/build-pkg.sh # 手动指定版本号
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build-release/Build/Products/Release/EasyContext.app"
IDENTIFIER="com.luyantao.easycontext"
PKG_SCRIPTS="packaging/pkg-scripts"

echo "==> 生成 Xcode 工程"
xcodegen generate

echo "==> Release 构建（ad-hoc 签名）"
xcodebuild -project EasyContext.xcodeproj -scheme EasyContext -configuration Release \
  -derivedDataPath build-release \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES build
[ -d "$APP" ] || { echo "构建产物缺失：$APP"; exit 1; }

# 版本号：优先取环境变量，其次读 app 内 Info.plist，最后兜底 1.0
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || true)}"
[ -n "$VERSION" ] || VERSION="1.0"
echo "==> 版本：$VERSION"

echo "==> 组装安装内容"
ROOT="$(mktemp -d)"
SCRIPTS="$(mktemp -d)"
PLISTDIR="$(mktemp -d)"; PLIST="$PLISTDIR/component.plist"
cp -R "$APP" "$ROOT/"                                   # 装到 /Applications/EasyContext.app
install -m 0755 "$PKG_SCRIPTS/preinstall"  "$SCRIPTS/preinstall"
install -m 0755 "$PKG_SCRIPTS/postinstall" "$SCRIPTS/postinstall"

# 关闭「Bundle 重定位」：pkgbuild 默认给 app 生成 <relocate>，安装器一旦在系统别处
# （如开发目录 build-release）发现同 bundle id 的旧副本，就会把新版装到那个旧位置、
# 而非 /Applications——表现为“装完 /Applications 里什么都没有”。故强制 false。
pkgbuild --analyze --root "$ROOT" "$PLIST" >/dev/null
i=0
while /usr/libexec/PlistBuddy -c "Print :$i:BundleIsRelocatable" "$PLIST" >/dev/null 2>&1; do
  /usr/libexec/PlistBuddy -c "Set :$i:BundleIsRelocatable false" "$PLIST"
  i=$((i+1))
done

echo "==> 打包 pkg（不签名）"
mkdir -p dist; rm -f dist/EasyContext.pkg
pkgbuild --root "$ROOT" \
  --component-plist "$PLIST" \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  --install-location /Applications \
  --scripts "$SCRIPTS" \
  dist/EasyContext.pkg

rm -rf "$ROOT" "$SCRIPTS" "$PLISTDIR"
echo "==> 完成：$(pwd)/dist/EasyContext.pkg"
ls -lh dist/EasyContext.pkg
