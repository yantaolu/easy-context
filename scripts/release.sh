#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/version-lib.sh
source "$SCRIPT_DIR/version-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/release.sh show [--version|--build]
  ./scripts/release.sh prepare X.Y.Z [--dry-run]
  ./scripts/release.sh next-build [--dry-run]
  ./scripts/release.sh preview [--arch arm64|x86_64|universal]
  ./scripts/release.sh check-tag vX.Y.Z
  ./scripts/release.sh check vX.Y.Z

prepare requires a version greater than the source and local stable tags, and
increments the build. next-build only increments the build. preview clears dist
before building the current worktree in a unique dist/preview run, without
changing either number. Old outputs are not archived or restored on failure.
check-tag only validates tag/source equality (also for historical CI reruns).
check fetches origin/master and tags, requires a clean committed source reachable
from origin/master, an unused tag, and the latest HEAD master push CI to succeed.
It uses curl + jq with the public GitHub API; no gh login is needed. API/network
failures stop the check. No command commits, creates tags, pushes, or installs.
All commands accept --repo PATH and --project PATH for isolated fixtures.
EOF
}

ACTION="${1:-show}"
[[ $# -eq 0 ]] || shift
case "$ACTION" in
  show|prepare|next-build|preview|check-tag|check) ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
DRY_RUN=false
BUILD_ONLY=false
[[ "$ACTION" != next-build ]] || BUILD_ONLY=true
REPO_ROOT="$DEFAULT_REPO_ROOT"
PROJECT_FILE=""
TARGET_VERSION=""
SHOW_FIELD=""
TARGET_ARCH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      [[ "$ACTION" == prepare || "$ACTION" == next-build ]] || { usage >&2; exit 2; }
      DRY_RUN=true
      ;;
    --version|--build)
      [[ "$ACTION" == show && -z "$SHOW_FIELD" ]] || { usage >&2; exit 2; }
      SHOW_FIELD="$1"
      ;;
    --arch)
      [[ "$ACTION" == preview && $# -ge 2 && -z "$TARGET_ARCH" ]] || { usage >&2; exit 2; }
      TARGET_ARCH="$2"
      shift
      ;;
    --project)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      PROJECT_FILE="$2"
      shift
      ;;
    --repo)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      REPO_ROOT="$2"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      usage >&2
      exit 2
      ;;
    *)
      [[ "$ACTION" == prepare || "$ACTION" == check || "$ACTION" == check-tag ]] || { usage >&2; exit 2; }
      [[ -z "$TARGET_VERSION" ]] || { usage >&2; exit 2; }
      TARGET_VERSION="$1"
      ;;
  esac
  shift
done

PROJECT_FILE="${PROJECT_FILE:-$REPO_ROOT/project.yml}"
TEMP_FILE=""
cleanup() {
  local exit_status=$?
  [[ -z "$TEMP_FILE" || ! -e "$TEMP_FILE" ]] || rm -f "$TEMP_FILE" || true
  ec_release_repo_lock
  return "$exit_status"
}
if [[ "$ACTION" == prepare || "$ACTION" == next-build ]]; then
  ec_acquire_repo_lock "$REPO_ROOT"
  trap cleanup EXIT
  [[ ! -L "$PROJECT_FILE" ]] || { ec_version_die "version updates require a regular project file, not a symlink"; exit 1; }
fi
if [[ "$ACTION" != preview ]]; then
  ec_read_project_version "$PROJECT_FILE"
  CURRENT_VERSION="$EC_MARKETING_VERSION"
  CURRENT_BUILD="$EC_BUILD_NUMBER"
fi

case "$ACTION" in
  show)
    case "$SHOW_FIELD" in
      --version) printf '%s\n' "$CURRENT_VERSION" ;;
      --build) printf '%s\n' "$CURRENT_BUILD" ;;
      *) printf '%s (build %s)\n' "$CURRENT_VERSION" "$CURRENT_BUILD" ;;
    esac
    exit 0
    ;;
  preview)
    TARGET_ARCH="${TARGET_ARCH:-$(uname -m)}"
    case "$TARGET_ARCH" in arm64|x86_64|universal) ;; *) ec_version_die "invalid preview architecture: $TARGET_ARCH"; exit 1 ;; esac
    # Build-pkg reads its own project.yml. Refuse a separate source override.
    REPO_ROOT="$(cd "$REPO_ROOT" && pwd -P)"
    PROJECT_FILE="$(cd "$(dirname "$PROJECT_FILE")" && pwd -P)/$(basename "$PROJECT_FILE")"
    [[ "$PROJECT_FILE" == "$REPO_ROOT/project.yml" ]] || { ec_version_die "preview requires the repository project.yml"; exit 1; }
    if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
        && ! git -C "$REPO_ROOT" diff --cached --quiet --; then
      printf 'Warning: staged changes exist; preview builds the current worktree, not the index.\n' >&2
    fi
    printf 'Preview: current worktree; the build reads the version under its repository lock without incrementing it.\n'
    TARGET_ARCH="$TARGET_ARCH" "$REPO_ROOT/scripts/build-pkg.sh" --preview
    exit 0
    ;;
  check-tag|check)
    [[ "$TARGET_VERSION" == v* ]] && ec_is_marketing_version "${TARGET_VERSION#v}" \
      || { ec_version_die "release tag must use strict vX.Y.Z form: $TARGET_VERSION"; exit 1; }
    [[ "${TARGET_VERSION#v}" == "$CURRENT_VERSION" ]] \
      || { ec_version_die "release tag $TARGET_VERSION does not match project.yml MARKETING_VERSION $CURRENT_VERSION"; exit 1; }
    if [[ "$ACTION" == check-tag ]]; then
      printf '%s\n' "$CURRENT_VERSION"
      exit 0
    fi
    ;;
esac

if [[ "$ACTION" == check ]]; then
  REPO_ROOT="$(cd "$REPO_ROOT" && git rev-parse --show-toplevel)"
  REPO_ROOT="$(cd "$REPO_ROOT" && pwd -P)"
  PROJECT_FILE="$(cd "$(dirname "$PROJECT_FILE")" && pwd -P)/$(basename "$PROJECT_FILE")"
  [[ "$PROJECT_FILE" == "$REPO_ROOT/"* ]] || { ec_version_die "project source must be inside the repository"; exit 1; }
  PROJECT_PATH="${PROJECT_FILE#"$REPO_ROOT/"}"
  CHECK_HEAD="$(git -C "$REPO_ROOT" rev-parse HEAD)"
  assert_clean_source() {
    local worktree_status committed_blob
    worktree_status="$(git -C "$REPO_ROOT" status --porcelain --untracked-files=all)" || return 1
    [[ -z "$worktree_status" ]] \
      || { ec_version_die "release check requires a clean worktree, index, and no untracked files"; return 1; }
    [[ "$(git -C "$REPO_ROOT" rev-parse HEAD)" == "$CHECK_HEAD" ]] \
      || { ec_version_die "HEAD changed during release check"; return 1; }
    committed_blob="$(git -C "$REPO_ROOT" rev-parse "HEAD:$PROJECT_PATH")" \
      || { ec_version_die "project source must be committed in HEAD"; return 1; }
    [[ "$(git -C "$REPO_ROOT" hash-object "$PROJECT_FILE")" == "$committed_blob" ]] \
      || { ec_version_die "project source differs from committed HEAD"; return 1; }
  }
  assert_clean_source
  ORIGIN_URL="$(git -C "$REPO_ROOT" remote get-url origin)"
  case "$ORIGIN_URL" in
    git@github.com:yantaolu/easy-context|git@github.com:yantaolu/easy-context.git|https://github.com/yantaolu/easy-context|https://github.com/yantaolu/easy-context.git|ssh://git@github.com/yantaolu/easy-context|ssh://git@github.com/yantaolu/easy-context.git) ;;
    *) ec_version_die "origin must be the GitHub repository yantaolu/easy-context"; exit 1 ;;
  esac
  command -v curl >/dev/null && command -v jq >/dev/null \
    || { ec_version_die "release check requires curl and jq"; exit 1; }
  git -C "$REPO_ROOT" fetch --no-recurse-submodules origin '+refs/heads/master:refs/remotes/origin/master' --tags \
    || { ec_version_die "fetch origin master and tags failed; release check stopped"; exit 1; }
  git -C "$REPO_ROOT" merge-base --is-ancestor "$CHECK_HEAD" refs/remotes/origin/master \
    || { ec_version_die "HEAD is not reachable from origin/master"; exit 1; }
  if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/tags/$TARGET_VERSION"; then
    ec_version_die "release tag already exists locally or remotely: $TARGET_VERSION"
    exit 1
  fi
  HIGHEST_STABLE_VERSION="$(ec_highest_stable_tag_version "$REPO_ROOT")"
  if [[ -n "$HIGHEST_STABLE_VERSION" ]] \
      && [[ "$(ec_compare_versions "$CURRENT_VERSION" "$HIGHEST_STABLE_VERSION")" != 1 ]]; then
    ec_version_die "release version must exceed existing stable tag v$HIGHEST_STABLE_VERSION"
    exit 1
  fi
  CI_RESPONSE="$(curl --fail --silent --show-error --connect-timeout 15 --max-time 60 \
    --proto '=https' -H 'Accept: application/vnd.github+json' \
    'https://api.github.com/repos/yantaolu/easy-context/actions/workflows/ci.yml/runs?branch=master&event=push&head_sha='"$CHECK_HEAD"'&per_page=100')" \
    || { ec_version_die "could not read GitHub CI status; release check stopped"; exit 1; }
  # Do not accept an older successful run if a newer run failed or is pending.
  printf '%s' "$CI_RESPONSE" | jq -e --arg sha "$CHECK_HEAD" '
    [.workflow_runs[] | select(.head_sha == $sha and .head_branch == "master" and .event == "push"
      and .path == ".github/workflows/ci.yml")]
    | sort_by(.created_at, .id, .run_attempt) | last
    | . != null and .status == "completed" and .conclusion == "success"
  ' >/dev/null || { ec_version_die "latest HEAD master push CI is missing, pending, failed, or invalid"; exit 1; }
  assert_clean_source
  printf 'Release check passed: %s at %s; latest master push CI succeeded. No tag was created.\n' "$TARGET_VERSION" "$CHECK_HEAD"
  exit 0
fi

if [[ "$BUILD_ONLY" == true ]]; then
  TARGET_VERSION="$CURRENT_VERSION"
  MODE_DESCRIPTION="explicit build-number increment (no build is run)"
else
  if [[ -z "$TARGET_VERSION" ]]; then
    usage >&2
    exit 2
  fi
  if ! ec_is_marketing_version "$TARGET_VERSION"; then
    ec_version_die "target version must use strict X.Y.Z form: $TARGET_VERSION"
    exit 1
  fi
  comparison="$(ec_compare_versions "$TARGET_VERSION" "$CURRENT_VERSION")"
  if [[ "$comparison" != "1" ]]; then
    ec_version_die "release version $TARGET_VERSION must be greater than current version $CURRENT_VERSION"
    exit 1
  fi
  if ! git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    ec_version_die "release repository is not a Git work tree: $REPO_ROOT"
    exit 1
  fi
  if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/tags/v$TARGET_VERSION"; then
    ec_version_die "release tag already exists: v$TARGET_VERSION"
    exit 1
  fi
  HIGHEST_STABLE_VERSION="$(ec_highest_stable_tag_version "$REPO_ROOT")"
  if [[ -n "$HIGHEST_STABLE_VERSION" ]] \
      && [[ "$(ec_compare_versions "$TARGET_VERSION" "$HIGHEST_STABLE_VERSION")" != "1" ]]; then
    ec_version_die "release version $TARGET_VERSION must be greater than existing stable tag v$HIGHEST_STABLE_VERSION"
    exit 1
  fi
  MODE_DESCRIPTION="release preparation"
fi

NEXT_BUILD="$(ec_increment_decimal "$CURRENT_BUILD")"
printf 'Current: %s (build %s)\n' "$CURRENT_VERSION" "$CURRENT_BUILD"
printf 'Target:  %s (build %s) — %s\n' "$TARGET_VERSION" "$NEXT_BUILD" "$MODE_DESCRIPTION"

if [[ "$DRY_RUN" == true ]]; then
  printf 'Dry run: project.yml was not modified.\n'
  exit 0
fi

PROJECT_DIR="$(cd "$(dirname "$PROJECT_FILE")" && pwd)"
PROJECT_BASENAME="$(basename "$PROJECT_FILE")"
TEMP_FILE="$(mktemp "$PROJECT_DIR/.${PROJECT_BASENAME}.XXXXXX")"

if ! awk -v version="$TARGET_VERSION" -v build="$NEXT_BUILD" '
  /^[[:space:]]*MARKETING_VERSION[[:space:]]*:/ {
    comment = ""
    if (match($0, /[[:space:]]+#/)) comment = substr($0, RSTART)
    prefix = $0
    sub(/MARKETING_VERSION.*/, "", prefix)
    print prefix "MARKETING_VERSION: " version comment
    marketing_count++
    next
  }
  /^[[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*:/ {
    comment = ""
    if (match($0, /[[:space:]]+#/)) comment = substr($0, RSTART)
    prefix = $0
    sub(/CURRENT_PROJECT_VERSION.*/, "", prefix)
    print prefix "CURRENT_PROJECT_VERSION: " build comment
    build_count++
    next
  }
  { print }
  END {
    if (marketing_count != 1 || build_count != 1) exit 1
  }
' "$PROJECT_FILE" > "$TEMP_FILE"; then
  ec_version_die "could not render a project file with exactly one version and build setting"
  exit 1
fi

# Validate the rendered file before the atomic rename. Keep the original mode.
ec_read_project_version "$TEMP_FILE"
if [[ "$EC_MARKETING_VERSION" != "$TARGET_VERSION" || "$EC_BUILD_NUMBER" != "$NEXT_BUILD" ]]; then
  ec_version_die "rendered project version did not match the requested values"
  exit 1
fi
FILE_MODE="$(stat -f '%Lp' "$PROJECT_FILE")"
chmod "$FILE_MODE" "$TEMP_FILE"
mv "$TEMP_FILE" "$PROJECT_FILE"
TEMP_FILE=""

printf 'Updated %s. Review and test the change before committing or tagging.\n' "$PROJECT_FILE"
