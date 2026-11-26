#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# Kubewekend CLI library: Core helpers
# =============================================================================
# Colours, messages (info, warn, error, header, confirm), prerequisite checks and table helpers.
# Sourced by scripts/setup.sh (never run it directly). Functions only: nothing here runs until main() calls it.
# PROJECT_ROOT, HOST_VARS_DIR and the other path variables come from setup.sh; colours and info/warn/error from core.sh.

# Colours (disabled when not a terminal)
# shellcheck disable=SC2034  # BLUE is part of the palette even though no message uses it yet
if [[ -t 1 ]]; then
    RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
    BLUE=$'\033[0;34m'; CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; NC=$'\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; NC=''
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()    { printf "${GREEN}[INFO]${NC}  %s\n" "$*"; }
warn()    { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
error()   { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }
header()  { printf "\n${BOLD}${CYAN}>>> %s${NC}\n\n" "$*"; }
confirm() {
    local msg="${1:-Continue?}"
    printf "${YELLOW}%s [y/N]:${NC} " "$msg"
    read -r ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

require_cmd() {
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then
            error "'$cmd' is required but not installed."
            return 1
        fi
    done
}

load_env() {
    if [[ -f "$ENV_FILE" ]]; then
        set -a
        # shellcheck source=/dev/null
        source "$ENV_FILE"
        set +a
    fi
}

# Highlight a current value from master.yaml / worker.yaml for `--list` output:
# bold green when set, red "(unset)" when the key is missing
_cur() {
    if [[ -n "$1" ]]; then
        printf '%s' "${BOLD}${GREEN}$1${NC}"
    else
        printf '%s' "${RED}(unset)${NC}"
    fi
}

# Bold "current:" label used by the `--list` views
_cur_label() { printf '%s' "${BOLD}current:${NC}"; }

# Coloured ON/OFF badge with optional trailing label
_badge() {
    local val="$1" label="${2:-}"
    if [[ "$val" == "true" ]]; then
        printf "${GREEN}ON${NC}%s"  "${label:+  $label}"
    else
        printf "${RED}OFF${NC}%s" "${label:+  $label}"
    fi
}

# Single table row: cyan label (24-char) + value
_row() { printf "  ${CYAN}%-24s${NC}  %s\n" "$1" "$2"; }

# Section header with divider line
_sec() {
    printf "\n  ${BOLD}${YELLOW}▸ %s${NC}\n" "$1"
    # printf repetition instead of `tr`, which is byte-based and garbles the multi-byte '─'
    printf '  %s\n' "$(printf '─%.0s' {1..52})"
}
