#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# Kubewekend CLI library: config command
# =============================================================================
# `config list|show|validate|edit` for master.yaml and worker.yaml.
# Sourced by scripts/setup.sh (never run it directly). Functions only: nothing here runs until main() calls it.
# PROJECT_ROOT, HOST_VARS_DIR and the other path variables come from setup.sh; colours and info/warn/error from core.sh.

# Full setup-option view of one distribution
_config_list_distro() {
    local distro="$1" top file="$HOST_VARS_DIR/master.yaml" wfile="$HOST_VARS_DIR/worker.yaml"
    local entry key desc opts dev paths path current used_by found=false
    top=$(_setup_top "$distro") || return 1
    case "$distro" in
        kind) used_by="kind setup" ;;
        *)    used_by="$distro setup / $distro ha-setup" ;;
    esac

    _sec "${distro^^} SETUP OPTIONS  (master.yaml → $top, used by: $used_by)"
    while IFS= read -r entry; do
        IFS='|' read -r key desc opts dev paths <<< "$entry"
        printf "  ${CYAN}%-20s${NC} %s\n" "$key" "$desc"
        printf "  %-20s   options: %s\n" "" "$opts"
        [[ -n "$dev" ]] && printf "  %-20s   ${YELLOW}in dev:${NC}  %s\n" "" "$dev"
        current=""
        local -a plist
        IFS=',' read -r -a plist <<< "$paths"
        for path in "${plist[@]}"; do
            [[ -n "$path" ]] && current+="${path}=$(_cur "$(_yaml_get "$file" "$top" "$path")") "
        done
        [[ -n "$current" ]] && printf "  %-20s   %s %s\n" "" "$(_cur_label)" "${current% }"
    done < <(_setup_entries "$distro")

    local dkey dval
    while IFS='|' read -r dkey dval; do
        [[ -z "$dkey" ]] && continue
        if [[ "$found" == false ]]; then
            printf "\n  ${YELLOW}In development${NC} (in master.yaml, not read by the playbooks yet):\n"
            found=true
        fi
        printf "  ${YELLOW}%-20s${NC}   %s %s\n" "$dkey" "$(_cur_label)" "$(_cur "$dval")"
    done < <(_setup_in_development "$distro")

    # Worker nodes read their own file for the agent configuration
    if [[ "$distro" != "kind" && -f "$wfile" ]]; then
        printf "\n  Worker nodes (worker.yaml → %s) %s version=%s  tlsSANs=%s  nodeLabels=%s  nodeTaints=%s\n" "$top" \
            "$(_cur_label)" \
            "$(_cur "$(_yaml_get "$wfile" "$top" version)")" "$(_cur "$(_yaml_get "$wfile" "$top" tlsSANs)")" \
            "$(_cur "$(_yaml_get "$wfile" "$top" nodeLabels)")" "$(_cur "$(_yaml_get "$wfile" "$top" nodeTaints)")"
    fi
}

# `config --list [kind|k3s|rke2|utils]`: supported / in-development options and current values
config_list() {
    local target="${1:-all}" distro
    case "$target" in
        utils|utilities) utils_list; return 0 ;;
        all|kind|k3s|rke2) ;;
        *) error "Unknown target: $target (expected: kind, k3s, rke2, utils)"; return 1 ;;
    esac

    header "Kubewekend setup options"
    printf "  Values: ${BOLD}%s${NC}\n" "$HOST_VARS_DIR/master.yaml"
    [[ -f "$HOST_VARS_DIR/master.yaml" ]] || warn "master.yaml not found: current values are unavailable"
    for distro in kind k3s rke2; do
        [[ "$target" == "all" || "$target" == "$distro" ]] && _config_list_distro "$distro"
    done
    echo ""
    info "Utility options: ./scripts/setup.sh config --list utils  (same as: <kind|k3s|rke2> utils --list)"
}

# `config validate [--strict]`: check master.yaml against what the playbooks read.
#   error:   a key no playbook reads (REMOVED_KEYS) or an archived ingress / Gateway API class
#   warning: a utility enabled in master.yaml that no tag installs yet
#   info:    cluster keys that are documented but not read yet ("in development")
# Exit 1 on errors; with --strict also on warnings. The pre-commit hook runs it, so a stale setting cannot be committed.
config_validate() {
    local strict=false arg
    for arg in "$@"; do
        case "$arg" in
            --strict) strict=true ;;
            *) error "Unknown option: $arg (expected: --strict)"; return 1 ;;
        esac
    done
    local file="$HOST_VARS_DIR/master.yaml" errors=0 warnings=0 msg distro block entry known keys
    [[ -f "$file" ]] || { error "File not found: $file"; return 1; }
    header "Validating $file"

    while IFS= read -r msg; do
        [[ -z "$msg" ]] && continue
        error "$msg"; errors=$((errors + 1))
    done < <(_removed_key_msgs all)

    for distro in kind rke2; do
        while IFS= read -r msg; do
            [[ -z "$msg" ]] && continue
            error "$msg"; errors=$((errors + 1))
        done < <(_archived_class_msgs "$distro")
    done

    for block in $(_util_master_blocks); do
        known=false
        for entry in "${UTILITY_REGISTRY[@]}"; do
            [[ "$(_util_field "$entry" 1)" == "$block" ]] && { known=true; break; }
        done
        [[ "$known" == true ]] && continue
        if [[ "$(_util_value "$block" "enable")" == "true" ]]; then
            warn "utilities.$block.enable is true, but no tag installs it yet (in development)"
            warnings=$((warnings + 1))
        fi
    done

    for distro in kind k3s rke2; do
        keys=$(_setup_in_development "$distro" | cut -d'|' -f1 | paste -sd, - | sed 's/,/, /g')
        [[ -n "$keys" ]] && info "$(_setup_top "$distro"): documented but not read by the playbooks yet: $keys"
    done

    echo ""
    if [[ $errors -gt 0 ]]; then
        error "$errors error(s), $warnings warning(s)"
        return 1
    fi
    if [[ "$strict" == true && $warnings -gt 0 ]]; then
        error "$warnings warning(s) (--strict)"
        return 1
    fi
    info "master.yaml is valid ($warnings warning(s))"
}

# ---------------------------------------------------------------------------
# COMMAND: config
# ---------------------------------------------------------------------------
cmd_config_help() {
    cat <<'EOF'
kubewekend config - View and edit cluster configuration

SUBCOMMANDS
  list [target]         Supported setup / utility options with current values from master.yaml
                        target: kind | k3s | rke2 | utils (default: kind, k3s and rke2)
                        aliases: --list, -l
  show [--raw]          Summary table of master.yaml (--raw: full file)
  validate [--strict]   Check master.yaml for keys no playbook reads, archived controllers and utilities with
                        no tag (exit 1 on errors; --strict also fails on warnings)
  edit                  Open master.yaml in $EDITOR
  worker-show [--raw]   Summary table of worker.yaml (--raw: full file)
  worker-edit           Open worker.yaml in $EDITOR

EXAMPLES
  ./scripts/setup.sh config --list
  ./scripts/setup.sh config --list k3s
  ./scripts/setup.sh config --list utils
  ./scripts/setup.sh config show
  ./scripts/setup.sh config show --raw
  ./scripts/setup.sh config validate
  ./scripts/setup.sh config edit
  ./scripts/setup.sh config worker-show
EOF
}

cmd_config() {
    local sub="${1:-help}"; shift || true
    case "$sub" in
        list|--list|-l) config_list "$@" ;;
        show)
            if [[ "${1:-}" == "--raw" ]]; then
                cat "$HOST_VARS_DIR/master.yaml"
            else
                config_show_master
            fi ;;
        validate)    config_validate "$@" ;;
        edit)        ${EDITOR:-vi} "$HOST_VARS_DIR/master.yaml" ;;
        worker-show)
            if [[ "${1:-}" == "--raw" ]]; then
                cat "$HOST_VARS_DIR/worker.yaml"
            else
                config_show_worker
            fi ;;
        worker-edit) ${EDITOR:-vi} "$HOST_VARS_DIR/worker.yaml" ;;
        *)           cmd_config_help ;;
    esac
}
