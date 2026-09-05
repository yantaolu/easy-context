#!/bin/bash
set -euo pipefail

# Offline contract tests for scripts/lib/publish-release.sh. Every GitHub CLI
# operation is handled by the stateful fake below; no token or network is used.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/easycontext-publish-test.XXXXXX")"
cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

REPO="$TEST_ROOT/repo"
FAKE_BIN="$TEST_ROOT/bin"
STATE="$TEST_ROOT/github-state.json"
LOG="$TEST_ROOT/gh.log"
ASSET_DIR="$TEST_ROOT/assets"
OUTPUT="$TEST_ROOT/output.log"
mkdir -p "$REPO/scripts/lib" "$FAKE_BIN" "$ASSET_DIR"
cp "$SCRIPT_DIR/version-lib.sh" "$REPO/scripts/version-lib.sh"
cp "$SCRIPT_DIR/lib/publish-release.sh" "$REPO/scripts/lib/publish-release.sh"

cat > "$REPO/project.yml" <<'EOF'
settings:
  base:
    MARKETING_VERSION: 1.2.0
    CURRENT_PROJECT_VERSION: 7
EOF

cat > "$FAKE_BIN/gh" <<'FAKE_GH'
#!/bin/bash
set -euo pipefail

state="$FAKE_GH_STATE"
log="$FAKE_GH_LOG"
remote_dir="$FAKE_GH_REMOTE_DIR"
printf '%q ' "$@" >> "$log"
printf '\n' >> "$log"

save_jq() {
  local filter="$1"
  shift
  local temporary="${state}.tmp"
  jq "$@" "$filter" "$state" > "$temporary"
  mv "$temporary" "$state"
}

if [[ "$1" == "api" ]]; then
  if [[ -n "${FAKE_GH_API_DENY_FILE:-}" && -e "$FAKE_GH_API_DENY_FILE" ]]; then
    echo 'HTTP 403: Resource not accessible' >&2
    exit 1
  fi
  shift
  endpoint="${!#}"
  case "$endpoint" in
    repos/*/git/ref/tags/*)
      jq -c '.remote_ref' "$state"
      ;;
    repos/*/git/tags/*)
      object_sha="${endpoint##*/}"
      jq -ec --arg sha "$object_sha" '.remote_tags[$sha]' "$state"
      ;;
    repos/*/releases\?per_page=100)
      # `gh api --paginate --slurp` wraps each response page in an array.
      if [[ -n "${FAKE_GH_RELEASE_LIST_FAIL_FILE:-}" && -e "$FAKE_GH_RELEASE_LIST_FAIL_FILE" ]]; then
        echo 'HTTP 503: simulated release listing failure' >&2
        exit 1
      fi
      if [[ -n "${FAKE_GH_RELEASE_LIST_INVALID_FILE:-}" && -e "$FAKE_GH_RELEASE_LIST_INVALID_FILE" ]]; then
        printf '{malformed json\n'
        exit 0
      fi
      if [[ -n "${FAKE_GH_HIDE_PUBLIC_TAG:-}" ]] \
          && jq -e --arg tag "$FAKE_GH_HIDE_PUBLIC_TAG" \
            'any(.releases[]; .tag_name == $tag and .draft == false)' "$state" >/dev/null; then
        jq -c --arg tag "$FAKE_GH_HIDE_PUBLIC_TAG" \
          '[[.releases[] | select(.tag_name != $tag)]]' "$state"
        exit 0
      fi
      jq -c 'if (.page_split // 0) > 0 then [.releases[0:.page_split], .releases[.page_split:]] else [.releases] end' "$state"
      ;;
    repos/*/releases/latest)
      jq -ec '.releases[] | select(.draft == false and .prerelease == false and .is_latest == true)' "$state"
      ;;
    *)
      echo "fake gh: unsupported api endpoint: $endpoint" >&2
      exit 64
      ;;
  esac
  exit 0
fi

[[ "$1" == "release" ]] || { echo "fake gh: unsupported command: $1" >&2; exit 64; }
subcommand="$2"
tag="$3"
shift 3

case "$subcommand" in
  create)
    notes_file=''
    while (( $# )); do
      case "$1" in
        --notes-file) notes_file="$2"; shift 2 ;;
        --title) shift 2 ;;
        --verify-tag|--draft|--latest=false|--generate-notes) shift ;;
        *) echo "fake gh: unsupported release create argument: $1" >&2; exit 64 ;;
      esac
    done
    [[ -n "$notes_file" && -f "$notes_file" ]] || exit 64
    [[ "$(jq --arg tag "$tag" '[.releases[] | select(.tag_name == $tag)] | length' "$state")" == 0 ]] || exit 1
    body="$(cat "$notes_file")"
    save_jq '.next_id as $id | .next_id += 1 | .releases += [{id: $id, tag_name: $tag, draft: true, prerelease: false, body: $body, assets: [], is_latest: false}]' \
      --arg tag "$tag" --arg body "$body"
    ;;
  upload)
    file="$1"
    [[ -f "$file" ]] || exit 64
    name="$(basename "$file")"
    upload_number="$(jq '.upload_count + 1' "$state")"
    save_jq '.upload_count = $count' --argjson count "$upload_number"
    if [[ -n "${FAKE_GH_UPLOAD_FAIL_AT:-}" && "$upload_number" == "$FAKE_GH_UPLOAD_FAIL_AT" && ! -e "${FAKE_GH_UPLOAD_FAILURE_USED:-/nonexistent}" ]]; then
      : > "$FAKE_GH_UPLOAD_FAILURE_USED"
      echo 'simulated upload failure' >&2
      exit 1
    fi
    [[ "$(jq --arg tag "$tag" --arg name "$name" '[.releases[] | select(.tag_name == $tag) | .assets[] | select(.name == $name)] | length' "$state")" == 0 ]] || exit 1
    digest="sha256:$(shasum -a 256 "$file" | awk '{print $1}')"
    size="$(wc -c < "$file" | tr -d '[:space:]')"
    mkdir -p "$remote_dir/$tag"
    cp "$file" "$remote_dir/$tag/$name"
    save_jq '(.releases[] | select(.tag_name == $tag) | .assets) += [{name: $name, state: "uploaded", size: $size, digest: $digest}]' \
      --arg tag "$tag" --arg name "$name" --arg digest "$digest" --argjson size "$size"
    ;;
  download)
    pattern=''
    destination=''
    while (( $# )); do
      case "$1" in
        --pattern) pattern="$2"; shift 2 ;;
        --dir) destination="$2"; shift 2 ;;
        *) echo "fake gh: unsupported release download argument: $1" >&2; exit 64 ;;
      esac
    done
    [[ -n "$pattern" && -n "$destination" && -f "$remote_dir/$tag/$pattern" ]] || exit 1
    [[ ! -e "$destination/$pattern" ]] || exit 1
    cp "$remote_dir/$tag/$pattern" "$destination/$pattern"
    if [[ -n "${FAKE_GH_MOVE_TAG_ON_COMPLETE_DRAFT:-}" ]] \
        && jq -e --arg tag "$tag" \
          'any(.releases[]; .tag_name == $tag and .draft == true and (.assets | length) == 4)' \
          "$state" >/dev/null; then
      save_jq '.remote_tags[.remote_ref.object.sha].object.sha = $sha' \
        --arg sha "$FAKE_GH_MOVE_TAG_ON_COMPLETE_DRAFT"
    fi
    ;;
  edit)
    draft_value=''
    latest_value=''
    while (( $# )); do
      case "$1" in
        --draft=false) draft_value=false; shift ;;
        --latest=false) latest_value=false; shift ;;
        --latest) latest_value=true; shift ;;
        *) echo "fake gh: unsupported release edit argument: $1" >&2; exit 64 ;;
      esac
    done
    [[ "$(jq --arg tag "$tag" '[.releases[] | select(.tag_name == $tag)] | length' "$state")" == 1 ]] || exit 1
    if [[ "$latest_value" == true && -n "${FAKE_GH_FAIL_LATEST_ONCE_FILE:-}" && ! -e "$FAKE_GH_FAIL_LATEST_ONCE_FILE" ]]; then
      : > "$FAKE_GH_FAIL_LATEST_ONCE_FILE"
      echo 'simulated Latest edit failure' >&2
      exit 1
    fi
    if [[ "$draft_value" == false ]]; then
      save_jq '(.releases[] | select(.tag_name == $tag) | .draft) = false' --arg tag "$tag"
    fi
    if [[ "$latest_value" == true ]]; then
      save_jq '.releases[].is_latest = false | (.releases[] | select(.tag_name == $tag) | .is_latest) = true' --arg tag "$tag"
    elif [[ "$latest_value" == false ]]; then
      save_jq '(.releases[] | select(.tag_name == $tag) | .is_latest) = false' --arg tag "$tag"
    fi
    ;;
  *)
    echo "fake gh: unsupported release subcommand: $subcommand" >&2
    exit 64
    ;;
esac
FAKE_GH
chmod +x "$FAKE_BIN/gh"

git -C "$REPO" init -q
git -C "$REPO" add project.yml scripts
git -C "$REPO" \
  -c user.name='Release Test' \
  -c user.email='release-test@example.invalid' \
  -c commit.gpgsign=false \
  -c core.hooksPath=/dev/null \
  commit -qm 'fixture'
TAG='v1.2.0'
VERSION='1.2.0'
BUILD_NUMBER='7'
EXPECTED_SHA="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" \
  -c user.name='Release Test' \
  -c user.email='release-test@example.invalid' \
  -c tag.gpgSign=false \
  -c core.hooksPath=/dev/null \
  tag -a "$TAG" -m "$TAG"
TAG_OBJECT_SHA="$(git -C "$REPO" rev-parse "$TAG^{tag}")"
git -C "$REPO" checkout -q --detach "$TAG"

write_assets() {
  local flavor="${1:-original}"
  local arch pkg
  mkdir -p "$ASSET_DIR"
  for arch in arm64 x86_64; do
    pkg="$ASSET_DIR/EasyContext-${VERSION}-macOS-${arch}.pkg"
    printf 'fixture package: %s: %s\n' "$arch" "$flavor" > "$pkg"
    (cd "$ASSET_DIR" && shasum -a 256 "$(basename "$pkg")" > "$(basename "$pkg").sha256")
  done
}

reset_state() {
  jq -n \
    --arg tag_object "$TAG_OBJECT_SHA" \
    --arg commit "$EXPECTED_SHA" '
      {
        remote_ref: {object: {type: "tag", sha: $tag_object}},
        remote_tags: {($tag_object): {object: {type: "commit", sha: $commit}}},
        next_id: 1,
        upload_count: 0,
        releases: []
      }
    ' > "$STATE"
  : > "$LOG"
  rm -rf "$TEST_ROOT/remote-assets"
  mkdir -p "$TEST_ROOT/remote-assets"
  rm -f "$TEST_ROOT/api-deny" "$TEST_ROOT/upload-failed" "$TEST_ROOT/latest-failed"
  rm -f "$TEST_ROOT/list-failed" "$TEST_ROOT/list-invalid"
  unset FAKE_GH_API_DENY_FILE FAKE_GH_RELEASE_LIST_FAIL_FILE FAKE_GH_RELEASE_LIST_INVALID_FILE || true
  unset FAKE_GH_HIDE_PUBLIC_TAG FAKE_GH_MOVE_TAG_ON_COMPLETE_DRAFT || true
  unset FAKE_GH_UPLOAD_FAIL_AT FAKE_GH_UPLOAD_FAILURE_USED FAKE_GH_FAIL_LATEST_ONCE_FILE || true
  write_assets original
}

run_release_script() {
  local mode="$1"
  (
    cd "$REPO"
    PATH="$FAKE_BIN:$PATH" \
    GH_TOKEN='offline-test-token' \
    GH_REPO='example/easy-context' \
    TAG="$TAG" \
    VERSION="$VERSION" \
    BUILD_NUMBER="$BUILD_NUMBER" \
    EXPECTED_SHA="$EXPECTED_SHA" \
    RELEASE_DIR="$ASSET_DIR" \
    FAKE_GH_STATE="$STATE" \
    FAKE_GH_LOG="$LOG" \
    FAKE_GH_REMOTE_DIR="$TEST_ROOT/remote-assets" \
    FAKE_GH_API_DENY_FILE="${FAKE_GH_API_DENY_FILE:-}" \
    FAKE_GH_RELEASE_LIST_FAIL_FILE="${FAKE_GH_RELEASE_LIST_FAIL_FILE:-}" \
    FAKE_GH_RELEASE_LIST_INVALID_FILE="${FAKE_GH_RELEASE_LIST_INVALID_FILE:-}" \
    FAKE_GH_HIDE_PUBLIC_TAG="${FAKE_GH_HIDE_PUBLIC_TAG:-}" \
    FAKE_GH_MOVE_TAG_ON_COMPLETE_DRAFT="${FAKE_GH_MOVE_TAG_ON_COMPLETE_DRAFT:-}" \
    FAKE_GH_UPLOAD_FAIL_AT="${FAKE_GH_UPLOAD_FAIL_AT:-}" \
    FAKE_GH_UPLOAD_FAILURE_USED="${FAKE_GH_UPLOAD_FAILURE_USED:-}" \
    FAKE_GH_FAIL_LATEST_ONCE_FILE="${FAKE_GH_FAIL_LATEST_ONCE_FILE:-}" \
    bash ./scripts/lib/publish-release.sh "$mode"
  )
}

run_publish() {
  run_release_script publish
}

run_inspect() {
  run_release_script inspect
}

pass_count=0
pass() {
  pass_count=$((pass_count + 1))
  printf 'ok %d - %s\n' "$pass_count" "$1"
}

assert_jq() {
  local expression="$1"
  jq -e "$expression" "$STATE" >/dev/null || {
    echo "assertion failed: $expression" >&2
    jq . "$STATE" >&2
    exit 1
  }
}

expect_failure() {
  local description="$1"
  local expected_message="$2"
  if run_publish > "$OUTPUT" 2>&1; then
    echo "expected failure: $description" >&2
    exit 1
  fi
  grep -F "$expected_message" "$OUTPUT" >/dev/null || {
    echo "failure did not contain expected message: $expected_message" >&2
    cat "$OUTPUT" >&2
    exit 1
  }
  pass "$description"
}

# A new tag produces exactly one managed public release and four assets.
reset_state
run_publish > "$OUTPUT"
assert_jq '.releases | length == 1'
assert_jq '.releases[0].draft == false and .releases[0].is_latest == true and (.releases[0].assets | length == 4)'
assert_jq '.releases[0].body | contains("easycontext-release-provenance:v1")'
PUBLIC_BASELINE="$TEST_ROOT/public-baseline.json"
PUBLIC_REMOTE="$TEST_ROOT/public-remote-assets"
cp "$STATE" "$PUBLIC_BASELINE"
cp -R "$TEST_ROOT/remote-assets" "$PUBLIC_REMOTE"
pass 'new release is created, verified, published, and selected as Latest'

restore_public_baseline() {
  cp "$PUBLIC_BASELINE" "$STATE"
  rm -rf "$TEST_ROOT/remote-assets"
  cp -R "$PUBLIC_REMOTE" "$TEST_ROOT/remote-assets"
}

reset_state
assert_equal() {
  local expected="$1" actual="$2" description="$3"
  [[ "$expected" == "$actual" ]] || {
    echo "assertion failed: $description (expected '$expected', got '$actual')" >&2
    exit 1
  }
  pass "$description"
}
assert_equal 'needs_artifacts=true' "$(run_inspect)" \
  'inspect requests workflow artifacts when no release exists'

# Classification is advisory only: the publishing invocation must safely
# re-read a state that changed between workflow steps.
restore_public_baseline
rm -rf "$ASSET_DIR"
run_publish > "$OUTPUT"
assert_jq '.releases[0].draft == false and .releases[0].is_latest == true'
pass 'missing-to-public state change is remotely verified without asset replacement'

restore_public_baseline
rm -rf "$ASSET_DIR"
assert_equal 'needs_artifacts=false' "$(run_inspect)" \
  'inspect skips expired workflow artifacts for an intact public release'
jq '(.releases[0].draft) = true' "$STATE" > "${STATE}.tmp"
mv "${STATE}.tmp" "$STATE"
expect_failure 'public-to-draft state change cannot bypass missing original artifacts' \
  'release asset directory does not exist'

restore_public_baseline
rm -rf "$ASSET_DIR"
run_publish > "$OUTPUT"
assert_jq '.releases[0].draft == false and .releases[0].is_latest == true'
pass 'public Latest recovery succeeds without local workflow artifacts'

# Upload failure leaves a recoverable draft; retry skips the existing good asset.
reset_state
export FAKE_GH_UPLOAD_FAIL_AT=2
export FAKE_GH_UPLOAD_FAILURE_USED="$TEST_ROOT/upload-failed"
expect_failure 'partial upload failure remains visible as a failure' 'simulated upload failure'
assert_jq '.releases[0].draft == true and (.releases[0].assets | length == 1)'
assert_equal 'needs_artifacts=true' "$(run_inspect)" \
  'inspect keeps original workflow artifacts mandatory for a managed draft'
unset FAKE_GH_UPLOAD_FAIL_AT
run_publish > "$OUTPUT"
assert_jq '.releases[0].draft == false and (.releases[0].assets | length == 4)'
[[ "$(grep -c 'release upload.*EasyContext-1.2.0-macOS-arm64.pkg ' "$LOG")" == 1 ]]
pass 'managed partial draft resumes without clobbering an uploaded asset'

# A managed draft is tied to the original artifact bytes.
reset_state
export FAKE_GH_UPLOAD_FAIL_AT=2
export FAKE_GH_UPLOAD_FAILURE_USED="$TEST_ROOT/upload-failed"
if run_publish > "$OUTPUT" 2>&1; then exit 1; fi
unset FAKE_GH_UPLOAD_FAIL_AT
write_assets rebuilt
expect_failure 'draft recovery rejects rebuilt artifact bytes' 'original artifact bytes'

reset_state
export FAKE_GH_UPLOAD_FAIL_AT=2
export FAKE_GH_UPLOAD_FAILURE_USED="$TEST_ROOT/upload-failed"
if run_publish > "$OUTPUT" 2>&1; then exit 1; fi
unset FAKE_GH_UPLOAD_FAIL_AT
rm -rf "$ASSET_DIR"
assert_equal 'needs_artifacts=true' "$(run_inspect)" \
  'managed draft remains classified as requiring original artifacts'
expect_failure 'managed draft cannot resume after local artifacts expire' \
  'release asset directory does not exist'

# A public managed release is verified remotely and ignores rebuilt local bytes.
restore_public_baseline
write_assets rebuilt
jq '(.releases[].assets[].digest) = null' "$STATE" > "${STATE}.tmp"
mv "${STATE}.tmp" "$STATE"
run_publish > "$OUTPUT"
assert_jq '.releases[0].draft == false and .releases[0].is_latest == true'
[[ "$(grep -c '^release upload' "$LOG" || true)" == 0 ]]
pass 'public rerun validates original remote provenance without replacing assets'

# Publishing may succeed before Latest coordination; a rerun repairs that state.
reset_state
export FAKE_GH_FAIL_LATEST_ONCE_FILE="$TEST_ROOT/latest-failed"
expect_failure 'Latest edit failure is reported after safe publication' 'simulated Latest edit failure'
assert_jq '.releases[0].draft == false and .releases[0].is_latest == false'
run_publish > "$OUTPUT"
assert_jq '.releases[0].is_latest == true'
pass 'public managed rerun resumes Latest coordination'
unset FAKE_GH_FAIL_LATEST_ONCE_FILE

# Completing an older release must preserve a newer stable release as Latest.
reset_state
jq '.releases += [{id: 99, tag_name: "v1.3.0", draft: false, prerelease: false, body: "newer", assets: [], is_latest: true}]' "$STATE" > "${STATE}.tmp"
mv "${STATE}.tmp" "$STATE"
run_publish > "$OUTPUT"
assert_jq '(.releases[] | select(.tag_name == "v1.3.0") | .is_latest) == true'
assert_jq '(.releases[] | select(.tag_name == "v1.2.0") | .is_latest) == false'
pass 'older release completion cannot move Latest backward'

# API/auth failures are not treated as a missing Release.
reset_state
: > "$TEST_ROOT/api-deny"
export FAKE_GH_API_DENY_FILE="$TEST_ROOT/api-deny"
expect_failure 'API authorization failure fails closed' 'failed to read remote tag ref'
assert_jq '.releases | length == 0'
unset FAKE_GH_API_DENY_FILE

reset_state
: > "$TEST_ROOT/list-failed"
export FAKE_GH_RELEASE_LIST_FAIL_FILE="$TEST_ROOT/list-failed"
expect_failure 'release-list API failure cannot be mistaken for absence' 'refusing to infer absence from an API failure'
assert_jq '.releases | length == 0'
unset FAKE_GH_RELEASE_LIST_FAIL_FILE

reset_state
: > "$TEST_ROOT/list-invalid"
export FAKE_GH_RELEASE_LIST_INVALID_FILE="$TEST_ROOT/list-invalid"
expect_failure 'malformed release-list response cannot create a release' 'pagination returned malformed JSON'
assert_jq '.releases | length == 0'
unset FAKE_GH_RELEASE_LIST_INVALID_FILE

reset_state
jq '.releases = [{id: 55, tag_name: 123, draft: false, prerelease: false, assets: []}]' \
  "$STATE" > "${STATE}.tmp"
mv "${STATE}.tmp" "$STATE"
expect_failure 'malformed release record fails closed' 'pagination returned malformed JSON'

# Existing but unmanaged/mismatched drafts are never adopted.
reset_state
jq '.releases = [{id: 1, tag_name: "v1.2.0", draft: true, prerelease: false, body: "legacy draft", assets: [], is_latest: false}]' "$STATE" > "${STATE}.tmp"
mv "${STATE}.tmp" "$STATE"
expect_failure 'unmanaged draft is rejected' 'not managed by the expected provenance schema'

restore_public_baseline
jq '(.releases[0].body) |= gsub("example/easy-context"; "other/repository")' "$STATE" > "${STATE}.tmp"
mv "${STATE}.tmp" "$STATE"
expect_failure 'managed provenance identity conflict is rejected' 'provenance marker conflicts'

reset_state
jq --arg other '0000000000000000000000000000000000000000' '.remote_tags[.remote_ref.object.sha].object.sha = $other' "$STATE" > "${STATE}.tmp"
mv "${STATE}.tmp" "$STATE"
expect_failure 'remote tag commit conflict is rejected' 'remote tag v1.2.0 resolves to'

reset_state
export FAKE_GH_MOVE_TAG_ON_COMPLETE_DRAFT='0000000000000000000000000000000000000000'
expect_failure 'remote tag moved before publication is rejected' 'remote tag v1.2.0 resolves to'
assert_jq '.releases[0].draft == true'
unset FAKE_GH_MOVE_TAG_ON_COMPLETE_DRAFT

# Pagination and numeric ordering must ignore draft/prerelease candidates.
reset_state
jq '.page_split = 2 | .releases = [
  {id: 90, tag_name: "v99.0.0", draft: true, prerelease: false, body: "draft", assets: [], is_latest: false},
  {id: 91, tag_name: "v100.0.0", draft: false, prerelease: true, body: "prerelease", assets: [], is_latest: false},
  {id: 92, tag_name: "v1.10.0", draft: false, prerelease: false, body: "newer", assets: [], is_latest: true}
]' "$STATE" > "${STATE}.tmp"
mv "${STATE}.tmp" "$STATE"
run_publish > "$OUTPUT"
assert_jq '(.releases[] | select(.tag_name == "v1.10.0") | .is_latest) == true'
assert_jq '(.releases[] | select(.tag_name == "v1.2.0") | .is_latest) == false'
pass 'paginated stable releases use numeric ordering and exclude draft/prerelease tags'

reset_state
jq '.releases = [{id: 93, tag_name: "v9223372036854775808.0.0", draft: false, prerelease: false, body: "overflow", assets: [], is_latest: true}]' "$STATE" > "${STATE}.tmp"
mv "${STATE}.tmp" "$STATE"
expect_failure 'stable-looking version overflow fails closed' \
  'exceeds the supported numeric version range'

# If the list endpoint omits the just-published tag, Latest coordination must
# fail rather than accepting the previous release as a coherent final state.
reset_state
jq '.releases = [{id: 99, tag_name: "v1.1.0", draft: false, prerelease: false, body: "older", assets: [], is_latest: true}]' "$STATE" > "${STATE}.tmp"
mv "${STATE}.tmp" "$STATE"
export FAKE_GH_HIDE_PUBLIC_TAG='v1.2.0'
expect_failure 'Latest coordination rejects a list missing the current public tag' \
  'must appear exactly once as a public stable Release'
assert_jq '(.releases[] | select(.tag_name == "v1.2.0") | .draft) == false'
assert_jq '(.releases[] | select(.tag_name == "v1.2.0") | .is_latest) == false'
assert_jq '(.releases[] | select(.tag_name == "v1.1.0") | .is_latest) == true'
unset FAKE_GH_HIDE_PUBLIC_TAG

# Integrity failures on an already public managed release all fail closed.
restore_public_baseline
jq '(.releases[0].assets[0].digest) = "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' "$STATE" > "${STATE}.tmp"
mv "${STATE}.tmp" "$STATE"
expect_failure 'remote asset hash mismatch is rejected' 'digest does not match provenance'

restore_public_baseline
jq '(.releases[0].assets[0].digest) = null' "$STATE" > "${STATE}.tmp"
mv "${STATE}.tmp" "$STATE"
printf 'tampered remote bytes\n' > "$TEST_ROOT/remote-assets/v1.2.0/EasyContext-1.2.0-macOS-arm64.pkg"
expect_failure 'downloaded remote bytes mismatch is rejected without digest metadata' 'downloaded remote asset hash does not match provenance'

restore_public_baseline
jq '(.releases[0].assets[0].size) += 1' "$STATE" > "${STATE}.tmp"
mv "${STATE}.tmp" "$STATE"
expect_failure 'remote asset size mismatch is rejected' 'does not match provenance'

restore_public_baseline
jq '.releases[0].assets = .releases[0].assets[0:3]' "$STATE" > "${STATE}.tmp"
mv "${STATE}.tmp" "$STATE"
expect_failure 'public release missing an asset is rejected' 'has 3 of 4 required assets'

restore_public_baseline
jq '.releases[0].assets[0].name = "unexpected.pkg"' "$STATE" > "${STATE}.tmp"
mv "${STATE}.tmp" "$STATE"
expect_failure 'unknown remote asset is rejected' 'contains unknown asset'

printf '1..%d\n' "$pass_count"
