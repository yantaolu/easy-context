#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/version-lib.sh
source "$SCRIPT_DIR/version-lib.sh"

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/easycontext-version-tests.XXXXXX")"
cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

TEST_COUNT=0

pass() {
  TEST_COUNT=$((TEST_COUNT + 1))
  printf 'ok %d - %s\n' "$TEST_COUNT" "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  [[ "$actual" == "$expected" ]] || fail "$label (expected '$expected', got '$actual')"
  pass "$label"
}

assert_fails() {
  local label="$1"
  shift
  if "$@" >"$TEST_ROOT/last-command.log" 2>&1; then
    fail "$label (command unexpectedly succeeded)"
  fi
  pass "$label"
}

write_project() {
  local path="$1"
  local version="$2"
  local build="$3"
  cat > "$path" <<EOF
name: VersionFixture
settings:
  base:
    MARKETING_VERSION: $version
    CURRENT_PROJECT_VERSION: $build
EOF
}

new_repo() {
  local name="$1"
  local version="$2"
  local build="$3"
  FIXTURE_REPO="$TEST_ROOT/$name"
  mkdir -p "$FIXTURE_REPO"
  write_project "$FIXTURE_REPO/project.yml" "$version" "$build"
  git -C "$FIXTURE_REPO" init -q
  git -C "$FIXTURE_REPO" -c user.name=VersionTest -c user.email=version@test.invalid \
    -c commit.gpgsign=false -c core.hooksPath=/dev/null \
    commit --allow-empty -q -m initial
}

add_tag() {
  git -C "$FIXTURE_REPO" -c tag.gpgSign=false -c core.hooksPath=/dev/null tag "$1"
}

PROJECT="$TEST_ROOT/read-project.yml"
write_project "$PROJECT" 1.0.10 42
assert_equal "1.0.10" "$($SCRIPT_DIR/version.sh --project "$PROJECT" --version)" \
  "reads the strict marketing version"
assert_equal "42" "$($SCRIPT_DIR/version.sh --project "$PROJECT" --build)" \
  "reads the positive build number"
cat > "$PROJECT" <<'EOF'
settings:
  base:
    MARKETING_VERSION: "2.3.4" # release version
    CURRENT_PROJECT_VERSION: '57' # monotonically increasing build
EOF
assert_equal "2.3.4" "$($SCRIPT_DIR/version.sh --project "$PROJECT" --version)" \
  "reads quoted values followed by comments"
assert_equal "57" "$($SCRIPT_DIR/version.sh --project "$PROJECT" --build)" \
  "reads a quoted build followed by a comment"
assert_equal "1" "$(ec_compare_versions 1.0.10 1.0.9)" \
  "compares semantic components numerically"
assert_equal "1" "$(ec_compare_versions 1.9223372036854775807.0 1.9.999)" \
  "compares maximum signed 64-bit semantic components without overflow"
assert_equal "9223372036854775807" "$(ec_increment_decimal 9223372036854775806)" \
  "increments a build number up to the signed 64-bit maximum"
assert_fails "rejects build-number overflow" ec_increment_decimal 9223372036854775807

for invalid_version in 1 1.2 01.2.3 1.02.3 1.2.03 1.2.3.4; do
  write_project "$PROJECT" "$invalid_version" 1
  assert_fails "rejects invalid version $invalid_version" \
    "$SCRIPT_DIR/version.sh" --project "$PROJECT" --version
done
write_project "$PROJECT" 1.9223372036854775808.0 1
assert_fails "rejects a semantic component above the signed 64-bit maximum" \
  "$SCRIPT_DIR/version.sh" --project "$PROJECT" --version
write_project "$PROJECT" 1.2.3 0
assert_fails "rejects a non-positive build number" \
  "$SCRIPT_DIR/version.sh" --project "$PROJECT" --build
write_project "$PROJECT" 1.2.3 9223372036854775808
assert_fails "rejects a build number above the signed 64-bit maximum" \
  "$SCRIPT_DIR/version.sh" --project "$PROJECT" --build

cat > "$PROJECT" <<'EOF'
settings:
  base:
    MARKETING_VERSION: 1.2.3
    MARKETING_VERSION: 1.2.4
    CURRENT_PROJECT_VERSION: 1
EOF
assert_fails "rejects duplicate version settings" \
  "$SCRIPT_DIR/version.sh" --project "$PROJECT" --version

assert_fails "build-pkg rejects a conflicting VERSION override before building" \
  env VERSION=999999999.999999999.999999999 "$SCRIPT_DIR/build-pkg.sh"
assert_fails "build-pkg rejects a conflicting BUILD_NUMBER override before building" \
  env BUILD_NUMBER=999999999999999999999 "$SCRIPT_DIR/build-pkg.sh"

new_repo dry-run 1.0.2 3
add_tag v1.0.2
BEFORE_HASH="$(shasum -a 256 "$FIXTURE_REPO/project.yml" | awk '{print $1}')"
BEFORE_HEAD="$(git -C "$FIXTURE_REPO" rev-parse HEAD)"
BEFORE_TAGS="$(git -C "$FIXTURE_REPO" tag --list)"
"$SCRIPT_DIR/prepare-release.sh" --dry-run --repo "$FIXTURE_REPO" \
  --project "$FIXTURE_REPO/project.yml" 1.0.3 >/dev/null
AFTER_HASH="$(shasum -a 256 "$FIXTURE_REPO/project.yml" | awk '{print $1}')"
assert_equal "$BEFORE_HASH" "$AFTER_HASH" "dry-run does not modify project.yml"

"$SCRIPT_DIR/prepare-release.sh" --repo "$FIXTURE_REPO" \
  --project "$FIXTURE_REPO/project.yml" 1.0.3 >/dev/null
assert_equal "1.0.3" "$($SCRIPT_DIR/version.sh --project "$FIXTURE_REPO/project.yml" --version)" \
  "release preparation updates the marketing version"
assert_equal "4" "$($SCRIPT_DIR/version.sh --project "$FIXTURE_REPO/project.yml" --build)" \
  "release preparation increments the build number"
assert_equal "$BEFORE_HEAD" "$(git -C "$FIXTURE_REPO" rev-parse HEAD)" \
  "release preparation does not create a commit"
assert_equal "$BEFORE_TAGS" "$(git -C "$FIXTURE_REPO" tag --list)" \
  "release preparation does not create a tag"
TEMP_FILE_COUNT="$(find "$FIXTURE_REPO" -maxdepth 1 -name '.project.yml.*' -print | wc -l | tr -d ' ')"
assert_equal "0" "$TEMP_FILE_COUNT" "atomic replacement leaves no temporary project file"

new_repo build-only 1.0.2 3
BEFORE_HASH="$(shasum -a 256 "$FIXTURE_REPO/project.yml" | awk '{print $1}')"
"$SCRIPT_DIR/prepare-release.sh" --dry-run --build-only --repo "$FIXTURE_REPO" \
  --project "$FIXTURE_REPO/project.yml" >/dev/null
AFTER_HASH="$(shasum -a 256 "$FIXTURE_REPO/project.yml" | awk '{print $1}')"
assert_equal "$BEFORE_HASH" "$AFTER_HASH" "build-only dry-run does not modify project.yml"
"$SCRIPT_DIR/prepare-release.sh" --build-only --repo "$FIXTURE_REPO" \
  --project "$FIXTURE_REPO/project.yml" >/dev/null
assert_equal "1.0.2" "$($SCRIPT_DIR/version.sh --project "$FIXTURE_REPO/project.yml" --version)" \
  "build-only keeps the marketing version"
assert_equal "4" "$($SCRIPT_DIR/version.sh --project "$FIXTURE_REPO/project.yml" --build)" \
  "build-only increments only the build number"

new_repo release-guards 1.0.0 1
add_tag v1.0.2
assert_fails "release preparation rejects a version below the highest stable tag" \
  "$SCRIPT_DIR/prepare-release.sh" --repo "$FIXTURE_REPO" \
  --project "$FIXTURE_REPO/project.yml" 1.0.1
assert_fails "tag validation rejects a source version below the highest stable tag" \
  "$SCRIPT_DIR/version.sh" --repo "$FIXTURE_REPO" \
  --project "$FIXTURE_REPO/project.yml" --check-tag v1.0.0
assert_fails "release preparation rejects a downgrade" \
  "$SCRIPT_DIR/prepare-release.sh" --repo "$FIXTURE_REPO" \
  --project "$FIXTURE_REPO/project.yml" 0.9.9
assert_fails "release preparation rejects a malformed target" \
  "$SCRIPT_DIR/prepare-release.sh" --repo "$FIXTURE_REPO" \
  --project "$FIXTURE_REPO/project.yml" 1.1

new_repo existing-tag 1.0.2 3
add_tag v1.0.3
assert_fails "release preparation rejects an existing target tag" \
  "$SCRIPT_DIR/prepare-release.sh" --repo "$FIXTURE_REPO" \
  --project "$FIXTURE_REPO/project.yml" 1.0.3

new_repo valid-tag 1.0.2 3
add_tag v1.0.1
assert_equal "1.0.2" "$($SCRIPT_DIR/version.sh --repo "$FIXTURE_REPO" \
  --project "$FIXTURE_REPO/project.yml" --check-tag v1.0.2)" \
  "tag validation accepts the next tag before it is created"
assert_fails "tag validation rejects a malformed tag" \
  "$SCRIPT_DIR/version.sh" --repo "$FIXTURE_REPO" \
  --project "$FIXTURE_REPO/project.yml" --check-tag v1.0
assert_fails "normal release preparation rejects the current version" \
  "$SCRIPT_DIR/prepare-release.sh" --repo "$FIXTURE_REPO" \
  --project "$FIXTURE_REPO/project.yml" 1.0.2
assert_fails "build-only rejects a different marketing version" \
  "$SCRIPT_DIR/prepare-release.sh" --build-only --repo "$FIXTURE_REPO" \
  --project "$FIXTURE_REPO/project.yml" 1.0.3

new_repo before-tag-creation 1.0.3 4
git -C "$FIXTURE_REPO" tag v1.0.2
assert_equal "1.0.3" \
  "$("$SCRIPT_DIR/version.sh" --repo "$FIXTURE_REPO" --project "$FIXTURE_REPO/project.yml" --check-tag v1.0.3)" \
  "tag validation supports the documented check before creating a new tag"

new_repo duplicate-atomic 1.0.2 3
printf '    MARKETING_VERSION: 1.0.3\n' >> "$FIXTURE_REPO/project.yml"
BEFORE_HASH="$(shasum -a 256 "$FIXTURE_REPO/project.yml" | awk '{print $1}')"
assert_fails "duplicate settings abort before an update" \
  "$SCRIPT_DIR/prepare-release.sh" --repo "$FIXTURE_REPO" \
  --project "$FIXTURE_REPO/project.yml" 1.0.4
AFTER_HASH="$(shasum -a 256 "$FIXTURE_REPO/project.yml" | awk '{print $1}')"
assert_equal "$BEFORE_HASH" "$AFTER_HASH" "failed preparation leaves project.yml unchanged"

new_repo build-overflow 1.0.2 9223372036854775807
BEFORE_HASH="$(shasum -a 256 "$FIXTURE_REPO/project.yml" | awk '{print $1}')"
assert_fails "build-only rejects signed 64-bit build-number overflow" \
  "$SCRIPT_DIR/prepare-release.sh" --build-only --repo "$FIXTURE_REPO" \
  --project "$FIXTURE_REPO/project.yml"
AFTER_HASH="$(shasum -a 256 "$FIXTURE_REPO/project.yml" | awk '{print $1}')"
assert_equal "$BEFORE_HASH" "$AFTER_HASH" "overflow leaves project.yml unchanged"

# Render postinstall exactly as build-pkg does, but validate only an isolated
# offline-volume fixture. This never installs, launches, or terminates an app.
OFFLINE_VOLUME="$TEST_ROOT/offline-volume"
APP_PATH="$OFFLINE_VOLUME/Applications/EasyContext.app"
APPEX_PATH="$APP_PATH/Contents/PlugIns/EasyContextFinder.appex"
mkdir -p "$APP_PATH/Contents/MacOS" "$APPEX_PATH/Contents/MacOS"
printf '#!/bin/sh\nexit 0\n' > "$APP_PATH/Contents/MacOS/EasyContext"
printf '#!/bin/sh\nexit 0\n' > "$APPEX_PATH/Contents/MacOS/EasyContextFinder"
chmod 0755 "$APP_PATH/Contents/MacOS/EasyContext" "$APPEX_PATH/Contents/MacOS/EasyContextFinder"
for plist in "$APP_PATH/Contents/Info.plist" "$APPEX_PATH/Contents/Info.plist"; do
  cat > "$plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleShortVersionString</key><string>1.0.2</string>
<key>CFBundleVersion</key><string>3</string>
</dict></plist>
EOF
done
APP_HASH="$(shasum -a 256 "$APP_PATH/Contents/MacOS/EasyContext" | awk '{print $1}')"
APPEX_HASH="$(shasum -a 256 "$APPEX_PATH/Contents/MacOS/EasyContextFinder" | awk '{print $1}')"
RENDERED_POSTINSTALL="$TEST_ROOT/postinstall"
sed \
  -e 's/@EXPECTED_VERSION@/1.0.2/g' \
  -e 's/@EXPECTED_BUILD_NUMBER@/3/g' \
  -e "s/@APP_EXECUTABLE_SHA256@/$APP_HASH/g" \
  -e "s/@APPEX_EXECUTABLE_SHA256@/$APPEX_HASH/g" \
  "$REPO_ROOT/packaging/pkg-scripts/postinstall" > "$RENDERED_POSTINSTALL"
chmod 0755 "$RENDERED_POSTINSTALL"
"$RENDERED_POSTINSTALL" unused unused "$OFFLINE_VOLUME" >/dev/null
pass "postinstall accepts matching version, build, and executable hashes on an offline fixture"
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 1.0.1' "$APP_PATH/Contents/Info.plist"
assert_fails "postinstall rejects a mismatched application version" \
  "$RENDERED_POSTINSTALL" unused unused "$OFFLINE_VOLUME"
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 1.0.2' "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 2' "$APP_PATH/Contents/Info.plist"
assert_fails "postinstall rejects a mismatched application build" \
  "$RENDERED_POSTINSTALL" unused unused "$OFFLINE_VOLUME"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 3' "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 1.0.1' "$APPEX_PATH/Contents/Info.plist"
assert_fails "postinstall rejects a mismatched extension version" \
  "$RENDERED_POSTINSTALL" unused unused "$OFFLINE_VOLUME"
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 1.0.2' "$APPEX_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 2' "$APPEX_PATH/Contents/Info.plist"
assert_fails "postinstall rejects a mismatched extension build" \
  "$RENDERED_POSTINSTALL" unused unused "$OFFLINE_VOLUME"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 3' "$APPEX_PATH/Contents/Info.plist"
printf '# altered\n' >> "$APP_PATH/Contents/MacOS/EasyContext"
assert_fails "postinstall rejects a skipped or altered application executable" \
  "$RENDERED_POSTINSTALL" unused unused "$OFFLINE_VOLUME"
printf '#!/bin/sh\nexit 0\n' > "$APP_PATH/Contents/MacOS/EasyContext"
chmod 0755 "$APP_PATH/Contents/MacOS/EasyContext"
printf '# altered\n' >> "$APPEX_PATH/Contents/MacOS/EasyContextFinder"
assert_fails "postinstall rejects a skipped or altered extension executable" \
  "$RENDERED_POSTINSTALL" unused unused "$OFFLINE_VOLUME"

printf '1..%d\n' "$TEST_COUNT"
