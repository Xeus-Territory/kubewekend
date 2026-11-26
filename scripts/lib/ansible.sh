#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# Kubewekend CLI library: Ansible runner
# =============================================================================
# The ansible-playbook wrapper shared by kind, k3s and rke2, and the `utils` command they all use.
# Sourced by scripts/setup.sh (never run it directly). Functions only: nothing here runs until main() calls it.
# PROJECT_ROOT, HOST_VARS_DIR and the other path variables come from setup.sh; colours and info/warn/error from core.sh.

# Shared implementation of `kind|k3s|rke2 utils`
run_utils() {
    local distro="$1"; shift
    local arg
    [[ "${1:-}" == "list" ]] && { utils_list; return 0; }
    for arg in "$@"; do
        [[ "$arg" == "--list" || "$arg" == "-l" ]] && { utils_list; return 0; }
    done

    parse_ansible_opts "$@"
    if [[ ${#ANSIBLE_TAGS[@]} -eq 0 ]]; then
        error "Specify at least one utility tag."
        echo ""
        utils_help_section
        echo "Example: ./scripts/setup.sh $distro utils certmanager monitoring"
        return 1
    fi

    # Reject unknown tags instead of letting ansible silently run nothing
    local tag entry key enabled unknown=()
    for tag in "${ANSIBLE_TAGS[@]}"; do
        _util_entry "$tag" >/dev/null || unknown+=("$tag")
    done
    if [[ ${#unknown[@]} -gt 0 ]]; then
        error "Unknown utility tag(s): ${unknown[*]}"
        echo "  List supported tags: ./scripts/setup.sh $distro utils --list"
        return 1
    fi

    # The playbook skips a block whose `enable` is not true, so warn before running
    for tag in "${ANSIBLE_TAGS[@]}"; do
        entry=$(_util_entry "$tag"); key=$(_util_field "$entry" 1)
        enabled=$(_util_value "$key" "enable")
        if [[ "$enabled" != "true" ]]; then
            warn "'$tag' is disabled in master.yaml (utilities.$key.enable: ${enabled:-unset}); the playbook will skip it"
        fi
    done

    local tags_str
    tags_str=$(IFS=,; echo "${ANSIBLE_TAGS[*]}")
    header "Installing K8s utilities: $tags_str (target: $HOST_NAME)"
    run_ansible_playbook "k8s-utilities-playbook.yaml" "$tags_str"
    info "Utilities installed: $tags_str"
}

# Parse common ansible flags used by kind/k3s/rke2 commands
parse_ansible_opts() {
    HOST_NAME="k8s-master-machine"
    DRY_RUN=false
    ASK_BECOME_PASS=false
    SKIP_TAGS=""
    EXTRA_VARS=""
    ANSIBLE_TAGS=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --host|-H)       HOST_NAME="$2"; shift 2 ;;
            --dry-run)       DRY_RUN=true;  shift ;;
            --skip-tags)     SKIP_TAGS="$2"; shift 2 ;;
            --extra-vars)    EXTRA_VARS="$2"; shift 2 ;;
            --ask-become-pass) ASK_BECOME_PASS=true; shift ;;
            -*)              warn "Unknown option: $1"; shift ;;
            *)               ANSIBLE_TAGS+=("$1"); shift ;;
        esac
    done
}

run_ansible_playbook() {
    local playbook="$1"; shift
    local tags="$1"; shift
    local extra="${1:-}"

    require_cmd ansible-playbook || return 1

    local cmd=(
        ansible-playbook
        -i "$HOSTS_FILE"
        --extra-vars "host_name=$HOST_NAME"
    )

    [[ -n "$tags" ]]       && cmd+=(--tags "$tags")
    [[ -n "$SKIP_TAGS" ]]  && cmd+=(--skip-tags "$SKIP_TAGS")
    [[ -n "$EXTRA_VARS" ]] && cmd+=(--extra-vars "$EXTRA_VARS")
    [[ -n "$extra" ]]      && cmd+=(--extra-vars "$extra")
    cmd+=("$ANSIBLE_DIR/$playbook")

    if [[ "$ASK_BECOME_PASS" == true ]]; then
        cmd+=(--ask-become-pass)
    fi

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY RUN] ${cmd[*]}"
        return 0
    fi

    info "Running: ${cmd[*]}"
    "${cmd[@]}"
}
