#!/bin/bash
# 构建指定架构的 Release App，并打包成 ad-hoc 签名、未签名的 .pkg。
#
# 用法：TARGET_ARCH=universal ./scripts/build-pkg.sh
# TARGET_ARCH 可选 universal（默认）、arm64 或 x86_64。
# 版本与构建号只从 project.yml 读取。为兼容旧调用方式，VERSION / BUILD_NUMBER
# 环境变量可以传入，但必须与 project.yml 完全一致。
set -euo pipefail

PREVIEW=false
case "${1:-}" in
  --preview) PREVIEW=true; shift ;;
  '') ;;
  *) echo 'Usage: build-pkg.sh [--preview]' >&2; exit 2 ;;
esac
[[ $# -eq 0 ]] || { echo 'Usage: build-pkg.sh [--preview]' >&2; exit 2; }

cd "$(dirname "$0")/.."

# shellcheck source=scripts/version-lib.sh
source "scripts/version-lib.sh"

IDENTIFIER="com.luyantao.easycontext"
TARGET_ARCH="${TARGET_ARCH:-universal}"

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

REPO_ROOT="$(pwd -P)"
PKG_SCRIPTS="$REPO_ROOT/packaging/pkg-scripts"
DIST_DIR="$REPO_ROOT/dist"
DIST_CLEANUP_STARTED=false
PREVIEW_DERIVED_DATA=""
PKG_ROOT=""
PKG_SCRIPTS_DIR=""
PLIST_DIR=""
TEMP_PKG=""
TEMP_SHA256=""
PUBLISH_LOCK=""
cleanup() {
  local exit_status=$?
  [[ -z "$PKG_ROOT" ]] || rm -rf "$PKG_ROOT" || true
  [[ -z "$PKG_SCRIPTS_DIR" ]] || rm -rf "$PKG_SCRIPTS_DIR" || true
  [[ -z "$PLIST_DIR" ]] || rm -rf "$PLIST_DIR" || true
  [[ -z "$TEMP_PKG" ]] || rm -f "$TEMP_PKG" || true
  [[ -z "$TEMP_SHA256" ]] || rm -f "$TEMP_SHA256" || true
  [[ -z "$PUBLISH_LOCK" ]] || rmdir "$PUBLISH_LOCK" || true
  if [[ -n "$PREVIEW_DERIVED_DATA" ]]; then
    # Each run builds in isolation; retain only its package and checksum.
    rm -rf "$PREVIEW_DERIVED_DATA" || true
  fi
  if [[ "$exit_status" -ne 0 && "$DIST_CLEANUP_STARTED" == true ]]; then
    echo "构建失败：dist 清理已经开始，旧产物可能已删除且不会自动恢复。" >&2
  fi
  ec_release_repo_lock
  return "$exit_status"
}

ec_acquire_repo_lock "$REPO_ROOT"
trap cleanup EXIT

# Read the source only after locking, so version preparation cannot race a build.
ec_read_project_version "project.yml"
SOURCE_VERSION="$EC_MARKETING_VERSION"
SOURCE_BUILD_NUMBER="$EC_BUILD_NUMBER"
if [[ -n "${VERSION+x}" && "$VERSION" != "$SOURCE_VERSION" ]]; then
  echo "VERSION 环境变量（${VERSION}）与 project.yml（${SOURCE_VERSION}）不一致" >&2
  exit 1
fi
if [[ -n "${BUILD_NUMBER+x}" && "$BUILD_NUMBER" != "$SOURCE_BUILD_NUMBER" ]]; then
  echo "BUILD_NUMBER 环境变量（${BUILD_NUMBER}）与 project.yml（${SOURCE_BUILD_NUMBER}）不一致" >&2
  exit 1
fi
VERSION="$SOURCE_VERSION"
BUILD_NUMBER="$SOURCE_BUILD_NUMBER"

if [[ -L "$DIST_DIR" ]]; then
  echo "拒绝清理符号链接形式的 dist：$DIST_DIR" >&2
  exit 1
fi
if [[ -e "$DIST_DIR" && ! -d "$DIST_DIR" ]]; then
  echo "dist 路径存在但不是目录，拒绝清理：$DIST_DIR" >&2
  exit 1
fi
mkdir -p "$DIST_DIR"
[[ -d "$DIST_DIR" && ! -L "$DIST_DIR" ]] || {
  echo "无法建立安全的 dist 目录：$DIST_DIR" >&2
  exit 1
}
DIST_ID="$(ec_directory_identity "$DIST_DIR")"
assert_dist_unchanged() {
  [[ -d "$DIST_DIR" && ! -L "$DIST_DIR" ]] \
    && [[ "$(ec_directory_identity "$DIST_DIR")" == "$DIST_ID" ]] \
    || { echo "dist 已被替换，拒绝继续构建或发布：$DIST_DIR" >&2; return 1; }
}

echo "==> 清空旧构建产物：$DIST_DIR"
# Bind the directory before deleting relative children. A concurrent rename or
# symlink replacement of repo/dist cannot redirect rm into a different tree.
cd -P "$DIST_DIR"
[[ "$(pwd -P)" == "$DIST_DIR" && "$(ec_directory_identity .)" == "$DIST_ID" ]] || {
  echo "dist 在进入清理目录前已被替换，拒绝清理" >&2
  exit 1
}
DIST_CLEANUP_STARTED=true
find . -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
assert_dist_unchanged
if ! DIST_REMAINDER="$(ls -A .)"; then
  echo "无法确认 dist 清理结果，拒绝开始构建：$DIST_DIR" >&2
  exit 1
fi
if [[ -n "$DIST_REMAINDER" ]]; then
  echo "dist 未能完全清空，拒绝开始构建：$DIST_DIR" >&2
  exit 1
fi

OUTPUT_DIR=.
OUTPUT_NAME="EasyContext-${VERSION}-macOS-${TARGET_ARCH}.pkg"
if [[ "$PREVIEW" == true ]]; then
  PREVIEW_PARENT="preview/${VERSION}-build${BUILD_NUMBER}/${TARGET_ARCH}"
  mkdir -p "$PREVIEW_PARENT"
  OUTPUT_DIR="$(mktemp -d "$PREVIEW_PARENT/run.XXXXXX")"
  OUTPUT_NAME="EasyContext-${VERSION}-build${BUILD_NUMBER}-preview-macOS-${TARGET_ARCH}.pkg"
  cd -P "$OUTPUT_DIR"
  DERIVED_DATA_PATH=DerivedData
  PREVIEW_DERIVED_DATA=./DerivedData
else
  DERIVED_DATA_PATH="$REPO_ROOT/$DERIVED_DATA_PATH"
fi
OUTPUT_DIR=.
OUTPUT_PKG="$OUTPUT_NAME"
OUTPUT_SHA256="$OUTPUT_PKG.sha256"
assert_dist_unchanged

APP="$DERIVED_DATA_PATH/Build/Products/Release/EasyContext.app"
APPEX="$APP/Contents/PlugIns/EasyContextFinder.appex"

echo "==> 版本：${VERSION}（构建号：${BUILD_NUMBER}）"
echo "==> 生成 Xcode 工程"
(cd "$REPO_ROOT" && xcodegen generate)
assert_dist_unchanged

echo "==> Release ${TARGET_ARCH} 构建（ad-hoc 签名）"
xcodebuild -project "$REPO_ROOT/EasyContext.xcodeproj" -scheme EasyContext -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  ARCHS="$BUILD_ARCHS" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  ENABLE_DEBUG_DYLIB=NO build
assert_dist_unchanged

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
APP_EXECUTABLE_SHA256="$(shasum -a 256 "$APP/Contents/MacOS/EasyContext" | awk '{print $1}')"
APPEX_EXECUTABLE_SHA256="$(shasum -a 256 "$APPEX/Contents/MacOS/EasyContextFinder" | awk '{print $1}')"
render_installer_script() {
  local source_script="$1"
  local destination_script="$2"
  sed \
    -e "s/@EXPECTED_VERSION@/$VERSION/g" \
    -e "s/@EXPECTED_BUILD_NUMBER@/$BUILD_NUMBER/g" \
    -e "s/@APP_EXECUTABLE_SHA256@/$APP_EXECUTABLE_SHA256/g" \
    -e "s/@APPEX_EXECUTABLE_SHA256@/$APPEX_EXECUTABLE_SHA256/g" \
    "$source_script" > "$destination_script"
  chmod 0755 "$destination_script"
}
render_installer_script "$PKG_SCRIPTS/preinstall" "$PKG_SCRIPTS_DIR/preinstall"
render_installer_script "$PKG_SCRIPTS/postinstall" "$PKG_SCRIPTS_DIR/postinstall"

# 禁用 Bundle 重定位，始终安装至 /Applications/EasyContext.app。
pkgbuild --analyze --root "$PKG_ROOT" "$COMPONENT_PLIST" >/dev/null
index=0
while /usr/libexec/PlistBuddy -c "Print :$index:BundleIsRelocatable" "$COMPONENT_PLIST" >/dev/null 2>&1; do
  /usr/libexec/PlistBuddy -c "Set :$index:BundleIsRelocatable false" "$COMPONENT_PLIST"
  index=$((index + 1))
done

mkdir -p "$OUTPUT_DIR"
assert_dist_unchanged
# Same filesystem as final outputs, allowing atomic rename without requiring
# hard-link support (for example on external exFAT volumes).
# BSD mktemp only replaces a trailing run of X characters.
TEMP_PKG="$(mktemp "$OUTPUT_DIR/.EasyContext-${VERSION}.pkg.XXXXXX")"
TEMP_SHA256="$(mktemp "$OUTPUT_DIR/.EasyContext-${VERSION}.sha256.XXXXXX")"

echo "==> 打包 pkg（未签名）"
pkgbuild --root "$PKG_ROOT" \
  --component-plist "$COMPONENT_PLIST" \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  --install-location /Applications \
  --scripts "$PKG_SCRIPTS_DIR" \
  "$TEMP_PKG"
PKG_SHA256="$(shasum -a 256 "$TEMP_PKG" | awk '{print $1}')"
printf '%s  %s\n' "$PKG_SHA256" "$OUTPUT_NAME" > "$TEMP_SHA256"
if ! mkdir "$OUTPUT_PKG.publish-lock"; then
  echo "安装包发布锁已存在，拒绝并发覆盖：$OUTPUT_PKG" >&2
  exit 1
fi
PUBLISH_LOCK="$OUTPUT_PKG.publish-lock"
if [[ -e "$OUTPUT_PKG" || -L "$OUTPUT_PKG" || -e "$OUTPUT_SHA256" || -L "$OUTPUT_SHA256" ]]; then
  echo "构建期间出现同名产物，拒绝覆盖：$OUTPUT_PKG" >&2
  exit 1
fi
publish_without_overwrite() {
  local source="$1" destination="$2"
  mv -n "$source" "$destination"
  # BSD mv -n returns success even when it declined to replace an existing file.
  [[ ! -e "$source" && -f "$destination" && ! -L "$destination" ]] || {
    echo "未能将构建产物安全发布为普通文件（目标可能在构建期间出现）：$destination" >&2
    return 1
  }
}
publish_without_overwrite "$TEMP_PKG" "$OUTPUT_PKG"
TEMP_PKG=""
publish_without_overwrite "$TEMP_SHA256" "$OUTPUT_SHA256"
TEMP_SHA256=""
assert_dist_unchanged

echo "==> 完成：$(pwd)/$OUTPUT_PKG"
ls -lh "$OUTPUT_PKG"
