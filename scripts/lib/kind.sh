#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# Kubewekend CLI library: kind command
# =============================================================================
# Kind cluster setup, destroy and utilities.
# Sourced by scripts/setup.sh (never run it directly). Functions only: nothing here runs until main() calls it.
# PROJECT_ROOT, HOST_VARS_DIR and the other path variables come from setup.sh; colours and info/warn/error from core.sh.

# ---------------------------------------------------------------------------
# COMMAND: kind
# ---------------------------------------------------------------------------
cmd_kind_help() {
    cat <<'EOF'
kubewekend kind - KIND (Kubernetes in Docker) cluster management

SUBCOMMANDS
  setup                 Install tools + create Kind cluster + networking
  destroy               Remove Kind cluster and related components
  utils [tags...]       Run K8s utilities (see UTILITY TAGS below)
  utils --list          List utility tags with options and status from master.yaml
                        (setup options: ./scripts/setup.sh config --list kind)

OPTIONS
  --host, -H <name>    Ansible host target (default: k8s-master-machine)
  --dry-run             Show ansible command without executing
  --skip-tags <tags>    Comma-separated tags to skip (e.g: install_common)
  --extra-vars <vars>   Additional ansible extra-vars (key=value)

EOF
    setup_help_section kind
    utils_help_section
    cat <<'EOF'
EXAMPLES
  # Full Kind cluster setup on master
  ./scripts/setup.sh kind setup

  # Setup on a specific host
  ./scripts/setup.sh kind setup --host k8s-master-machine

  # Destroy Kind cluster
  ./scripts/setup.sh kind destroy

  # Install cert-manager + dashboard
  ./scripts/setup.sh kind utils certmanager dashboard

  # Install full LGTM observability stack
  ./scripts/setup.sh kind utils monitoring

  # Install security policy engine
  ./scripts/setup.sh kind utils security

  # Install storage + secret management
  ./scripts/setup.sh kind utils storage secret_management

  # List utility tags, supported options and what is enabled in master.yaml
  ./scripts/setup.sh kind utils --list

  # Dry run to see what ansible would execute
  ./scripts/setup.sh kind setup --dry-run

  # Use another Kubernetes version: kindCluster.image in master.yaml is the only place (no extra-var reads it)
  ./scripts/setup.sh versions bump kind-node v1.35.8 --dry-run
  ./scripts/setup.sh versions bump kind-node v1.35.8
  ./scripts/setup.sh kind setup
EOF
}

cmd_kind() {
    local sub="${1:-help}"; shift || true
    case "$sub" in
        setup)   kind_setup "$@" ;;
        destroy) kind_destroy "$@" ;;
        utils)   kind_utils "$@" ;;
        *)       cmd_kind_help ;;
    esac
}

kind_setup() {
    parse_ansible_opts "$@"
    _check_archived_classes kind
    header "Setting up Kind cluster on $HOST_NAME"
    run_ansible_playbook "kind-playbook.yaml" "install_common,setup_kind"
    info "Kind cluster setup complete!"
}

kind_destroy() {
    parse_ansible_opts "$@"
    header "Destroying Kind cluster on $HOST_NAME"
    confirm "This will remove the Kind cluster and all related components. Continue?" || return 0
    run_ansible_playbook "kind-playbook.yaml" "remove_kind"
    info "Kind cluster destroyed"
}

kind_utils() { run_utils kind "$@"; }
