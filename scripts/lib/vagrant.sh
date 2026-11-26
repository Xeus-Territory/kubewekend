#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# Kubewekend CLI library: vagrant command
# =============================================================================
# Vagrant VM lifecycle.
# Sourced by scripts/setup.sh (never run it directly). Functions only: nothing here runs until main() calls it.
# PROJECT_ROOT, HOST_VARS_DIR and the other path variables come from setup.sh; colours and info/warn/error from core.sh.

# ---------------------------------------------------------------------------
# COMMAND: vagrant
# ---------------------------------------------------------------------------
cmd_vagrant_help() {
    cat <<'EOF'
kubewekend vagrant - Vagrant VM management

SUBCOMMANDS
  up [machines...]       Provision VMs (default: k8s-master-machine)
  halt [machines...]     Stop VMs
  destroy [machines...]  Destroy VMs
  status                 Show VM status
  ssh <machine>          SSH into a VM
  reload [machines...]   Reload VMs

OPTIONS
  Machines can be specified by name or regex pattern.

REQUIREMENTS
  Environment variables SSH_USER, SSH_KEY are read from .env

EXAMPLES
  # Provision master only
  ./scripts/setup.sh vagrant up k8s-master-machine

  # Provision master + 2 workers
  ./scripts/setup.sh vagrant up k8s-master-machine k8s-worker-machine-1 k8s-worker-machine-2

  # Provision workers by regex
  ./scripts/setup.sh vagrant up "/k8s-worker-machine-[1-2]/"

  # Check all VM status
  ./scripts/setup.sh vagrant status

  # SSH into master
  ./scripts/setup.sh vagrant ssh k8s-master-machine

  # Halt everything
  ./scripts/setup.sh vagrant halt

  # Destroy a specific worker
  ./scripts/setup.sh vagrant destroy k8s-worker-machine-1
EOF
}

cmd_vagrant() {
    local sub="${1:-help}"; shift || true
    case "$sub" in
        up)      vagrant_up "$@" ;;
        halt)    vagrant_halt "$@" ;;
        destroy) vagrant_destroy "$@" ;;
        status)  vagrant_status ;;
        ssh)     vagrant_ssh "$@" ;;
        reload)  vagrant_reload "$@" ;;
        *)       cmd_vagrant_help ;;
    esac
}

vagrant_up() {
    load_env
    require_cmd vagrant || return 1
    cd "$PROJECT_ROOT"

    local machines=("${@:-k8s-master-machine}")
    header "Provisioning VMs: ${machines[*]}"

    export SSH_USER="${SSH_USER:-vagrant}"
    export SSH_KEY="${SSH_KEY:-vmbox}"

    [ -f "$HOME/.ssh/$SSH_KEY" ] && [ -f "$HOME/.ssh/$SSH_KEY.pub" ] || {
        error "SSH key and public key not found at $HOME/.ssh/$SSH_KEY"
        error "Please generate it with: ssh-keygen -t rsa -b 2048 -C \"vmbox\" -f ~/.ssh/vmbox"
        return 1
    }

    # Printf the profile environment variables before running vagrant up
    info "Using SSH_USER=$SSH_USER"
    info "Using SSH_KEY=$SSH_KEY"

    vagrant up "${machines[@]}" --provider=virtualbox
    info "VMs provisioned successfully"
}

vagrant_halt() {
    load_env
    require_cmd vagrant || return 1
    cd "$PROJECT_ROOT"
    if [[ $# -eq 0 ]]; then
        header "Halting all VMs"
        vagrant halt
    else
        header "Halting VMs: $*"
        vagrant halt "$@"
    fi
}

vagrant_destroy() {
    load_env
    require_cmd vagrant || return 1
    cd "$PROJECT_ROOT"
    if [[ $# -eq 0 ]]; then
        confirm "Destroy ALL VMs?" || return 0
        vagrant destroy -f
    else
        confirm "Destroy VMs: $*?" || return 0
        vagrant destroy -f "$@"
    fi
    info "VMs destroyed"
}

vagrant_status() {
    load_env
    require_cmd vagrant || return 1
    cd "$PROJECT_ROOT"
    vagrant status
}

vagrant_ssh() {
    load_env
    require_cmd vagrant || return 1
    cd "$PROJECT_ROOT"
    local machine="${1:?Machine name required. Usage: kubewekend vagrant ssh <machine>}"
    vagrant ssh "$machine"
}

vagrant_reload() {
    load_env
    require_cmd vagrant || return 1
    cd "$PROJECT_ROOT"
    if [[ $# -eq 0 ]]; then
        vagrant reload
    else
        vagrant reload "$@"
    fi
}
