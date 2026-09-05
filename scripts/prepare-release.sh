#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/version-lib.sh
source "$SCRIPT_DIR/version-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/prepare-release.sh [--dry-run] X.Y.Z
  ./scripts/prepare-release.sh [--dry-run] --build-only [X.Y.Z]

Normal mode requires a version greater than the current version and increments
the build number. --build-only keeps the current version and only increments
the build number for a local test package. No commit, tag, push, or build is run.
EOF
}

DRY_RUN=false
BUILD_ONLY=false
REPO_ROOT="$DEFAULT_REPO_ROOT"
PROJECT_FILE=""
TARGET_VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      ;;
    --build-only)
      BUILD_ONLY=true
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
      [[ -z "$TARGET_VERSION" ]] || { usage >&2; exit 2; }
      TARGET_VERSION="$1"
      ;;
  esac
  shift
done

PROJECT_FILE="${PROJECT_FILE:-$REPO_ROOT/project.yml}"
ec_read_project_version "$PROJECT_FILE"
CURRENT_VERSION="$EC_MARKETING_VERSION"
CURRENT_BUILD="$EC_BUILD_NUMBER"

if [[ "$BUILD_ONLY" == true ]]; then
  TARGET_VERSION="${TARGET_VERSION:-$CURRENT_VERSION}"
  if ! ec_is_marketing_version "$TARGET_VERSION"; then
    ec_version_die "target version must use strict X.Y.Z form: $TARGET_VERSION"
    exit 1
  fi
  if [[ "$TARGET_VERSION" != "$CURRENT_VERSION" ]]; then
    ec_version_die "--build-only must keep the current version $CURRENT_VERSION (received $TARGET_VERSION)"
    exit 1
  fi
  MODE_DESCRIPTION="local build-only preparation"
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
cleanup() {
  [[ ! -e "$TEMP_FILE" ]] || rm -f "$TEMP_FILE"
}
trap cleanup EXIT

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
trap - EXIT

printf 'Updated %s. Review and test the change before committing or tagging.\n' "$PROJECT_FILE"
