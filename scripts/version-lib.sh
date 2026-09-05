#!/bin/bash

# Shared, dependency-free helpers for reading and comparing the product version.
# This file is sourced by the release scripts; it intentionally has no side effects.

ec_version_die() {
  printf 'Version error: %s\n' "$*" >&2
  return 1
}

EC_INT64_MAX="9223372036854775807"

ec_is_int64_component() {
  local value="$1"
  local LC_ALL=C
  [[ "$value" =~ ^(0|[1-9][0-9]*)$ ]] || return 1
  if (( ${#value} < ${#EC_INT64_MAX} )); then
    return 0
  fi
  if (( ${#value} > ${#EC_INT64_MAX} )); then
    return 1
  fi
  [[ "$value" == "$EC_INT64_MAX" || "$value" < "$EC_INT64_MAX" ]]
}

ec_is_marketing_version() {
  local value="$1"
  local pattern='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
  local parts=()
  [[ "$value" =~ $pattern ]] || return 1
  IFS=. read -r -a parts <<< "$value"
  ec_is_int64_component "${parts[0]}" \
    && ec_is_int64_component "${parts[1]}" \
    && ec_is_int64_component "${parts[2]}"
}

ec_is_build_number() {
  local value="$1"
  [[ "$value" =~ ^[1-9][0-9]*$ ]] && ec_is_int64_component "$value"
}

ec_compare_decimal() {
  local left="$1"
  local right="$2"
  local LC_ALL=C

  if (( ${#left} > ${#right} )); then
    printf '1\n'
  elif (( ${#left} < ${#right} )); then
    printf '%s\n' '-1'
  elif [[ "$left" == "$right" ]]; then
    printf '0\n'
  elif [[ "$left" > "$right" ]]; then
    printf '1\n'
  else
    printf '%s\n' '-1'
  fi
}

ec_increment_decimal() {
  local value="$1"
  local result=""
  local digit replacement
  local index

  if ! ec_is_build_number "$value"; then
    ec_version_die "cannot increment invalid build number: $value"
    return 1
  fi
  if [[ "$value" == "$EC_INT64_MAX" ]]; then
    ec_version_die "build number cannot exceed signed 64-bit maximum $EC_INT64_MAX"
    return 1
  fi
  index=$((${#value} - 1))
  while (( index >= 0 )); do
    digit="${value:index:1}"
    case "$digit" in
      0) replacement=1 ;;
      1) replacement=2 ;;
      2) replacement=3 ;;
      3) replacement=4 ;;
      4) replacement=5 ;;
      5) replacement=6 ;;
      6) replacement=7 ;;
      7) replacement=8 ;;
      8) replacement=9 ;;
      9) replacement=0 ;;
    esac
    result="$replacement$result"
    if [[ "$digit" != "9" ]]; then
      printf '%s%s\n' "${value:0:index}" "$result"
      return 0
    fi
    index=$((index - 1))
  done
  printf '1%s\n' "$result"
}

ec_extract_project_setting() {
  local project_file="$1"
  local key="$2"

  awk -v key="$key" '
    $0 ~ "^[[:space:]]*" key "[[:space:]]*:" {
      value = $0
      sub("^[[:space:]]*" key "[[:space:]]*:[[:space:]]*", "", value)
      sub(/[[:space:]]+#.*$/, "", value)
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      quote = substr(value, 1, 1)
      if (length(value) >= 2 && (quote == "\"" || quote == sprintf("%c", 39)) && substr(value, length(value), 1) == quote) {
        value = substr(value, 2, length(value) - 2)
      }
      print value
      count++
    }
    END {
      if (count != 1) exit 1
    }
  ' "$project_file"
}

ec_read_project_version() {
  local project_file="$1"
  local marketing_version
  local build_number

  if [[ ! -f "$project_file" ]]; then
    ec_version_die "project file does not exist: $project_file"
    return 1
  fi
  if ! marketing_version="$(ec_extract_project_setting "$project_file" MARKETING_VERSION)"; then
    ec_version_die "$project_file must contain exactly one MARKETING_VERSION setting"
    return 1
  fi
  if ! build_number="$(ec_extract_project_setting "$project_file" CURRENT_PROJECT_VERSION)"; then
    ec_version_die "$project_file must contain exactly one CURRENT_PROJECT_VERSION setting"
    return 1
  fi
  if ! ec_is_marketing_version "$marketing_version"; then
    ec_version_die "MARKETING_VERSION must use strict X.Y.Z numeric form with components no greater than $EC_INT64_MAX: $marketing_version"
    return 1
  fi
  if ! ec_is_build_number "$build_number"; then
    ec_version_die "CURRENT_PROJECT_VERSION must be a positive integer no greater than $EC_INT64_MAX: $build_number"
    return 1
  fi

  EC_MARKETING_VERSION="$marketing_version"
  EC_BUILD_NUMBER="$build_number"
}

# Prints -1, 0, or 1 when the first valid X.Y.Z version is less than, equal to,
# or greater than the second. Components are compared numerically.
ec_compare_versions() {
  local left="$1"
  local right="$2"
  local left_parts=()
  local right_parts=()
  local index
  local comparison

  if ! ec_is_marketing_version "$left"; then
    ec_version_die "invalid version: $left"
    return 1
  fi
  if ! ec_is_marketing_version "$right"; then
    ec_version_die "invalid version: $right"
    return 1
  fi

  IFS=. read -r -a left_parts <<< "$left"
  IFS=. read -r -a right_parts <<< "$right"
  for index in 0 1 2; do
    comparison="$(ec_compare_decimal "${left_parts[index]}" "${right_parts[index]}")"
    if [[ "$comparison" != "0" ]]; then
      printf '%s\n' "$comparison"
      return 0
    fi
  done
  printf '0\n'
}

# Prints the numerically greatest strict vX.Y.Z tag in a local repository, or an
# empty line if there are no stable version tags. No fetch or other network work
# is performed.
ec_highest_stable_tag_version() {
  local repo_root="$1"
  local tag version comparison
  local highest=""
  local tag_pattern='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'

  if ! git -C "$repo_root" rev-parse --git-dir >/dev/null 2>&1; then
    ec_version_die "release repository is not a Git work tree: $repo_root"
    return 1
  fi
  while IFS= read -r tag; do
    [[ "$tag" =~ $tag_pattern ]] || continue
    version="${tag#v}"
    ec_is_marketing_version "$version" || continue
    if [[ -z "$highest" ]]; then
      highest="$version"
      continue
    fi
    comparison="$(ec_compare_versions "$version" "$highest")"
    if [[ "$comparison" == "1" ]]; then
      highest="$version"
    fi
  done <<< "$(git -C "$repo_root" tag --list 'v*')"
  printf '%s\n' "$highest"
}
