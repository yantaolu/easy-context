#!/bin/bash
# 构建指定架构的 Release App，并打包成 ad-hoc 签名、未签名的 .pkg。
#
# 用法：VERSION=1.2.3 BUILD_NUMBER=123 TARGET_ARCH=universal ./scripts/build-pkg.sh
# TARGET_ARCH 可选 universal（默认）、arm64 或 x86_64。
# 本地 VERSION 可为 1、1.2 或 1.2.3；GitHub tag 构建必须是三段版本号。
set -euo pipefail

cd "$(dirname "$0")/.."

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
TARGET_ARCH="${TARGET_ARCH:-universal}"

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

case "$TARGET_ARCH" in
  universal)
    BUILD_ARCHS="arm64 x86_64"
    EXPECTED_ARCHITECTURES=(arm64 x86_64)
    DERIVED_DATA_PATH="build-release"
    ;;
  arm64|x86_64)
    BUILD_ARCHS="$TARGET_ARCH"
    EXPECTED_ARCHITECTURES=("$TARGET_ARCH")
    # 单架构构建使用独立 DerivedData，避免从此前的 universal 或另一架构构建复用产物。
    DERIVED_DATA_PATH="build-release/$TARGET_ARCH"
    ;;
  *)
    echo "TARGET_ARCH 必须为 universal、arm64 或 x86_64，实际为：$TARGET_ARCH" >&2
    exit 1
    ;;
esac

APP="$DERIVED_DATA_PATH/Build/Products/Release/EasyContext.app"
APPEX="$APP/Contents/PlugIns/EasyContextFinder.appex"

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

echo "==> Release ${TARGET_ARCH} 构建（ad-hoc 签名）"
xcodebuild -project EasyContext.xcodeproj -scheme EasyContext -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  ARCHS="$BUILD_ARCHS" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
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

assert_target_architectures() {
  local binary="$1"
  local architectures
  local actual_architectures
  local expected_architecture
  architectures="$(lipo -archs "$binary")"
  read -r -a actual_architectures <<< "$architectures"

  [[ "${#actual_architectures[@]}" -eq "${#EXPECTED_ARCHITECTURES[@]}" ]] || {
    echo "$binary 架构应恰好为 ${EXPECTED_ARCHITECTURES[*]}，实际为：$architectures" >&2
    exit 1
  }
  for expected_architecture in "${EXPECTED_ARCHITECTURES[@]}"; do
    [[ " $architectures " == *" $expected_architecture "* ]] || {
      echo "$binary 缺少 $expected_architecture 架构（实际：$architectures）" >&2
      exit 1
    }
  done
}

assert_get_task_allow_not_true() {
  local bundle="$1"
  local entitlements
  local value

  entitlements="$(mktemp)"
  if ! codesign -d --entitlements :- "$bundle" >"$entitlements" 2>/dev/null; then
    rm -f "$entitlements"
    echo "无法读取 $bundle 的签名 entitlement" >&2
    exit 1
  fi

  # 未设置 entitlement 时 codesign 可以输出空内容；这等价于缺少该 key，属于正常情况。
  if [[ ! -s "$entitlements" ]]; then
    rm -f "$entitlements"
    return
  fi
  if ! plutil -lint "$entitlements" >/dev/null; then
    rm -f "$entitlements"
    echo "无法解析 $bundle 的签名 entitlement，拒绝将其视为安全产物" >&2
    exit 1
  fi

  if value="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$entitlements" 2>/dev/null)"; then
    rm -f "$entitlements"
    [[ "$value" == "false" ]] || {
      echo "$bundle 的 com.apple.security.get-task-allow 必须为 false 或缺失，实际为：$value" >&2
      exit 1
    }
    return
  fi

  rm -f "$entitlements"
  # plutil 已验证整个 plist；无法提取该 key 表示它不存在，属于允许的状态。
}

echo "==> 验证版本、架构与签名结构"
assert_plist_value "$APP/Contents/Info.plist" CFBundleShortVersionString "$VERSION"
assert_plist_value "$APP/Contents/Info.plist" CFBundleVersion "$BUILD_NUMBER"
assert_plist_value "$APPEX/Contents/Info.plist" CFBundleShortVersionString "$VERSION"
assert_plist_value "$APPEX/Contents/Info.plist" CFBundleVersion "$BUILD_NUMBER"
assert_target_architectures "$APP/Contents/MacOS/EasyContext"
assert_target_architectures "$APPEX/Contents/MacOS/EasyContextFinder"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign --verify --deep --strict --verbose=2 "$APPEX"
assert_get_task_allow_not_true "$APP"
assert_get_task_allow_not_true "$APPEX"

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

OUTPUT_PKG="dist/EasyContext-${VERSION}-macOS-${TARGET_ARCH}.pkg"
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
