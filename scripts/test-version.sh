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
  git -C "$FIXTURE_REPO" init -q -b master
  git -C "$FIXTURE_REPO" -c core.hooksPath=/dev/null add project.yml
  git -C "$FIXTURE_REPO" -c user.name=VersionTest -c user.email=version@test.invalid \
    -c commit.gpgsign=false -c core.hooksPath=/dev/null \
    commit --allow-empty -q -m initial
}

add_tag() {
  git -C "$FIXTURE_REPO" -c tag.gpgSign=false -c core.hooksPath=/dev/null tag "$1"
}

PROJECT="$TEST_ROOT/read-project.yml"
write_project "$PROJECT" 1.0.10 42
assert_equal "1.0.10" "$($SCRIPT_DIR/release.sh show --project "$PROJECT" --version)" \
  "reads the strict marketing version"
assert_equal "42" "$($SCRIPT_DIR/release.sh show --project "$PROJECT" --build)" \
  "reads the positive build number"
cat > "$PROJECT" <<'EOF'
settings:
  base:
    MARKETING_VERSION: "2.3.4" # release version
    CURRENT_PROJECT_VERSION: '57' # monotonically increasing build
EOF
assert_equal "2.3.4" "$($SCRIPT_DIR/release.sh show --project "$PROJECT" --version)" \
  "reads quoted values followed by comments"
assert_equal "57" "$($SCRIPT_DIR/release.sh show --project "$PROJECT" --build)" \
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
    "$SCRIPT_DIR/release.sh" show --project "$PROJECT" --version
done
write_project "$PROJECT" 1.9223372036854775808.0 1
assert_fails "rejects a semantic component above the signed 64-bit maximum" \
  "$SCRIPT_DIR/release.sh" show --project "$PROJECT" --version
write_project "$PROJECT" 1.2.3 0
assert_fails "rejects a non-positive build number" \
  "$SCRIPT_DIR/release.sh" show --project "$PROJECT" --build
write_project "$PROJECT" 1.2.3 9223372036854775808
assert_fails "rejects a build number above the signed 64-bit maximum" \
  "$SCRIPT_DIR/release.sh" show --project "$PROJECT" --build

cat > "$PROJECT" <<'EOF'
settings:
  base:
    MARKETING_VERSION: 1.2.3
    MARKETING_VERSION: 1.2.4
    CURRENT_PROJECT_VERSION: 1
EOF
assert_fails "rejects duplicate version settings" \
  "$SCRIPT_DIR/release.sh" show --project "$PROJECT" --version

OVERRIDE_REPO="$TEST_ROOT/override-build"
mkdir -p "$OVERRIDE_REPO/scripts"
cp "$REPO_ROOT/project.yml" "$OVERRIDE_REPO/project.yml"
cp "$SCRIPT_DIR/build-pkg.sh" "$SCRIPT_DIR/version-lib.sh" "$OVERRIDE_REPO/scripts/"
assert_fails "build-pkg rejects a conflicting VERSION override before building" \
  env VERSION=999999999.999999999.999999999 "$OVERRIDE_REPO/scripts/build-pkg.sh"
assert_fails "build-pkg rejects a conflicting BUILD_NUMBER override before building" \
  env BUILD_NUMBER=999999999999999999999 "$OVERRIDE_REPO/scripts/build-pkg.sh"

new_repo dry-run 1.0.2 3
add_tag v1.0.2
BEFORE_HASH="$(shasum -a 256 "$FIXTURE_REPO/project.yml" | awk '{print $1}')"
BEFORE_HEAD="$(git -C "$FIXTURE_REPO" rev-parse HEAD)"
BEFORE_TAGS="$(git -C "$FIXTURE_REPO" tag --list)"
"$SCRIPT_DIR/release.sh" prepare --dry-run --repo "$FIXTURE_REPO" \
  --project "$FIXTURE_REPO/project.yml" 1.0.3 >/dev/null
AFTER_HASH="$(shasum -a 256 "$FIXTURE_REPO/project.yml" | awk '{print $1}')"
assert_equal "$BEFORE_HASH" "$AFTER_HASH" "dry-run does not modify project.yml"

"$SCRIPT_DIR/release.sh" prepare --repo "$FIXTURE_REPO" \
  --project "$FIXTURE_REPO/project.yml" 1.0.3 >/dev/null
assert_equal "1.0.3" "$($SCRIPT_DIR/release.sh show --project "$FIXTURE_REPO/project.yml" --version)" \
  "release preparation updates the marketing version"
assert_equal "4" "$($SCRIPT_DIR/release.sh show --project "$FIXTURE_REPO/project.yml" --build)" \
  "release preparation increments the build number"
assert_equal "$BEFORE_HEAD" "$(git -C "$FIXTURE_REPO" rev-parse HEAD)" \
  "release preparation does not create a commit"
assert_equal "$BEFORE_TAGS" "$(git -C "$FIXTURE_REPO" tag --list)" \
  "release preparation does not create a tag"
TEMP_FILE_COUNT="$(find "$FIXTURE_REPO" -maxdepth 1 -name '.project.yml.*' -print | wc -l | tr -d ' ')"
assert_equal "0" "$TEMP_FILE_COUNT" "atomic replacement leaves no temporary project file"

new_repo build-only 1.0.2 3
BEFORE_HASH="$(shasum -a 256 "$FIXTURE_REPO/project.yml" | awk '{print $1}')"
"$SCRIPT_DIR/release.sh" next-build --dry-run --repo "$FIXTURE_REPO" \
  --project "$FIXTURE_REPO/project.yml" >/dev/null
AFTER_HASH="$(shasum -a 256 "$FIXTURE_REPO/project.yml" | awk '{print $1}')"
assert_equal "$BEFORE_HASH" "$AFTER_HASH" "build-only dry-run does not modify project.yml"
"$SCRIPT_DIR/release.sh" next-build --repo "$FIXTURE_REPO" \
  --project "$FIXTURE_REPO/project.yml" >/dev/null
assert_equal "1.0.2" "$($SCRIPT_DIR/release.sh show --project "$FIXTURE_REPO/project.yml" --version)" \
  "build-only keeps the marketing version"
assert_equal "4" "$($SCRIPT_DIR/release.sh show --project "$FIXTURE_REPO/project.yml" --build)" \
  "build-only increments only the build number"

new_repo release-guards 1.0.0 1
add_tag v1.0.2
assert_fails "release preparation rejects a version below the highest stable tag" \
  "$SCRIPT_DIR/release.sh" prepare --repo "$FIXTURE_REPO" \
  --project "$FIXTURE_REPO/project.yml" 1.0.1
assert_equal "1.0.0" "$("$SCRIPT_DIR/release.sh" check-tag --repo "$FIXTURE_REPO" \
  --project "$FIXTURE_REPO/project.yml" v1.0.0)" \
  "pure tag validation accepts historical versions below the highest tag"
assert_fails "release preparation rejects a downgrade" \
  "$SCRIPT_DIR/release.sh" prepare --repo "$FIXTURE_REPO" \
  --project "$FIXTURE_REPO/project.yml" 0.9.9
assert_fails "release preparation rejects a malformed target" \
  "$SCRIPT_DIR/release.sh" prepare --repo "$FIXTURE_REPO" \
  --project "$FIXTURE_REPO/project.yml" 1.1

new_repo existing-tag 1.0.2 3
add_tag v1.0.3
assert_fails "release preparation rejects an existing target tag" \
  "$SCRIPT_DIR/release.sh" prepare --repo "$FIXTURE_REPO" \
  --project "$FIXTURE_REPO/project.yml" 1.0.3

new_repo valid-tag 1.0.2 3
add_tag v1.0.1
assert_equal "1.0.2" "$($SCRIPT_DIR/release.sh check-tag --repo "$FIXTURE_REPO" \
  --project "$FIXTURE_REPO/project.yml" v1.0.2)" \
  "tag validation accepts the next tag before it is created"
assert_fails "tag validation rejects a malformed tag" \
  "$SCRIPT_DIR/release.sh" check-tag --repo "$FIXTURE_REPO" \
  --project "$FIXTURE_REPO/project.yml" v1.0
assert_fails "normal release preparation rejects the current version" \
  "$SCRIPT_DIR/release.sh" prepare --repo "$FIXTURE_REPO" \
  --project "$FIXTURE_REPO/project.yml" 1.0.2
assert_fails "build-only rejects a different marketing version" \
  "$SCRIPT_DIR/release.sh" next-build --repo "$FIXTURE_REPO" \
  --project "$FIXTURE_REPO/project.yml" 1.0.3

new_repo before-tag-creation 1.0.3 4
add_tag v1.0.2
assert_equal "1.0.3" \
  "$("$SCRIPT_DIR/release.sh" check-tag --repo "$FIXTURE_REPO" --project "$FIXTURE_REPO/project.yml" v1.0.3)" \
  "tag validation supports the documented check before creating a new tag"

new_repo duplicate-atomic 1.0.2 3
printf '    MARKETING_VERSION: 1.0.3\n' >> "$FIXTURE_REPO/project.yml"
BEFORE_HASH="$(shasum -a 256 "$FIXTURE_REPO/project.yml" | awk '{print $1}')"
assert_fails "duplicate settings abort before an update" \
  "$SCRIPT_DIR/release.sh" prepare --repo "$FIXTURE_REPO" \
  --project "$FIXTURE_REPO/project.yml" 1.0.4
AFTER_HASH="$(shasum -a 256 "$FIXTURE_REPO/project.yml" | awk '{print $1}')"
assert_equal "$BEFORE_HASH" "$AFTER_HASH" "failed preparation leaves project.yml unchanged"

new_repo build-overflow 1.0.2 9223372036854775807
BEFORE_HASH="$(shasum -a 256 "$FIXTURE_REPO/project.yml" | awk '{print $1}')"
assert_fails "build-only rejects signed 64-bit build-number overflow" \
  "$SCRIPT_DIR/release.sh" next-build --repo "$FIXTURE_REPO" \
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

# Release governance uses real temporary Git history and deterministic, offline
# transport doubles. A fetch can only reach the temporary bare repository.
FAKE_BIN="$TEST_ROOT/fake-bin"
mkdir -p "$FAKE_BIN"
REAL_GIT="$(command -v git)"
export REAL_GIT
cat > "$FAKE_BIN/git" <<'EOF'
#!/bin/bash
set -euo pipefail
if [[ " $* " == *' fetch '* ]]; then
  [[ "$1" == -C && "$3" == fetch && "$*" == *'origin +refs/heads/master:refs/remotes/origin/master --tags' ]] || exit 98
  [[ "${TEST_FETCH_FAIL:-0}" == 0 ]] || exit 97
  exec "$REAL_GIT" -C "$2" fetch --no-recurse-submodules "$TEST_REMOTE" '+refs/heads/master:refs/remotes/origin/master' --tags
fi
[[ " $* " != *' push '* ]] || exit 96
exec "$REAL_GIT" "$@"
EOF
cat > "$FAKE_BIN/curl" <<'EOF'
#!/bin/bash
set -euo pipefail
[[ "${TEST_CURL_FAIL:-0}" == 0 ]] || exit 22
[[ "${!#}" == "https://api.github.com/repos/yantaolu/easy-context/actions/workflows/ci.yml/runs?branch=master&event=push&head_sha=$TEST_SHA&per_page=100" ]] || exit 95
cat "$TEST_CI_JSON"
EOF
cat > "$FAKE_BIN/gh" <<'EOF'
#!/bin/bash
exit 94
EOF
chmod +x "$FAKE_BIN/git" "$FAKE_BIN/curl" "$FAKE_BIN/gh"

commit_fixture() {
  git -C "$FIXTURE_REPO" -c core.hooksPath=/dev/null add -A
  git -C "$FIXTURE_REPO" -c user.name=VersionTest -c user.email=version@test.invalid \
    -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q -m "$1"
}
new_check_repo() {
  new_repo "$1" 1.2.0 7
  TEST_REMOTE="$TEST_ROOT/$1.git"
  git clone --bare -q "$FIXTURE_REPO" "$TEST_REMOTE"
  git -C "$FIXTURE_REPO" remote add origin https://github.com/yantaolu/easy-context.git
  TEST_SHA="$(git -C "$FIXTURE_REPO" rev-parse HEAD)"
  TEST_CI_JSON="$TEST_ROOT/$1-ci.json"
  jq -n --arg sha "$TEST_SHA" '{workflow_runs: [{id: 20, created_at: "2026-09-05T00:00:00Z", run_attempt: 1, path: ".github/workflows/ci.yml", head_sha: $sha, head_branch: "master", event: "push", status: "completed", conclusion: "success"}]}' > "$TEST_CI_JSON"
}
run_check() {
  env PATH="$FAKE_BIN:$PATH" TEST_REMOTE="$TEST_REMOTE" TEST_SHA="$TEST_SHA" \
    TEST_CI_JSON="$TEST_CI_JSON" "$SCRIPT_DIR/release.sh" check v1.2.0 --repo "$FIXTURE_REPO"
}
assert_succeeds() {
  local label="$1"
  shift
  if ! "$@" >"$TEST_ROOT/last-command.log" 2>&1; then
    cat "$TEST_ROOT/last-command.log" >&2
    fail "$label"
  fi
  pass "$label"
}
new_check_repo check-clean
assert_succeeds "complete check accepts clean committed HEAD with successful master push CI" run_check
assert_equal "" "$(git -C "$FIXTURE_REPO" tag --list)" "complete check never creates a tag"
printf '# dirty\n' >> "$FIXTURE_REPO/project.yml"
assert_fails "complete check rejects a dirty worktree" run_check
git -C "$FIXTURE_REPO" -c core.hooksPath=/dev/null add project.yml
assert_fails "complete check rejects staged changes" run_check
commit_fixture modified
assert_fails "complete check rejects HEAD not reachable from origin/master" run_check

new_check_repo check-untracked
touch "$FIXTURE_REPO/untracked"
assert_fails "complete check rejects untracked files" run_check
new_check_repo check-network
assert_fails "complete check fails closed when fetch fails" env TEST_FETCH_FAIL=1 \
  PATH="$FAKE_BIN:$PATH" TEST_REMOTE="$TEST_REMOTE" "$SCRIPT_DIR/release.sh" check v1.2.0 --repo "$FIXTURE_REPO"
assert_fails "complete check fails closed when GitHub API fails" env TEST_CURL_FAIL=1 \
  PATH="$FAKE_BIN:$PATH" TEST_REMOTE="$TEST_REMOTE" "$SCRIPT_DIR/release.sh" check v1.2.0 --repo "$FIXTURE_REPO"
git -C "$FIXTURE_REPO" remote set-url origin https://github.com/other/repository.git
assert_fails "complete check rejects an unrelated origin before checking this repository CI" run_check

new_check_repo check-ci
for field in conclusion status head_sha head_branch event path; do
  cp "$TEST_CI_JSON" "$TEST_ROOT/ci-original.json"
  jq --arg field "$field" '.workflow_runs[0][$field] = "wrong"' "$TEST_ROOT/ci-original.json" > "$TEST_CI_JSON"
  assert_fails "complete check rejects CI with incorrect $field" run_check
  cp "$TEST_ROOT/ci-original.json" "$TEST_CI_JSON"
done
cp "$TEST_CI_JSON" "$TEST_ROOT/ci-original.json"
jq '.workflow_runs += [(.workflow_runs[0] | .id = 21 | .conclusion = "failure")]' "$TEST_ROOT/ci-original.json" > "$TEST_CI_JSON"
assert_fails "complete check rejects a failed latest run despite an older success" run_check
jq '.workflow_runs += [(.workflow_runs[0] | .run_attempt = 2 | .conclusion = "failure")]' "$TEST_ROOT/ci-original.json" > "$TEST_CI_JSON"
assert_fails "complete check rejects a failed latest attempt despite an earlier success" run_check
printf '{"workflow_runs":[]}\n' > "$TEST_CI_JSON"
assert_fails "complete check rejects missing CI" run_check
printf 'invalid JSON\n' > "$TEST_CI_JSON"
assert_fails "complete check rejects invalid API JSON" run_check

new_check_repo check-remote-tag
git -C "$TEST_REMOTE" -c tag.gpgSign=false -c core.hooksPath=/dev/null tag v1.2.0
assert_fails "complete check rejects a tag that exists only on the remote" run_check
new_check_repo check-tag-conflict
add_tag v1.0.0
printf '# remote tag target\n' >> "$FIXTURE_REPO/project.yml"
commit_fixture remote-tag-target
git -C "$TEST_REMOTE" fetch -q "$FIXTURE_REPO" HEAD
git -C "$TEST_REMOTE" -c tag.gpgSign=false -c core.hooksPath=/dev/null tag v1.0.0 FETCH_HEAD
assert_fails "complete check rejects conflicting local and remote tags during fetch" run_check

new_check_repo check-uncommitted-source
git -C "$FIXTURE_REPO" -c core.hooksPath=/dev/null rm --cached -q project.yml
printf 'project.yml\n' > "$FIXTURE_REPO/.gitignore"
commit_fixture ignore-uncommitted-source
assert_fails "complete check rejects an ignored source absent from committed HEAD" run_check
new_check_repo check-hidden-source-change
git -C "$FIXTURE_REPO" update-index --skip-worktree project.yml
printf '# hidden source change\n' >> "$FIXTURE_REPO/project.yml"
assert_fails "complete check rejects source changes hidden from git status" run_check

# Exercise the actual packaging script with fake build/sign/package executables.
# PlistBuddy, architecture assertions, checksums, and installer-script rendering
# still run. This cannot invoke Xcode, install a package, or contact the network.
cat > "$FAKE_BIN/xcodegen" <<'EOF'
#!/bin/bash
[[ -z "${TEST_XCODEGEN_MARKER:-}" ]] || touch "$TEST_XCODEGEN_MARKER"
if [[ -n "${TEST_BUILD_VERSION_PROBE:-}" ]]; then
  "$TEST_RELEASE_CLI" next-build --repo "$PWD" > "$TEST_BUILD_VERSION_PROBE" 2>&1
  printf '%s\n' "$?" > "$TEST_BUILD_VERSION_PROBE.status"
  exit 91
fi
if [[ "${TEST_REPLACE_LOCK:-0}" == 1 ]]; then
  mv .build-pkg.lock .build-pkg.lock-original
  mkdir .build-pkg.lock
  exit 91
fi
[[ "${TEST_XCODEGEN_FAIL:-0}" == 0 ]] || exit 91
exit 0
EOF
cat > "$FAKE_BIN/xcodebuild" <<'EOF'
#!/bin/bash
set -euo pipefail
while [[ $# -gt 0 ]]; do
  case "$1" in
    -project) project_root="$(dirname "$2")"; shift ;;
    -derivedDataPath) derived="$2"; shift ;;
    MARKETING_VERSION=*) version="${1#*=}" ;;
    CURRENT_PROJECT_VERSION=*) build="${1#*=}" ;;
  esac
  shift
done
app="$derived/Build/Products/Release/EasyContext.app"
appex="$app/Contents/PlugIns/EasyContextFinder.appex"
for bundle in "$app" "$appex"; do
  mkdir -p "$bundle/Contents/MacOS"
  cat > "$bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>$build</string>
</dict></plist>
PLIST
done
cp "$project_root/project.yml" "$app/Contents/MacOS/EasyContext"
cp "$project_root/project.yml" "$appex/Contents/MacOS/EasyContextFinder"
[[ -z "${TEST_BUILD_SNAPSHOT:-}" ]] || cp "$project_root/project.yml" "$TEST_BUILD_SNAPSHOT"
if [[ -n "${TEST_SWAP_AFTER_BUILD:-}" ]]; then
  run_relative="$(pwd -P)"
  run_relative="${run_relative#"$project_root/dist/"}"
  mkdir -p "$TEST_SWAP_AFTER_BUILD/$run_relative/DerivedData"
  printf 'outside preview cleanup\n' > "$TEST_SWAP_AFTER_BUILD/$run_relative/DerivedData/sentinel"
  mv "$project_root/dist" "$project_root/dist-original"
  ln -s "$TEST_SWAP_AFTER_BUILD" "$project_root/dist"
fi
EOF
cat > "$FAKE_BIN/lipo" <<'EOF'
#!/bin/bash
if [[ "$TARGET_ARCH" == universal ]]; then echo 'arm64 x86_64'; else echo "$TARGET_ARCH"; fi
EOF
cat > "$FAKE_BIN/codesign" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$FAKE_BIN/pkgbuild" <<'EOF'
#!/bin/bash
set -euo pipefail
if [[ "$1" == --analyze ]]; then
  printf '<?xml version="1.0"?><plist version="1.0"><array/></plist>\n' > "${!#}"
else
  if [[ -n "${TEST_COLLISION:-}" ]]; then printf 'concurrent artifact\n' > "$TEST_COLLISION"; fi
  if [[ -n "${TEST_TEMP_PATH_LOG:-}" ]]; then
    basename "${!#}" >> "$TEST_TEMP_PATH_LOG"
    for checksum in "$(dirname "${!#}")"/.EasyContext-*sha256*; do
      [[ ! -f "$checksum" ]] || basename "$checksum" >> "$TEST_TEMP_PATH_LOG.sha256"
    done
  fi
  printf 'fixture package\n' > "${!#}"
fi
EOF
chmod +x "$FAKE_BIN/xcodegen" "$FAKE_BIN/xcodebuild" "$FAKE_BIN/lipo" "$FAKE_BIN/codesign" "$FAKE_BIN/pkgbuild"
new_repo preview 1.2.0 7
mkdir -p "$FIXTURE_REPO/scripts" "$FIXTURE_REPO/packaging"
cp "$SCRIPT_DIR/build-pkg.sh" "$SCRIPT_DIR/version-lib.sh" "$FIXTURE_REPO/scripts/"
cp -R "$REPO_ROOT/packaging/pkg-scripts" "$FIXTURE_REPO/packaging/"
printf '# staged snapshot\n' >> "$FIXTURE_REPO/project.yml"
git -C "$FIXTURE_REPO" -c core.hooksPath=/dev/null add project.yml
printf '# worktree snapshot\n' >> "$FIXTURE_REPO/project.yml"
BEFORE_HASH="$(shasum -a 256 "$FIXTURE_REPO/project.yml")"
run_preview() {
  env PATH="$FAKE_BIN:$PATH" TEST_BUILD_SNAPSHOT="$TEST_ROOT/preview-source.yml" \
    TEST_TEMP_PATH_LOG="$TEST_ROOT/preview-temp-paths" \
    "$SCRIPT_DIR/release.sh" preview --repo "$FIXTURE_REPO" "$@"
}

# dist cleanup is intentionally destructive, but only inside this fixture. Seed
# hidden files, historical preview layouts, and a nested symlink to prove scope.
SYMLINK_TARGET="$TEST_ROOT/symlink-target"
mkdir -p "$FIXTURE_REPO/dist/preview/1.1.0-build2/arm64/run.old" "$SYMLINK_TARGET"
printf 'old preview\n' > "$FIXTURE_REPO/dist/preview/1.1.0-build2/arm64/run.old/old.pkg"
printf 'hidden\n' > "$FIXTURE_REPO/dist/.hidden-output"
printf 'outside sentinel\n' > "$SYMLINK_TARGET/sentinel"
ln -s "$SYMLINK_TARGET" "$FIXTURE_REPO/dist/nested-link"
assert_succeeds "preview builds the current worktree with the host architecture by default" run_preview
[[ "$(< "$TEST_ROOT/last-command.log")" == *'staged changes exist'* ]] || fail "missing staged warning"
pass "preview warns about staged changes and the worktree/index distinction"
assert_equal "$BEFORE_HASH" "$(shasum -a 256 "$FIXTURE_REPO/project.yml")" "preview does not increment version or build"
PREVIEW_PKG="$(find "$FIXTURE_REPO/dist/preview" -name '*.pkg' -type f)"
EXPECTED_NAME="EasyContext-1.2.0-build7-preview-macOS-$(uname -m).pkg"
assert_equal "$EXPECTED_NAME" "$(basename "$PREVIEW_PKG")" "preview filename includes build, preview marker, and architecture"
[[ ! -e "$FIXTURE_REPO/dist/.hidden-output" && ! -e "$FIXTURE_REPO/dist/nested-link" \
    && ! -e "$FIXTURE_REPO/dist/preview/1.1.0-build2" ]] || fail "preview did not clear all prior dist children"
pass "preview clears hidden and historical dist contents before building"
assert_equal 'outside sentinel' "$(< "$SYMLINK_TARGET/sentinel")" "dist cleanup does not follow nested symlinks"
cmp "$FIXTURE_REPO/project.yml" "$TEST_ROOT/preview-source.yml" || fail "preview built the index instead of worktree"
pass "preview build consumes unstaged worktree content"
[[ ! -e "$(dirname "$PREVIEW_PKG")/DerivedData" ]] || fail "preview retained DerivedData"
pass "preview removes its isolated DerivedData after building"
(cd "$(dirname "$PREVIEW_PKG")" && shasum -a 256 -c "$EXPECTED_NAME.sha256" >/dev/null) || fail "invalid preview checksum"
pass "preview emits a valid sha256 companion"
PREVIEW_HASH="$(shasum -a 256 "$PREVIEW_PKG" | awk '{print $1}')"
assert_succeeds "same build can be previewed again in a unique run" run_preview
[[ ! -e "$PREVIEW_PKG" ]] || fail "repeat preview retained the prior package"
pass "repeat preview removes the prior package"
SECOND_PREVIEW_PKG="$(find "$FIXTURE_REPO/dist/preview" -name '*.pkg' -type f)"
assert_equal "$PREVIEW_HASH" "$(shasum -a 256 "$SECOND_PREVIEW_PKG" | awk '{print $1}')" "repeat preview publishes the newly built package"
assert_equal 1 "$(find "$FIXTURE_REPO/dist" -name '*.pkg' -type f | wc -l | tr -d ' ')" "dist contains only the latest preview package"
# These names come from the real system mktemp, observed at pkgbuild invocation;
# comparing basenames prevents unique preview directories from hiding a literal
# XXXXXX filename on macOS BSD mktemp.
for temp_kind in pkg sha256; do
  TEMP_PATH_LOG="$TEST_ROOT/preview-temp-paths"
  [[ "$temp_kind" != sha256 ]] || TEMP_PATH_LOG="$TEMP_PATH_LOG.sha256"
  FIRST_TEMP_NAME="$(sed -n '1p' "$TEMP_PATH_LOG")"
  SECOND_TEMP_NAME="$(sed -n '2p' "$TEMP_PATH_LOG")"
  TEMP_NAME_PATTERN="^\\.EasyContext-1\\.2\\.0\\.$temp_kind\\.[[:alnum:]]{6}$"
  [[ "$FIRST_TEMP_NAME" =~ $TEMP_NAME_PATTERN && "$SECOND_TEMP_NAME" =~ $TEMP_NAME_PATTERN \
      && "$FIRST_TEMP_NAME" != *XXXXXX* && "$SECOND_TEMP_NAME" != *XXXXXX* ]] \
    || fail "$temp_kind temporary name does not contain a real mktemp suffix"
  pass "$temp_kind temporary filename uses a real system mktemp random suffix"
  [[ "$FIRST_TEMP_NAME" != "$SECOND_TEMP_NAME" ]] || fail "$temp_kind temporary basenames collided"
  pass "repeated builds allocate distinct $temp_kind temporary basenames"
done
assert_succeeds "preview supports an explicit universal architecture" run_preview --arch universal
UNIVERSAL_PREVIEW="$(find "$FIXTURE_REPO/dist" -name '*-universal.pkg' -type f)"
UNIVERSAL_HASH="$(shasum -a 256 "$UNIVERSAL_PREVIEW")"
assert_fails "invalid build-pkg argument does not clear dist" env PATH="$FAKE_BIN:$PATH" "$FIXTURE_REPO/scripts/build-pkg.sh" --unknown
assert_equal "$UNIVERSAL_HASH" "$(shasum -a 256 "$UNIVERSAL_PREVIEW")" "CLI argument validation precedes dist cleanup"
assert_fails "preview rejects an invalid architecture" run_preview --arch invalid
assert_equal "$UNIVERSAL_HASH" "$(shasum -a 256 "$UNIVERSAL_PREVIEW")" "invalid architecture leaves dist untouched"

# Invalid source version is rejected before the cleanup boundary.
cp "$FIXTURE_REPO/project.yml" "$TEST_ROOT/valid-project.yml"
sed 's/MARKETING_VERSION: 1.2.0/MARKETING_VERSION: invalid/' "$TEST_ROOT/valid-project.yml" > "$FIXTURE_REPO/project.yml"
assert_fails "invalid source version does not clear dist" env PATH="$FAKE_BIN:$PATH" TARGET_ARCH=arm64 "$FIXTURE_REPO/scripts/build-pkg.sh"
assert_equal "$UNIVERSAL_HASH" "$(shasum -a 256 "$UNIVERSAL_PREVIEW")" "version validation precedes dist cleanup"
cp "$TEST_ROOT/valid-project.yml" "$FIXTURE_REPO/project.yml"

# The global lock is acquired before cleanup and is never removed by a contender.
mkdir "$FIXTURE_REPO/.build-pkg.lock"
assert_fails "global build lock rejects a concurrent build before cleanup" env PATH="$FAKE_BIN:$PATH" TARGET_ARCH=arm64 "$FIXTURE_REPO/scripts/build-pkg.sh"
assert_equal "$UNIVERSAL_HASH" "$(shasum -a 256 "$UNIVERSAL_PREVIEW")" "lock conflict preserves existing dist contents"
[[ -d "$FIXTURE_REPO/.build-pkg.lock" ]] || fail "contending build removed another process lock"
pass "contending build does not remove another process lock"
rmdir "$FIXTURE_REPO/.build-pkg.lock"

# Once validation and locking pass, a later failure leaves dist empty by design.
printf 'old local output\n' > "$FIXTURE_REPO/dist/old-local.pkg"
assert_fails "build failure occurs after clearing old dist contents" env PATH="$FAKE_BIN:$PATH" TARGET_ARCH=arm64 TEST_XCODEGEN_FAIL=1 "$FIXTURE_REPO/scripts/build-pkg.sh"
assert_equal 0 "$(find "$FIXTURE_REPO/dist" -mindepth 1 | wc -l | tr -d ' ')" "failed build does not restore cleared outputs"
[[ "$(< "$TEST_ROOT/last-command.log")" == *'不会自动恢复'* ]] || fail "failed build did not explain destructive cleanup"
pass "failed build clearly reports that old outputs are not restored"

# Formal builds keep their established CI names; each run clears the other arch.
FORMAL_ARM="$FIXTURE_REPO/dist/EasyContext-1.2.0-macOS-arm64.pkg"
assert_succeeds "formal arm64 build succeeds after a cleared failure" env PATH="$FAKE_BIN:$PATH" TARGET_ARCH=arm64 "$FIXTURE_REPO/scripts/build-pkg.sh"
(cd "$FIXTURE_REPO/dist" && shasum -a 256 -c "$(basename "$FORMAL_ARM").sha256" >/dev/null) || fail "invalid formal arm64 checksum"
assert_equal 2 "$(find "$FIXTURE_REPO/dist" -type f | wc -l | tr -d ' ')" "successful formal build leaves only pkg and sha256"
FORMAL_X86="$FIXTURE_REPO/dist/EasyContext-1.2.0-macOS-x86_64.pkg"
assert_succeeds "formal x86_64 build clears the preceding arm64 output" env PATH="$FAKE_BIN:$PATH" TARGET_ARCH=x86_64 "$FIXTURE_REPO/scripts/build-pkg.sh"
[[ ! -e "$FORMAL_ARM" && -f "$FORMAL_X86" && -f "$FORMAL_X86.sha256" ]] || fail "formal build did not retain only the last architecture"
pass "local sequential architectures retain only the last formal result"

SOURCE_ARCHIVE="$TEST_ROOT/source-archive"
mkdir -p "$SOURCE_ARCHIVE"
cp "$FIXTURE_REPO/project.yml" "$SOURCE_ARCHIVE/"
cp -R "$FIXTURE_REPO/scripts" "$FIXTURE_REPO/packaging" "$SOURCE_ARCHIVE/"
FIXTURE_REPO="$SOURCE_ARCHIVE"
assert_succeeds "preview supports a downloaded source archive without Git metadata" run_preview --arch arm64
[[ "$(< "$TEST_ROOT/last-command.log")" != *'staged changes exist'* && "$(< "$TEST_ROOT/last-command.log")" != *'fatal:'* ]] || fail "source archive emitted a Git warning"
pass "source archive preview does not report staged changes or Git errors"

ARCHIVE_FORMAL="$SOURCE_ARCHIVE/dist/EasyContext-1.2.0-macOS-arm64.pkg"
REAL_MV="$(command -v mv)"
export REAL_MV
cat > "$FAKE_BIN/mv" <<'EOF'
#!/bin/bash
set -euo pipefail
destination="${!#}"
if [[ -n "${TEST_MV_COLLISION:-}" ]] \
    && [[ "$(basename "$destination")" == "$(basename "$TEST_MV_COLLISION")" ]]; then
  printf 'last instant collision\n' > "$TEST_MV_COLLISION"
fi
if [[ -n "${TEST_MV_DIRECTORY_COLLISION:-}" ]] \
    && [[ "$(basename "$destination")" == "$(basename "$TEST_MV_DIRECTORY_COLLISION")" ]]; then
  mkdir -p "$TEST_MV_DIRECTORY_COLLISION"
fi
exec "$REAL_MV" "$@"
EOF
chmod +x "$FAKE_BIN/mv"
assert_fails "no-clobber publication detects mv -n declining a last-instant collision" \
  env PATH="$FAKE_BIN:$PATH" TARGET_ARCH=arm64 TEST_MV_COLLISION="$ARCHIVE_FORMAL" "$SOURCE_ARCHIVE/scripts/build-pkg.sh"
assert_equal 'last instant collision' "$(< "$ARCHIVE_FORMAL")" "atomic publication preserves a last-instant competing package"

DIRECTORY_COLLISION="$SOURCE_ARCHIVE/dist/EasyContext-1.2.0-macOS-universal.pkg"
assert_fails "final publication rejects a destination that becomes a directory" \
  env PATH="$FAKE_BIN:$PATH" TARGET_ARCH=universal TEST_MV_DIRECTORY_COLLISION="$DIRECTORY_COLLISION" "$SOURCE_ARCHIVE/scripts/build-pkg.sh"
[[ -d "$DIRECTORY_COLLISION" ]] || fail "directory collision fixture was unexpectedly removed"
pass "final mv cannot mistake moving into a destination directory for success"

# A dist root symlink is never traversed or cleared.
rm -rf "$SOURCE_ARCHIVE/dist"
DIST_LINK_TARGET="$TEST_ROOT/dist-link-target"
mkdir -p "$DIST_LINK_TARGET"
printf 'outside dist\n' > "$DIST_LINK_TARGET/sentinel"
ln -s "$DIST_LINK_TARGET" "$SOURCE_ARCHIVE/dist"
assert_fails "symbolic-link dist root is rejected" env PATH="$FAKE_BIN:$PATH" TARGET_ARCH=arm64 "$SOURCE_ARCHIVE/scripts/build-pkg.sh"
assert_equal 'outside dist' "$(< "$DIST_LINK_TARGET/sentinel")" "dist root symlink target is never cleared"
[[ -L "$SOURCE_ARCHIVE/dist" ]] || fail "rejected dist root symlink was removed"
pass "rejected dist root symlink remains untouched"

rm "$SOURCE_ARCHIVE/dist"
printf 'not a directory\n' > "$SOURCE_ARCHIVE/dist"
assert_fails "non-directory dist root is rejected" env PATH="$FAKE_BIN:$PATH" TARGET_ARCH=arm64 "$SOURCE_ARCHIVE/scripts/build-pkg.sh"
assert_equal 'not a directory' "$(< "$SOURCE_ARCHIVE/dist")" "non-directory dist root remains untouched"

[[ ! -e "$SOURCE_ARCHIVE/.build-pkg.lock" ]] || fail "failed build leaked the global build lock"
pass "owned global build lock is removed on exit"

# A root replacement between enumeration and rm must not redirect deletion.
REAL_RM="$(command -v rm)"
REAL_AWK="$(command -v awk)"
export REAL_RM REAL_AWK
cat > "$FAKE_BIN/rm" <<'EOF'
#!/bin/bash
set -euo pipefail
if [[ "${1:-}" == -rf && "${2:-}" == -- ]]; then
  [[ "${TEST_RM_FAIL:-0}" == 0 ]] || exit 72
  if [[ -n "${TEST_SWAP_REPO:-}" && ! -e "$TEST_SWAP_REPO/dist-original" ]]; then
    mv "$TEST_SWAP_REPO/dist" "$TEST_SWAP_REPO/dist-original"
    ln -s "$TEST_SWAP_OUTSIDE" "$TEST_SWAP_REPO/dist"
  fi
fi
exec "$REAL_RM" "$@"
EOF
cat > "$FAKE_BIN/awk" <<'EOF'
#!/bin/bash
set -euo pipefail
if [[ -n "${TEST_VERSION_PROBE:-}" && ! -e "$TEST_VERSION_PROBE" ]]; then
  touch "$TEST_VERSION_PROBE"
  set +e
  if [[ "$TEST_PROBE_KIND" == build ]]; then
    "$TEST_PROBE_REPO/scripts/build-pkg.sh" >> "$TEST_VERSION_PROBE" 2>&1
  else
    "$TEST_RELEASE_CLI" next-build --repo "$TEST_PROBE_REPO" >> "$TEST_VERSION_PROBE" 2>&1
  fi
  printf '%s\n' "$?" > "$TEST_VERSION_PROBE.status"
  set -e
fi
exec "$REAL_AWK" "$@"
EOF
chmod +x "$FAKE_BIN/rm" "$FAKE_BIN/awk"

new_packaging_repo() {
  new_repo "$1" 1.2.0 7
  mkdir -p "$FIXTURE_REPO/scripts" "$FIXTURE_REPO/packaging" "$FIXTURE_REPO/dist"
  cp "$SCRIPT_DIR/build-pkg.sh" "$SCRIPT_DIR/version-lib.sh" "$FIXTURE_REPO/scripts/"
  cp -R "$REPO_ROOT/packaging/pkg-scripts" "$FIXTURE_REPO/packaging/"
}
new_packaging_repo dist-swap-during-rm
SWAP_OUTSIDE="$TEST_ROOT/swap-outside"
mkdir -p "$SWAP_OUTSIDE"
printf 'old dist\n' > "$FIXTURE_REPO/dist/sentinel"
printf 'outside must survive\n' > "$SWAP_OUTSIDE/sentinel"
assert_fails "dist replacement between find and rm aborts the build" env PATH="$FAKE_BIN:$PATH" \
  TEST_SWAP_REPO="$FIXTURE_REPO" TEST_SWAP_OUTSIDE="$SWAP_OUTSIDE" TEST_XCODEGEN_MARKER="$TEST_ROOT/swap-xcodegen" \
  "$FIXTURE_REPO/scripts/build-pkg.sh"
assert_equal 'outside must survive' "$(< "$SWAP_OUTSIDE/sentinel")" "bound cleanup preserves the substituted root symlink target"
[[ ! -e "$FIXTURE_REPO/dist-original/sentinel" && ! -e "$TEST_ROOT/swap-xcodegen" ]] || fail "root replacement was not confined to the bound directory"
pass "root replacement clears only the original directory and never starts compilation"

new_packaging_repo dist-cleanup-failure
printf 'old dist\n' > "$FIXTURE_REPO/dist/sentinel"
assert_fails "a failed rm during cleanup stops the build" env PATH="$FAKE_BIN:$PATH" TEST_RM_FAIL=1 \
  TEST_XCODEGEN_MARKER="$TEST_ROOT/rm-failure-xcodegen" "$FIXTURE_REPO/scripts/build-pkg.sh"
[[ -f "$FIXTURE_REPO/dist/sentinel" && ! -e "$TEST_ROOT/rm-failure-xcodegen" && ! -e "$FIXTURE_REPO/.build-pkg.lock" ]] || fail "cleanup failure did not fail closed and release its lock"
pass "cleanup failure preserves undeleted content, never compiles, and releases its lock"

new_packaging_repo dist-swap-after-build
SWAP_PREVIEW_OUTSIDE="$TEST_ROOT/swap-preview-outside"
mkdir -p "$SWAP_PREVIEW_OUTSIDE"
assert_fails "root replacement after preview compilation aborts publication" env PATH="$FAKE_BIN:$PATH" \
  TARGET_ARCH=arm64 TEST_SWAP_AFTER_BUILD="$SWAP_PREVIEW_OUTSIDE" "$FIXTURE_REPO/scripts/build-pkg.sh" --preview
OUTSIDE_PREVIEW_SENTINEL="$(find "$SWAP_PREVIEW_OUTSIDE" -name sentinel -type f)"
assert_equal 'outside preview cleanup' "$(< "$OUTSIDE_PREVIEW_SENTINEL")" "preview cleanup stays bound and cannot delete the external mirrored DerivedData"
assert_equal 0 "$(find "$FIXTURE_REPO/dist-original" -name DerivedData -type d | wc -l | tr -d ' ')" "failed preview cleans only its original bound DerivedData"
assert_equal 0 "$(find "$SWAP_PREVIEW_OUTSIDE" -name '*.pkg' -type f | wc -l | tr -d ' ')" "a replaced dist root receives no published package"

new_packaging_repo version-lock
VERSION_BEFORE="$(shasum -a 256 "$FIXTURE_REPO/project.yml")"
mkdir "$FIXTURE_REPO/.build-pkg.lock"
for mutation in 'next-build' 'next-build --dry-run' 'prepare 1.3.0' 'prepare 1.3.0 --dry-run'; do
  read -r -a MUTATION_ARGS <<< "$mutation"
  assert_fails "held build lock rejects $mutation" "$SCRIPT_DIR/release.sh" "${MUTATION_ARGS[@]}" --repo "$FIXTURE_REPO"
done
assert_equal "$VERSION_BEFORE" "$(shasum -a 256 "$FIXTURE_REPO/project.yml")" "lock conflicts do not advance or rewrite the version"
[[ -d "$FIXTURE_REPO/.build-pkg.lock" ]] || fail "version contender removed another lock"
pass "version contenders preserve the existing lock"
assert_equal '1.2.0' "$("$SCRIPT_DIR/release.sh" show --version --repo "$FIXTURE_REPO")" "read-only show does not acquire the mutation lock"
assert_equal '1.2.0' "$("$SCRIPT_DIR/release.sh" check-tag v1.2.0 --repo "$FIXTURE_REPO")" "read-only check-tag does not acquire the mutation lock"
# Invalid source plus held lock proves lock acquisition precedes source reads.
printf 'invalid source\n' > "$FIXTURE_REPO/project.yml"
assert_fails "version mutator checks the lock before parsing the source" "$SCRIPT_DIR/release.sh" next-build --repo "$FIXTURE_REPO"
[[ "$(< "$TEST_ROOT/last-command.log")" == *'another version or build operation'* ]] || fail "version mutator read the invalid source before acquiring the lock"
pass "version mutation cannot read an unlocked source snapshot"
assert_fails "build checks the lock before parsing the source" "$FIXTURE_REPO/scripts/build-pkg.sh"
[[ "$(< "$TEST_ROOT/last-command.log")" == *'another version or build operation'* ]] || fail "build read the invalid source before acquiring the lock"
pass "build cannot read an unlocked source snapshot"
rmdir "$FIXTURE_REPO/.build-pkg.lock"
write_project "$FIXTURE_REPO/project.yml" 1.2.0 7
assert_succeeds "dry-run releases its owned version lock" "$SCRIPT_DIR/release.sh" next-build --dry-run --repo "$FIXTURE_REPO"
[[ ! -e "$FIXTURE_REPO/.build-pkg.lock" ]] || fail "dry-run leaked its lock"
pass "dry-run leaves no mutation lock"

for probe_kind in version build; do
  new_packaging_repo "version-holds-$probe_kind"
  printf 'dist must survive\n' > "$FIXTURE_REPO/dist/sentinel"
  PROBE_LOG="$TEST_ROOT/$probe_kind-lock-probe"
  PROBE_ALIAS="$TEST_ROOT/$probe_kind-repo-alias"
  ln -s "$FIXTURE_REPO" "$PROBE_ALIAS"
  assert_succeeds "version owner excludes a competing $probe_kind operation through a repository alias" \
    env PATH="$FAKE_BIN:$PATH" TEST_VERSION_PROBE="$PROBE_LOG" TEST_PROBE_KIND="$probe_kind" \
    TEST_PROBE_REPO="$PROBE_ALIAS" TEST_RELEASE_CLI="$SCRIPT_DIR/release.sh" \
    "$SCRIPT_DIR/release.sh" next-build --repo "$FIXTURE_REPO"
  assert_equal 1 "$(< "$PROBE_LOG.status")" "competing $probe_kind operation fails while version owner holds the lock"
  assert_equal 8 "$("$SCRIPT_DIR/release.sh" show --build --repo "$FIXTURE_REPO")" "only the owning version operation advances the build"
  assert_equal 'dist must survive' "$(< "$FIXTURE_REPO/dist/sentinel")" "competing $probe_kind operation cannot clear dist"
  [[ ! -e "$FIXTURE_REPO/.build-pkg.lock" ]] || fail "version owner leaked its lock"
  pass "version owner releases its lock after excluding $probe_kind"
done

new_packaging_repo build-holds-version
BUILD_VERSION_PROBE="$TEST_ROOT/build-holds-version-probe"
assert_fails "fake build holds the shared lock during Xcode generation" env PATH="$FAKE_BIN:$PATH" \
  TEST_BUILD_VERSION_PROBE="$BUILD_VERSION_PROBE" TEST_RELEASE_CLI="$SCRIPT_DIR/release.sh" "$FIXTURE_REPO/scripts/build-pkg.sh"
assert_equal 1 "$(< "$BUILD_VERSION_PROBE.status")" "version changes are rejected while a build owns the lock"
assert_equal 7 "$("$SCRIPT_DIR/release.sh" show --build --repo "$FIXTURE_REPO")" "an active build prevents version advancement"
[[ ! -e "$FIXTURE_REPO/.build-pkg.lock" ]] || fail "failed build leaked shared lock"
pass "failed build releases the shared mutation lock"

new_packaging_repo replaced-build-lock
assert_fails "fake build simulates replacement of its owned lock" env PATH="$FAKE_BIN:$PATH" TEST_REPLACE_LOCK=1 "$FIXTURE_REPO/scripts/build-pkg.sh"
[[ -d "$FIXTURE_REPO/.build-pkg.lock" ]] || fail "cleanup removed a replacement lock owned by another operation"
pass "cleanup never removes a replacement lock with a different directory identity"

new_packaging_repo version-project-symlink
ln -s project.yml "$FIXTURE_REPO/linked-project.yml"
VERSION_BEFORE="$(shasum -a 256 "$FIXTURE_REPO/project.yml")"
assert_fails "version mutation refuses a final project symlink" "$SCRIPT_DIR/release.sh" next-build --repo "$FIXTURE_REPO" --project "$FIXTURE_REPO/linked-project.yml"
[[ -L "$FIXTURE_REPO/linked-project.yml" && ! -e "$FIXTURE_REPO/.build-pkg.lock" ]] || fail "symlink rejection rewrote the link or leaked its lock"
assert_equal "$VERSION_BEFORE" "$(shasum -a 256 "$FIXTURE_REPO/project.yml")" "rejected symlink mutation leaves its target unchanged"

printf '1..%d\n' "$TEST_COUNT"
