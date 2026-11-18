#!/bin/bash
# 构建指定架构的 Release App，并打包成未签名的 .pkg。
#
# 用法：TARGET_ARCH=universal ./scripts/build-pkg.sh
# TARGET_ARCH 可选 universal（默认）、arm64 或 x86_64。
#
# App 签名：
# - 设置 EC_SIGN_IDENTITY（证书 SHA-1 或名称）时，用该自签名证书重新签名宿主与扩展，
#   使 designated requirement 跨版本稳定（macOS 隐私授权不再随升级失效）。
#   EC_SIGN_KEYCHAIN 可指定只从某个钥匙串查找身份（CI 临时钥匙串）。
#   packaging/signing-certificate.sha1 存在时，签名证书必须与其一致。
# - 未设置时沿用 ad-hoc 签名（每次构建身份都会变）；EC_REQUIRE_SIGNING=1 时拒绝 ad-hoc。
# - 证书由 scripts/create-signing-cert.sh 一次性生成。
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
EXTENSION_IDENTIFIER="$IDENTIFIER.finder"
SIGN_IDENTITY="${EC_SIGN_IDENTITY:-}"
SIGN_KEYCHAIN="${EC_SIGN_KEYCHAIN:-}"
REQUIRE_SIGNING="${EC_REQUIRE_SIGNING:-0}"
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
SIGNING_PIN_FILE="$REPO_ROOT/packaging/signing-certificate.sha1"
EXPECTED_CERT_SHA1=""
if [[ -f "$SIGNING_PIN_FILE" ]]; then
  EXPECTED_CERT_SHA1="$(tr -d '[:space:]' < "$SIGNING_PIN_FILE" | tr 'A-F' 'a-f')"
  [[ "$EXPECTED_CERT_SHA1" =~ ^[0-9a-f]{40}$ ]] || {
    echo "签名证书指纹文件格式无效（应为 40 位十六进制 SHA-1）：$SIGNING_PIN_FILE" >&2
    exit 1
  }
fi
if [[ "$REQUIRE_SIGNING" == 1 ]]; then
  [[ -n "$SIGN_IDENTITY" ]] || {
    echo "EC_REQUIRE_SIGNING=1 但未设置 EC_SIGN_IDENTITY，拒绝构建 ad-hoc 发布包" >&2
    exit 1
  }
  [[ -n "$EXPECTED_CERT_SHA1" ]] || {
    echo "EC_REQUIRE_SIGNING=1 需要 $SIGNING_PIN_FILE 固定签名证书指纹" >&2
    exit 1
  }
fi
if [[ -n "$SIGN_KEYCHAIN" && ! -f "$SIGN_KEYCHAIN" ]]; then
  echo "EC_SIGN_KEYCHAIN 指向的钥匙串不存在：$SIGN_KEYCHAIN" >&2
  exit 1
fi
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

echo "==> Release ${TARGET_ARCH} 构建（先 ad-hoc 签名，必要时随后用固定证书重签）"
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

sign_code() {
  local target="$1"
  shift
  local args=(--force --sign "$SIGN_IDENTITY" --timestamp=none)
  [[ -z "$SIGN_KEYCHAIN" ]] || args+=(--keychain "$SIGN_KEYCHAIN")
  codesign "${args[@]}" "$@" "$target"
}

# 签名身份必须是「identifier + 证书指纹」而非 cdhash，否则隐私授权仍会随构建失效。
assert_certificate_requirement() {
  local bundle="$1"
  local identifier="$2"
  local requirement
  local leaf
  requirement="$(codesign -d -r- "$bundle" 2>&1)"
  leaf="$(sed -n 's/.*certificate leaf = H"\([0-9A-Fa-f]\{40\}\)".*/\1/p' <<< "$requirement" \
    | head -n 1 | tr 'A-F' 'a-f')"
  [[ "$requirement" == *"identifier \"$identifier\""* && -n "$leaf" ]] || {
    echo "$bundle 的签名身份不是预期的「identifier + 证书指纹」：" >&2
    echo "$requirement" >&2
    exit 1
  }
  if [[ -n "$EXPECTED_CERT_SHA1" && "$leaf" != "$EXPECTED_CERT_SHA1" ]]; then
    echo "$bundle 使用的签名证书（${leaf}）与 packaging/signing-certificate.sha1（${EXPECTED_CERT_SHA1}）不一致。" >&2
    echo "换证书会让所有用户的隐私授权失效；如确需更换，请同时更新指纹文件。" >&2
    exit 1
  fi
}

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "==> 使用固定证书重新签名（由内向外）"
  if [[ -d "$APP/Contents/Frameworks" ]]; then
    while IFS= read -r -d '' nested; do
      sign_code "$nested"
    done < <(find "$APP/Contents/Frameworks" -mindepth 1 -maxdepth 1 \
      \( -name '*.framework' -o -name '*.dylib' \) -print0)
  fi
  sign_code "$APPEX" --entitlements "$REPO_ROOT/EasyContextFinder/EasyContextFinder.entitlements"
  sign_code "$APP"
  assert_certificate_requirement "$APPEX" "$EXTENSION_IDENTIFIER"
  assert_certificate_requirement "$APP" "$IDENTIFIER"
else
  echo "⚠️  未设置 EC_SIGN_IDENTITY：沿用 ad-hoc 签名。此包每次构建身份都会变，" >&2
  echo "    安装后 macOS 隐私授权（外置磁盘、完全磁盘访问、自动化）可能需要重新授予。" >&2
fi

assert_plist_value() {
  local plist="$1"
  local key="$2"
  local expected="$3"
  local actual
  actual="$(/usr/libexec/PlistBuddy -c "Print :$key" "$plist")"
  [[ "$actual" == "$expected" ]] || {
    echo "$plist 的 $key 应为 ${expected}，实际为 $actual" >&2
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
      echo "$binary 缺少 $expected_architecture 架构（实际：${architectures}）" >&2
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
# 共享判定函数（被 preinstall / postinstall source），无占位符，原样复制。
install -m 0644 "$PKG_SCRIPTS/easycontext-installer-lib.sh" "$PKG_SCRIPTS_DIR/easycontext-installer-lib.sh"

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

# xcodebuild 会把构建目录里的 App 登记到 LaunchServices。它与已安装版同 bundle id，
# 会争抢 easycontext:// 请求和隐私授权，故打包后注销（best-effort，不影响产物）。
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true
fi

echo "==> 完成：$(pwd)/$OUTPUT_PKG"
ls -lh "$OUTPUT_PKG"
