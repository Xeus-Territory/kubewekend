#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# Kubewekend CLI library: YAML readers
# =============================================================================
# Pure-bash readers for the host_vars files (no yq or jq): _yaml_get, _yaml_has and the block helpers.
# Sourced by scripts/setup.sh (never run it directly). Functions only: nothing here runs until main() calls it.
# PROJECT_ROOT, HOST_VARS_DIR and the other path variables come from setup.sh; colours and info/warn/error from core.sh.

# Read `<top>.<dotted.path>` from a host_vars YAML file, matching the exact indentation (2 spaces per level)
# so that nested keys with the same name (e.g. `enable`, `type`) never collide.
# Scalars are returned as-is, block lists ("- item") comma-joined, block scalars (`|`) as "(multi-line)".
# Missing keys return an empty string.
_yaml_get() {
    local file="$1" top="$2" path="$3" data indent=2 part last line value
    [[ -f "$file" ]] || return 0
    data=$(_yblock "$top" "$file")
    local -a parts
    IFS='.' read -r -a parts <<< "$path"
    last="${parts[${#parts[@]}-1]}"
    for part in "${parts[@]:0:${#parts[@]}-1}"; do
        data=$(printf '%s\n' "$data" | _ysub "$part" "$indent")
        indent=$((indent + 2))
    done
    line=$({ printf '%s\n' "$data" | grep -m1 -E "^ {${indent}}${last}:" || true; })
    [[ -n "$line" ]] || return 0
    value=$(printf '%s\n' "$line" | sed -E 's/^[^:]*:[[:space:]]*//; s/[[:space:]]+#.*$//; s/^#.*$//' \
        | tr -d '"' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
    case "$value" in
        "|"|"|-"|">"|">-") value="(multi-line)" ;;
        "")
            value=$(printf '%s\n' "$data" | _ysub "$last" "$indent" \
                | { grep -E '^[[:space:]]*-[[:space:]]' || true; } \
                | sed -E 's/^[[:space:]]*-[[:space:]]*//; s/[[:space:]]+#.*$//' | tr -d '"' \
                | paste -sd, - | sed 's/,/, /g') ;;
    esac
    printf '%s' "$value"
}

# True when `<top>.<dotted.path>` exists as a key in a host_vars YAML file (same indentation rules as _yaml_get)
_yaml_has() {
    local file="$1" top="$2" path="$3" data indent=2 part last
    [[ -f "$file" ]] || return 1
    data=$(_yblock "$top" "$file")
    local -a parts
    IFS='.' read -r -a parts <<< "$path"
    last="${parts[${#parts[@]}-1]}"
    for part in "${parts[@]:0:${#parts[@]}-1}"; do
        data=$(printf '%s\n' "$data" | _ysub "$part" "$indent")
        indent=$((indent + 2))
    done
    grep -q -E "^ {${indent}}${last}:" <<< "$data"
}

# ---------------------------------------------------------------------------
# COMMAND: config — YAML parsing helpers (pure bash, no yq/jq)
# ---------------------------------------------------------------------------

# Extract all indented lines under a 0-indent top-level YAML key (from file)
_yblock() {
    awk "/^${1}:/{f=1;next} f&&/^[^ ]/{exit} f{print}" "$2"
}

# Extract a sub-block at a fixed indent level from stdin
# $1 = key name, $2 = number of leading spaces the key sits at (default 2)
_ysub() {
    local key="$1" spc
    printf -v spc '%*s' "${2:-2}" ''
    awk "/^${spc}${key}:/{f=1;next} f&&/^${spc}[^ ]/{exit} f{print}"
}

# Get the first scalar value for a key from stdin
# A missing key returns an empty string instead of failing: under `set -euo pipefail` a grep without a match
# would otherwise abort the whole command (e.g. `config show` after a key moves in master.yaml).
_yval() {
    { grep -m1 "^\s*${1}:" || true; } \
      | sed 's/[^:]*:[[:space:]]*//' \
      | tr -d '"' \
      | sed 's/[[:space:]]*#.*//' \
      | sed -E 's/^[[:space:]]+|[[:space:]]+$//g'
}

# Collect YAML list items ("  - value") from stdin → comma-joined
_ylist() {
    local result
    result=$({ grep "^\s*-[[:space:]]" || true; } \
      | sed 's/^\s*-[[:space:]]*//' \
      | tr -d '"' \
      | sed 's/[[:space:]]*#.*//' \
      | awk 'NR>1{printf ", "}{printf $0} END{if(NR>0)printf ""}')
    printf '%s' "${result:-none}"
}
