#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# Kubewekend CLI library: Debug mode
# =============================================================================
# `./scripts/setup.sh --debug <command>` (first argument) or KUBEWEKEND_DEBUG=1 switches this on from setup.sh.
#   - every command is traced as `+ file.sh:LINE function(): command`
#   - the first unexpected failure prints the failing line of source, its file:line and the call stack
#   - KUBEWEKEND_DEBUG_LOG=<file> writes the trace to that file instead of the terminal
# Normal runs never load a trap or a trace, and debug output goes to stderr, so stdout is the same with or without it.
# Sourced by scripts/setup.sh (never run it directly).

# Set once the first failure was reported: the same failure travels up through every caller, report it only once
_DEBUG_FAILURE_SHOWN=false

_debug_on() {
    PS4='+ ${BASH_SOURCE[0]##*/}:${LINENO} ${FUNCNAME[0]:-top-level}(): '
    if [[ -n "${KUBEWEKEND_DEBUG_LOG:-}" ]]; then
        # shellcheck disable=SC2034  # read by bash itself: BASH_XTRACEFD sends the trace to this descriptor
        exec {BASH_XTRACEFD}>>"$KUBEWEKEND_DEBUG_LOG"
        printf '%s[DEBUG]%s trace written to %s\n' "$YELLOW" "$NC" "$KUBEWEKEND_DEBUG_LOG" >&2
    else
        printf '%s[DEBUG]%s tracing every command (KUBEWEKEND_DEBUG_LOG=<file> writes the trace to a file instead)\n' "$YELLOW" "$NC" >&2
    fi
    set -E   # functions and subshells inherit the ERR trap
    trap '_debug_on_error $? "${BASH_SOURCE[0]}" "$LINENO"' ERR
    set -x
}

# Usage: _debug_on_error <exit code> <file> <line>   (called by the ERR trap)
# The failing command is read from the source line: bash's own BASH_COMMAND would show the last statement of a
# function that returned non-zero (often a bare `return 1`) instead of the call that failed.
_debug_on_error() {
    local rc=$1 file=$2 line=$3 i src
    { set +x; } 2>/dev/null
    if [[ "$_DEBUG_FAILURE_SHOWN" == false ]]; then
        _DEBUG_FAILURE_SHOWN=true
        src=$(sed -n "${line}p" "$file" 2>/dev/null | sed -E 's/^[[:space:]]+//')
        printf '%s[DEBUG]%s command failed (exit %s) at %s:%s\n         %s\n' "$RED" "$NC" "$rc" "$(_debug_rel "$file")" "$line" "${src:-<source line not available>}" >&2
        printf '         call stack, innermost first:\n' >&2
        for ((i = 1; i < ${#FUNCNAME[@]}; i++)); do
            [[ -n "${BASH_SOURCE[$((i + 1))]:-}" ]] || break   # the last frame is the script itself, not a function
            printf '           %s()  called from %s:%s\n' "${FUNCNAME[$i]}" "$(_debug_rel "${BASH_SOURCE[$((i + 1))]}")" "${BASH_LINENO[$i]}" >&2
        done
    fi
    set -x
}

# Path relative to the project root, for readable reports (setup.sh may be started as ./scripts/setup.sh)
_debug_rel() {
    local f=$1
    case "$f" in
        "$PROJECT_ROOT"/*) f=${f#"$PROJECT_ROOT"/} ;;
        ./scripts/*)       f=${f#./} ;;
        */setup.sh|setup.sh) f=scripts/setup.sh ;;
    esac
    printf '%s' "$f"
}
