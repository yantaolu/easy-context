#!/bin/bash
set -euo pipefail

# Internal GitHub Actions entry point. This is deliberately not a maintainer CLI:
# it reconciles exactly one tag's draft/public Release from immutable workflow
# artifacts and fails closed on any state it cannot prove safe.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=scripts/version-lib.sh
source "$REPO_ROOT/scripts/version-lib.sh"

die() {
  printf 'publish-release: %s\n' "$*" >&2
  exit 1
}

for command_name in gh git jq shasum awk sed wc; do
  command -v "$command_name" >/dev/null 2>&1 || die "required command is missing: $command_name"
done

: "${GH_REPO:?GH_REPO is required}"
: "${TAG:?TAG is required}"
: "${VERSION:?VERSION is required}"
: "${BUILD_NUMBER:?BUILD_NUMBER is required}"
: "${EXPECTED_SHA:?EXPECTED_SHA is required}"
MODE="${1:-publish}"
[[ $# -le 1 && ( "$MODE" == "inspect" || "$MODE" == "publish" ) ]] \
  || die "usage: publish-release.sh [inspect|publish]"
if [[ "$MODE" == "publish" ]]; then
  : "${RELEASE_DIR:?RELEASE_DIR is required}"
fi

[[ "$GH_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "invalid GH_REPO: $GH_REPO"
[[ "$TAG" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] \
  || die "TAG must use strict vX.Y.Z form: $TAG"
ec_is_marketing_version "$VERSION" || die "invalid VERSION: $VERSION"
ec_is_build_number "$BUILD_NUMBER" || die "invalid BUILD_NUMBER: $BUILD_NUMBER"
[[ "$TAG" == "v$VERSION" ]] || die "TAG $TAG does not match VERSION $VERSION"
[[ "$EXPECTED_SHA" =~ ^[0-9a-fA-F]{40}$ ]] || die "EXPECTED_SHA must be a full 40-character commit SHA"
EXPECTED_SHA="$(printf '%s' "$EXPECTED_SHA" | tr '[:upper:]' '[:lower:]')"

ec_read_project_version "$REPO_ROOT/project.yml"
[[ "$EC_MARKETING_VERSION" == "$VERSION" ]] \
  || die "tag source version $EC_MARKETING_VERSION does not match expected $VERSION"
[[ "$EC_BUILD_NUMBER" == "$BUILD_NUMBER" ]] \
  || die "tag source build $EC_BUILD_NUMBER does not match expected $BUILD_NUMBER"

LOCAL_TAG_SHA="$(git -C "$REPO_ROOT" rev-parse "$TAG^{commit}" 2>/dev/null)" \
  || die "cannot dereference local tag $TAG to a commit"
LOCAL_HEAD_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)" \
  || die "cannot resolve local HEAD"
LOCAL_TAG_SHA="$(printf '%s' "$LOCAL_TAG_SHA" | tr '[:upper:]' '[:lower:]')"
LOCAL_HEAD_SHA="$(printf '%s' "$LOCAL_HEAD_SHA" | tr '[:upper:]' '[:lower:]')"
[[ "$LOCAL_TAG_SHA" == "$EXPECTED_SHA" ]] \
  || die "local tag $TAG resolves to $LOCAL_TAG_SHA, expected $EXPECTED_SHA"
[[ "$LOCAL_HEAD_SHA" == "$EXPECTED_SHA" ]] \
  || die "checkout HEAD $LOCAL_HEAD_SHA does not match tag commit $EXPECTED_SHA"

WORK_DIR="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/easycontext-publish.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

gh_api() {
  gh api -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' "$@"
}

remote_tag_commit() {
  local object_json="$WORK_DIR/remote-tag-object.json"
  local object_type object_sha depth

  if ! gh_api "repos/$GH_REPO/git/ref/tags/$TAG" > "$object_json"; then
    die "failed to read remote tag ref $TAG"
  fi
  object_type="$(jq -er '.object.type' "$object_json")" \
    || die "remote tag ref has no object type"
  object_sha="$(jq -er '.object.sha' "$object_json")" \
    || die "remote tag ref has no object SHA"

  depth=0
  while [[ "$object_type" == "tag" ]]; do
    depth=$((depth + 1))
    (( depth <= 8 )) || die "remote annotated tag chain is unexpectedly deep"
    if ! gh_api "repos/$GH_REPO/git/tags/$object_sha" > "$object_json"; then
      die "failed to dereference remote annotated tag object $object_sha"
    fi
    object_type="$(jq -er '.object.type' "$object_json")" \
      || die "remote annotated tag object has no target type"
    object_sha="$(jq -er '.object.sha' "$object_json")" \
      || die "remote annotated tag object has no target SHA"
  done
  [[ "$object_type" == "commit" ]] || die "remote tag resolves to unsupported object type: $object_type"
  [[ "$object_sha" =~ ^[0-9a-fA-F]{40}$ ]] || die "remote tag resolved to an invalid commit SHA"
  printf '%s\n' "$object_sha" | tr '[:upper:]' '[:lower:]'
}

assert_remote_tag_commit() {
  local remote_tag_sha
  remote_tag_sha="$(remote_tag_commit)"
  [[ "$remote_tag_sha" == "$EXPECTED_SHA" ]] \
    || die "remote tag $TAG resolves to $remote_tag_sha, expected $EXPECTED_SHA"
}

assert_remote_tag_commit

PAGES_FILE="$WORK_DIR/releases-pages.json"
RELEASE_FILE="$WORK_DIR/release.json"

fetch_release_pages() {
  local destination="$1"
  if ! gh_api --paginate --slurp "repos/$GH_REPO/releases?per_page=100" > "$destination"; then
    die "failed to list GitHub Releases; refusing to infer absence from an API failure"
  fi
  jq -e '
    type == "array" and
    all(.[]; type == "array") and
    all(.[][];
      type == "object" and
      (.tag_name | type == "string") and
      (.draft | type == "boolean") and
      (.prerelease | type == "boolean"))
  ' "$destination" >/dev/null \
    || die "GitHub Releases pagination returned malformed JSON"
}

load_release() {
  local count
  fetch_release_pages "$PAGES_FILE"
  count="$(jq --arg tag "$TAG" '[.[][] | select(.tag_name == $tag)] | length' "$PAGES_FILE")"
  [[ "$count" == "0" || "$count" == "1" ]] \
    || die "multiple Releases unexpectedly use tag $TAG"
  if [[ "$count" == "0" ]]; then
    RELEASE_FOUND=false
    : > "$RELEASE_FILE"
    return
  fi
  jq -e -c --arg tag "$TAG" \
    '.[][] | select(.tag_name == $tag)' "$PAGES_FILE" > "$RELEASE_FILE" \
    || die "could not select Release $TAG from API response"
  jq -e '
    (.id | type == "number") and
    (.tag_name | type == "string") and
    (.draft | type == "boolean") and
    (.prerelease | type == "boolean") and
    (.assets | type == "array")
  ' "$RELEASE_FILE" >/dev/null || die "Release $TAG has malformed fields"
  RELEASE_FOUND=true
}

required_assets=(
  "EasyContext-${VERSION}-macOS-arm64.pkg"
  "EasyContext-${VERSION}-macOS-arm64.pkg.sha256"
  "EasyContext-${VERSION}-macOS-x86_64.pkg"
  "EasyContext-${VERSION}-macOS-x86_64.pkg.sha256"
)
REQUIRED_NAMES_JSON="$(printf '%s\n' "${required_assets[@]}" | jq -R . | jq -sc .)"

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

file_size() {
  wc -c < "$1" | tr -d '[:space:]'
}

LOCAL_MARKER_FILE="$WORK_DIR/local-marker.json"
BODY_FILE="$WORK_DIR/release-notes.md"

prepare_local_assets() {
  local name path pkg checksum local_names_json expected_checksum_line actual_checksum_line
  local assets_json='[]'

  [[ -d "$RELEASE_DIR" ]] || die "release asset directory does not exist: $RELEASE_DIR"
  for name in "${required_assets[@]}"; do
    path="$RELEASE_DIR/$name"
    [[ -f "$path" && -s "$path" ]] || die "missing or empty release asset: $path"
    assets_json="$(jq -cS \
      --arg name "$name" \
      --arg sha256 "$(sha256_file "$path")" \
      --arg size "$(file_size "$path")" \
      '. + [{name: $name, sha256: $sha256, size: $size}]' <<< "$assets_json")"
  done

  local_names_json="$(find "$RELEASE_DIR" -maxdepth 1 -type f -print \
    | sed 's#^.*/##' | LC_ALL=C sort | jq -R . | jq -sc .)"
  [[ "$(jq -cS . <<< "$local_names_json")" == "$(jq -cS . <<< "$REQUIRED_NAMES_JSON")" ]] \
    || die "release directory must contain exactly the four expected assets"

  for pkg in \
    "EasyContext-${VERSION}-macOS-arm64.pkg" \
    "EasyContext-${VERSION}-macOS-x86_64.pkg"; do
    checksum="$pkg.sha256"
    expected_checksum_line="$(sha256_file "$RELEASE_DIR/$pkg")  $pkg"
    actual_checksum_line="$(cat "$RELEASE_DIR/$checksum")"
    awk 'END { exit (NR == 1 ? 0 : 1) }' "$RELEASE_DIR/$checksum" \
      || die "checksum file must contain exactly one line: $checksum"
    [[ "$actual_checksum_line" == "$expected_checksum_line" ]] \
      || die "checksum file must contain exactly the canonical hash and package name: $checksum"
    (cd "$RELEASE_DIR" && shasum -a 256 -c "$checksum" >/dev/null) \
      || die "checksum file does not verify package: $checksum"
  done

  jq -cnS \
    --arg schema 'easycontext-release-provenance/v1' \
    --arg repository "$GH_REPO" \
    --arg tag "$TAG" \
    --arg commit "$EXPECTED_SHA" \
    --arg build "$BUILD_NUMBER" \
    --argjson assets "$assets_json" \
    '{schema: $schema, repository: $repository, tag: $tag, commit: $commit, build: $build, assets: $assets}' \
    > "$LOCAL_MARKER_FILE"

  cat > "$BODY_FILE" <<EOF
⚠️ 此 Release 的 .pkg 未签名；其中的 App 使用 ad-hoc 签名且未经过 Apple 公证。首次安装或打开时 macOS 可能显示安全警告；请仅从本 Release 下载。

下载选择：Apple Silicon（M 系列）Mac 请下载 \`EasyContext-<版本>-macOS-arm64.pkg\`；Intel Mac 请下载 \`EasyContext-<版本>-macOS-x86_64.pkg\`。

<!-- easycontext-release-provenance:v1
$(cat "$LOCAL_MARKER_FILE")
-->
EOF
}

REMOTE_MARKER_FILE="$WORK_DIR/remote-marker.json"

extract_and_validate_remote_marker() {
  local body_file="$WORK_DIR/release-body.md"
  local extracted_file="$WORK_DIR/extracted-marker.json"
  local expected_mode="$1"

  jq -r '.body // ""' "$RELEASE_FILE" > "$body_file"
  if ! awk '
    $0 == "<!-- easycontext-release-provenance:v1" {
      if (inside) exit 2
      inside = 1
      openings++
      next
    }
    inside && $0 == "-->" {
      inside = 0
      closings++
      next
    }
    inside { print }
    END {
      if (inside || openings != 1 || closings != 1) exit 3
    }
  ' "$body_file" > "$extracted_file"; then
    die "Release $TAG is not managed by the expected provenance schema"
  fi
  jq -e -cS . "$extracted_file" > "$REMOTE_MARKER_FILE" \
    || die "Release $TAG provenance marker is not valid JSON"

  jq -e \
    --arg schema 'easycontext-release-provenance/v1' \
    --arg repository "$GH_REPO" \
    --arg tag "$TAG" \
    --arg commit "$EXPECTED_SHA" \
    --arg build "$BUILD_NUMBER" \
    --argjson names "$REQUIRED_NAMES_JSON" '
      .schema == $schema and
      .repository == $repository and
      .tag == $tag and
      .commit == $commit and
      .build == $build and
      (.assets | type == "array" and length == 4) and
      ([.assets[].name] | sort) == ($names | sort) and
      ([.assets[].name] | unique | length) == 4 and
      all(.assets[];
        (.sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
        (.size | type == "string" and test("^[1-9][0-9]*$")))
    ' "$REMOTE_MARKER_FILE" >/dev/null \
    || die "Release $TAG provenance marker conflicts with repository, tag, commit, build, or asset schema"

  if [[ "$expected_mode" == "draft" ]] && ! cmp -s "$LOCAL_MARKER_FILE" "$REMOTE_MARKER_FILE"; then
    die "managed draft provenance does not match this workflow's original artifact bytes"
  fi
}

validate_remote_assets() {
  local completeness="$1"
  local remote_count unique_count
  local name state size digest expected_hash expected_size
  local download_dir downloaded_path downloaded_hash downloaded_size

  download_dir="$(mktemp -d "$WORK_DIR/remote-assets.XXXXXX")"

  remote_count="$(jq '.assets | length' "$RELEASE_FILE")"
  unique_count="$(jq '[.assets[].name] | unique | length' "$RELEASE_FILE")"
  [[ "$remote_count" == "$unique_count" ]] || die "Release $TAG has duplicate asset names"
  (( remote_count <= 4 )) || die "Release $TAG has unexpected extra assets"

  while IFS=$'\t' read -r name state size digest; do
    [[ -n "$name" ]] || continue
    if ! jq -e --arg name "$name" 'index($name) != null' <<< "$REQUIRED_NAMES_JSON" >/dev/null; then
      die "Release $TAG contains unknown asset: $name"
    fi
    expected_hash="$(jq -er --arg name "$name" '.assets[] | select(.name == $name) | .sha256' "$REMOTE_MARKER_FILE")" \
      || die "provenance has no hash for asset $name"
    expected_size="$(jq -er --arg name "$name" '.assets[] | select(.name == $name) | .size' "$REMOTE_MARKER_FILE")" \
      || die "provenance has no size for asset $name"
    [[ "$state" == "uploaded" ]] || die "asset $name is not in uploaded state: $state"
    [[ "$size" == "$expected_size" ]] \
      || die "asset $name size $size does not match provenance $expected_size"
    if [[ -n "$digest" ]]; then
      [[ "$digest" == "sha256:$expected_hash" ]] \
        || die "asset $name digest does not match provenance"
    fi
    if ! gh release download "$TAG" --pattern "$name" --dir "$download_dir" >/dev/null; then
      die "failed to download remote asset for verification: $name"
    fi
    downloaded_path="$download_dir/$name"
    [[ -f "$downloaded_path" && ! -L "$downloaded_path" ]] \
      || die "downloaded remote asset is missing or not a regular file: $name"
    downloaded_hash="$(sha256_file "$downloaded_path")"
    downloaded_size="$(file_size "$downloaded_path")"
    [[ "$downloaded_hash" == "$expected_hash" ]] \
      || die "downloaded remote asset hash does not match provenance: $name"
    [[ "$downloaded_size" == "$expected_size" ]] \
      || die "downloaded remote asset size does not match provenance: $name"
  done < <(jq -r '.assets[] | [.name, .state, (.size | tostring), (.digest // "")] | @tsv' "$RELEASE_FILE")

  if [[ "$completeness" == "complete" && "$remote_count" != "4" ]]; then
    die "Release $TAG has $remote_count of 4 required assets"
  fi
}

upload_missing_assets() {
  local name
  for name in "${required_assets[@]}"; do
    if jq -e --arg name "$name" '.assets[] | select(.name == $name)' "$RELEASE_FILE" >/dev/null; then
      continue
    fi
    printf 'Uploading missing asset: %s\n' "$name"
    gh release upload "$TAG" "$RELEASE_DIR/$name"
  done
}

coordinate_latest() {
  local releases_file="$WORK_DIR/public-releases.json"
  local latest_file="$WORK_DIR/latest-release.json"
  local release_tag release_version comparison
  local current_public_count
  local highest_version=""
  local highest_tag=""

  fetch_release_pages "$releases_file"
  current_public_count="$(jq --arg tag "$TAG" \
    '[.[][] | select(.tag_name == $tag and .draft == false and .prerelease == false)] | length' \
    "$releases_file")"
  [[ "$current_public_count" == "1" ]] \
    || die "current tag $TAG must appear exactly once as a public stable Release before Latest coordination"
  while IFS= read -r release_tag; do
    [[ "$release_tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || continue
    release_version="${release_tag#v}"
    ec_is_marketing_version "$release_version" \
      || die "public stable-looking tag exceeds the supported numeric version range: $release_tag"
    if [[ -z "$highest_version" ]]; then
      highest_version="$release_version"
      highest_tag="$release_tag"
      continue
    fi
    comparison="$(ec_compare_versions "$release_version" "$highest_version")"
    if [[ "$comparison" == "1" ]]; then
      highest_version="$release_version"
      highest_tag="$release_tag"
    fi
  done < <(jq -r '.[][] | select(.draft == false and .prerelease == false) | .tag_name' "$releases_file")

  [[ -n "$highest_version" ]] || die "no public stable Release exists after publishing $TAG"
  if [[ "$VERSION" == "$highest_version" ]]; then
    gh release edit "$TAG" --latest
  else
    gh release edit "$TAG" --latest=false
  fi

  if ! gh_api "repos/$GH_REPO/releases/latest" > "$latest_file"; then
    die "failed to verify the repository Latest Release after coordination"
  fi
  [[ "$(jq -er '.tag_name' "$latest_file")" == "$highest_tag" ]] \
    || die "Latest Release verification did not resolve to highest stable tag $highest_tag"
}

load_release

if [[ "$MODE" == "inspect" ]]; then
  if [[ "$RELEASE_FOUND" == false ]]; then
    printf 'needs_artifacts=true\n'
    exit 0
  fi
  [[ "$(jq -r '.prerelease' "$RELEASE_FILE")" == "false" ]] \
    || die "existing Release $TAG is unexpectedly a prerelease"
  if [[ "$(jq -r '.draft' "$RELEASE_FILE")" == "true" ]]; then
    extract_and_validate_remote_marker identity
    validate_remote_assets partial
    printf 'needs_artifacts=true\n'
    exit 0
  fi
  extract_and_validate_remote_marker public
  validate_remote_assets complete
  printf 'needs_artifacts=false\n'
  exit 0
fi

if [[ "$RELEASE_FOUND" == true && "$(jq -r '.draft' "$RELEASE_FILE")" == "false" ]]; then
  [[ "$(jq -r '.prerelease' "$RELEASE_FILE")" == "false" ]] \
    || die "existing public Release $TAG is unexpectedly a prerelease"
  extract_and_validate_remote_marker public
  validate_remote_assets complete
  printf 'Public managed Release %s is intact; reconciling Latest status only.\n' "$TAG"
  assert_remote_tag_commit
  coordinate_latest
  exit 0
fi

prepare_local_assets

if [[ "$RELEASE_FOUND" == false ]]; then
  printf 'Creating managed draft Release: %s\n' "$TAG"
  gh release create "$TAG" \
    --verify-tag \
    --draft \
    --latest=false \
    --generate-notes \
    --title "$TAG" \
    --notes-file "$BODY_FILE"
  load_release
  [[ "$RELEASE_FOUND" == true && "$(jq -r '.draft' "$RELEASE_FILE")" == "true" ]] \
    || die "newly created Release $TAG was not returned as a draft"
else
  [[ "$(jq -r '.draft' "$RELEASE_FILE")" == "true" ]] \
    || die "Release state changed unexpectedly while reconciling $TAG"
fi

[[ "$(jq -r '.prerelease' "$RELEASE_FILE")" == "false" ]] \
  || die "managed draft $TAG is unexpectedly a prerelease"
extract_and_validate_remote_marker draft
validate_remote_assets partial
upload_missing_assets

load_release
[[ "$RELEASE_FOUND" == true && "$(jq -r '.draft' "$RELEASE_FILE")" == "true" ]] \
  || die "Release $TAG did not remain a draft through asset verification"
extract_and_validate_remote_marker draft
validate_remote_assets complete

# Publishing is deliberately split from Latest selection. The first edit cannot
# accidentally make an older concurrent release Latest; a failed second edit is
# recoverable because the public managed release is verified on the next run.
assert_remote_tag_commit
gh release edit "$TAG" --draft=false --latest=false
coordinate_latest
