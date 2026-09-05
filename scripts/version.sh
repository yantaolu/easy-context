#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/version-lib.sh
source "$SCRIPT_DIR/version-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/version.sh
  ./scripts/version.sh --version
  ./scripts/version.sh --build
  ./scripts/version.sh --check-tag vX.Y.Z

Reads the single product-version source in project.yml. --check-tag verifies
that a strict release tag exactly matches MARKETING_VERSION.
EOF
}

ACTION="show"
TAG=""
PROJECT_FILE="$REPO_ROOT/project.yml"
VERSION_REPO_ROOT="$REPO_ROOT"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version|--build)
      [[ "$ACTION" == "show" ]] || { usage >&2; exit 2; }
      ACTION="${1#--}"
      ;;
    --check-tag)
      [[ "$ACTION" == "show" && $# -ge 2 ]] || { usage >&2; exit 2; }
      ACTION="check-tag"
      TAG="$2"
      shift
      ;;
    --project)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      PROJECT_FILE="$2"
      shift
      ;;
    --repo)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      VERSION_REPO_ROOT="$2"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
  shift
done

ec_read_project_version "$PROJECT_FILE"

case "$ACTION" in
  show)
    printf '%s (build %s)\n' "$EC_MARKETING_VERSION" "$EC_BUILD_NUMBER"
    ;;
  version)
    printf '%s\n' "$EC_MARKETING_VERSION"
    ;;
  build)
    printf '%s\n' "$EC_BUILD_NUMBER"
    ;;
  check-tag)
    tag_pattern='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
    if ! [[ "$TAG" =~ $tag_pattern ]]; then
      printf 'Release tag must use strict vX.Y.Z form: %s\n' "$TAG" >&2
      exit 1
    fi
    if [[ "${TAG#v}" != "$EC_MARKETING_VERSION" ]]; then
      printf 'Release tag %s does not match project.yml MARKETING_VERSION %s\n' \
        "$TAG" "$EC_MARKETING_VERSION" >&2
      exit 1
    fi
    HIGHEST_STABLE_VERSION="$(ec_highest_stable_tag_version "$VERSION_REPO_ROOT")"
    if [[ -n "$HIGHEST_STABLE_VERSION" ]] \
        && [[ "$(ec_compare_versions "$EC_MARKETING_VERSION" "$HIGHEST_STABLE_VERSION")" == "-1" ]]; then
      printf 'Release version %s is older than existing stable tag v%s\n' \
        "$EC_MARKETING_VERSION" "$HIGHEST_STABLE_VERSION" >&2
      exit 1
    fi
    printf '%s\n' "$EC_MARKETING_VERSION"
    ;;
esac
