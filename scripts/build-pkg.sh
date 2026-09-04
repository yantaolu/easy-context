#!/bin/bash
# 构建 universal Release App，并打包成 ad-hoc 签名、未签名的 .pkg。
#
# 用法：VERSION=1.2.3 BUILD_NUMBER=123 ./scripts/build-pkg.sh
# 本地 VERSION 可为 1、1.2 或 1.2.3；GitHub tag 构建必须是三段版本号。
set -euo pipefail

cd "$(dirname "$0")/.."

APP="build-release/Build/Products/Release/EasyContext.app"
APPEX="$APP/Contents/PlugIns/EasyContextFinder.appex"
IDENTIFIER="com.luyantao.easycontext"
PKG_SCRIPTS="packaging/pkg-scripts"

default_setting() {
  local key="$1"
  sed -nE "s/^[[:space:]]*${key}:[[:space:]]*\"?([^\"[:space:]#]+)\"?.*/\1/p" project.yml | head -n 1
}

DEFAULT_VERSION="$(default_setting MARKETING_VERSION)"
DEFAULT_BUILD_NUMBER="$(default_setting CURRENT_PROJECT_VERSION)"
VERSION="${VERSION:-$DEFAULT_VERSION}"
BUILD_NUMBER="${BUILD_NUMBER:-$DEFAULT_BUILD_NUMBER}"

local_version_pattern='^(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*)){0,2}$'
tag_version_pattern='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'

if ! [[ "$VERSION" =~ $local_version_pattern ]]; then
  echo "VERSION 必须为 1、1.2 或 1.2.3 形式，实际为：$VERSION" >&2
  exit 1
fi
if [[ "${GITHUB_ACTIONS:-}" == "true" && "${GITHUB_REF_TYPE:-}" == "tag" ]] \
  && ! [[ "$VERSION" =~ $tag_version_pattern ]]; then
  echo "GitHub tag 构建的 VERSION 必须为三段版本号，实际为：$VERSION" >&2
  exit 1
fi
if ! [[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "BUILD_NUMBER 必须为正整数，实际为：$BUILD_NUMBER" >&2
  exit 1
fi

PKG_ROOT=""
PKG_SCRIPTS_DIR=""
PLIST_DIR=""
TEMP_PKG=""
cleanup() {
  local exit_status=$?
  [[ -z "$PKG_ROOT" ]] || rm -rf "$PKG_ROOT" || true
  [[ -z "$PKG_SCRIPTS_DIR" ]] || rm -rf "$PKG_SCRIPTS_DIR" || true
  [[ -z "$PLIST_DIR" ]] || rm -rf "$PLIST_DIR" || true
  [[ -z "$TEMP_PKG" ]] || rm -f "$TEMP_PKG" || true
  return "$exit_status"
}
trap cleanup EXIT

echo "==> 版本：${VERSION}（构建号：${BUILD_NUMBER}）"
echo "==> 生成 Xcode 工程"
xcodegen generate

echo "==> Release universal 构建（ad-hoc 签名）"
xcodebuild -project EasyContext.xcodeproj -scheme EasyContext -configuration Release \
  -derivedDataPath build-release \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES \
  ENABLE_DEBUG_DYLIB=NO build

[[ -d "$APP" ]] || { echo "构建产物缺失：$APP" >&2; exit 1; }
[[ -d "$APPEX" ]] || { echo "Finder 扩展产物缺失：$APPEX" >&2; exit 1; }

assert_plist_value() {
  local plist="$1"
  local key="$2"
  local expected="$3"
  local actual
  actual="$(/usr/libexec/PlistBuddy -c "Print :$key" "$plist")"
  [[ "$actual" == "$expected" ]] || {
    echo "$plist 的 $key 应为 $expected，实际为 $actual" >&2
    exit 1
  }
}

assert_universal_binary() {
  local binary="$1"
  local architectures
  architectures="$(lipo -archs "$binary")"
  for architecture in arm64 x86_64; do
    [[ " $architectures " == *" $architecture "* ]] || {
      echo "$binary 缺少 $architecture 架构（实际：$architectures）" >&2
      exit 1
    }
  done
}

echo "==> 验证版本、架构与签名结构"
assert_plist_value "$APP/Contents/Info.plist" CFBundleShortVersionString "$VERSION"
assert_plist_value "$APP/Contents/Info.plist" CFBundleVersion "$BUILD_NUMBER"
assert_plist_value "$APPEX/Contents/Info.plist" CFBundleShortVersionString "$VERSION"
assert_plist_value "$APPEX/Contents/Info.plist" CFBundleVersion "$BUILD_NUMBER"
assert_universal_binary "$APP/Contents/MacOS/EasyContext"
assert_universal_binary "$APPEX/Contents/MacOS/EasyContextFinder"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign --verify --deep --strict --verbose=2 "$APPEX"

echo "==> 组装安装内容"
PKG_ROOT="$(mktemp -d)"
PKG_SCRIPTS_DIR="$(mktemp -d)"
PLIST_DIR="$(mktemp -d)"
COMPONENT_PLIST="$PLIST_DIR/component.plist"
cp -R "$APP" "$PKG_ROOT/"
install -m 0755 "$PKG_SCRIPTS/preinstall" "$PKG_SCRIPTS_DIR/preinstall"
install -m 0755 "$PKG_SCRIPTS/postinstall" "$PKG_SCRIPTS_DIR/postinstall"

# 禁用 Bundle 重定位，始终安装至 /Applications/EasyContext.app。
pkgbuild --analyze --root "$PKG_ROOT" "$COMPONENT_PLIST" >/dev/null
index=0
while /usr/libexec/PlistBuddy -c "Print :$index:BundleIsRelocatable" "$COMPONENT_PLIST" >/dev/null 2>&1; do
  /usr/libexec/PlistBuddy -c "Set :$index:BundleIsRelocatable false" "$COMPONENT_PLIST"
  index=$((index + 1))
done

OUTPUT_PKG="dist/EasyContext-${VERSION}-macOS-universal.pkg"
TEMP_PKG="$(mktemp "${TMPDIR:-/tmp}/EasyContext-${VERSION}.XXXXXX.pkg")"
mkdir -p dist

echo "==> 打包 pkg（未签名）"
pkgbuild --root "$PKG_ROOT" \
  --component-plist "$COMPONENT_PLIST" \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  --install-location /Applications \
  --scripts "$PKG_SCRIPTS_DIR" \
  "$TEMP_PKG"
mv -f "$TEMP_PKG" "$OUTPUT_PKG"
TEMP_PKG=""

echo "==> 完成：$(pwd)/$OUTPUT_PKG"
ls -lh "$OUTPUT_PKG"
