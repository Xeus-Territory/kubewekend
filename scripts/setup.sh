#!/usr/bin/env bash
# =============================================================================
# Kubewekend CLI - Setup & Operate Kind / K3s / RKE2 Kubernetes Clusters
# =============================================================================
# A unified CLI for provisioning VMs (Vagrant/VPS), configuring ansible
# inventories, deploying Kind/K3s/RKE2 clusters, and managing K8s utilities.
#
# Usage:  ./scripts/setup.sh <command> [subcommand] [options]
# Help:   ./scripts/setup.sh help
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants & Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ANSIBLE_DIR="$PROJECT_ROOT/ansible"
INVENTORY_DIR="$ANSIBLE_DIR/inventories"
HOSTS_FILE="$INVENTORY_DIR/hosts"
HOST_VARS_DIR="$INVENTORY_DIR/host_vars"
ENV_FILE="$PROJECT_ROOT/.env"
TEMPLATE_ENV="$PROJECT_ROOT/template.env"

# ---------------------------------------------------------------------------
# Libraries: one file per concern in scripts/lib/ (functions and tables only; nothing runs until main)
# ---------------------------------------------------------------------------
# shellcheck source=lib/core.sh
source "$SCRIPT_DIR/lib/core.sh"
# shellcheck source=lib/debug.sh
source "$SCRIPT_DIR/lib/debug.sh"
# shellcheck source=lib/yaml.sh
source "$SCRIPT_DIR/lib/yaml.sh"
# shellcheck source=lib/ansible.sh
source "$SCRIPT_DIR/lib/ansible.sh"
# shellcheck source=lib/utilities.sh
source "$SCRIPT_DIR/lib/utilities.sh"
# shellcheck source=lib/options.sh
source "$SCRIPT_DIR/lib/options.sh"
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"
# shellcheck source=lib/config_show.sh
source "$SCRIPT_DIR/lib/config_show.sh"
# shellcheck source=lib/env.sh
source "$SCRIPT_DIR/lib/env.sh"
# shellcheck source=lib/vagrant.sh
source "$SCRIPT_DIR/lib/vagrant.sh"
# shellcheck source=lib/inventory.sh
source "$SCRIPT_DIR/lib/inventory.sh"
# shellcheck source=lib/network.sh
source "$SCRIPT_DIR/lib/network.sh"
# shellcheck source=lib/kind.sh
source "$SCRIPT_DIR/lib/kind.sh"
# shellcheck source=lib/k3s.sh
source "$SCRIPT_DIR/lib/k3s.sh"
# shellcheck source=lib/rke2.sh
source "$SCRIPT_DIR/lib/rke2.sh"
# shellcheck source=lib/quickstart.sh
source "$SCRIPT_DIR/lib/quickstart.sh"
# shellcheck source=lib/status.sh
source "$SCRIPT_DIR/lib/status.sh"
# shellcheck source=lib/versions_registry.sh
source "$SCRIPT_DIR/lib/versions_registry.sh"
# shellcheck source=lib/versions.sh
source "$SCRIPT_DIR/lib/versions.sh"

# ---------------------------------------------------------------------------
# Main help
# ---------------------------------------------------------------------------
show_help() {
    cat <<EOF
${BOLD}Kubewekend CLI${NC} - Setup & Operate Kubernetes Clusters for Workshop/Demo

${BOLD}USAGE${NC}
  ./scripts/setup.sh <command> [subcommand] [options]

${BOLD}COMMANDS${NC}
  ${CYAN}env${NC}            Manage environment (check tools, init .env)
  ${CYAN}vagrant${NC}        Vagrant VM lifecycle (up, halt, destroy, ssh)
  ${CYAN}inventory${NC}      Ansible inventory management (generate, ping, remote VPS)
  ${CYAN}kind${NC}           Kind cluster operations (setup, destroy, utilities)
  ${CYAN}k3s${NC}            K3s cluster operations (setup, ha-setup, destroy, utilities)
  ${CYAN}rke2${NC}           RKE2 cluster operations (setup, ha-setup, destroy, utilities)
  ${CYAN}network${NC}        VirtualBox NAT network management
  ${CYAN}quickstart${NC}     Guided quick-start workflows with examples
  ${CYAN}config${NC}         View/edit cluster configuration, list supported options (config --list)
  ${CYAN}versions${NC}       List and bump pinned versions of charts, tools and manifests
  ${CYAN}status${NC}         Show overall project status
  ${CYAN}help${NC}           Show this help message

${BOLD}QUICK REFERENCE${NC}
  # Check prerequisites
  ./scripts/setup.sh env check

  # --- Kind on Vagrant ---
  ./scripts/setup.sh vagrant up k8s-master-machine
  ./scripts/setup.sh inventory generate
  ./scripts/setup.sh kind setup
  ./scripts/setup.sh kind utils certmanager ingress_test

  # --- K3s on Vagrant (standalone) ---
  ./scripts/setup.sh vagrant up k8s-master-machine k8s-worker-machine-1
  ./scripts/setup.sh inventory generate
  ./scripts/setup.sh k3s setup
  ./scripts/setup.sh k3s utils certmanager gitops

  # --- K3s on Remote VPS ---
  ./scripts/setup.sh inventory set-remote
  ./scripts/setup.sh inventory ping
  ./scripts/setup.sh k3s setup

  # --- K3s HA Cluster ---
  # (fill the HA groups in hosts and review k3sCluster.highAvailability.dataStorage in master.yaml first)
  ./scripts/setup.sh k3s ha-setup

  # --- RKE2 on Vagrant (standalone) ---
  ./scripts/setup.sh vagrant up k8s-master-machine k8s-worker-machine-1
  ./scripts/setup.sh inventory generate
  ./scripts/setup.sh rke2 setup --host k8s-master-machine
  ./scripts/setup.sh rke2 setup --host k8s-worker-machine-1
  ./scripts/setup.sh rke2 utils certmanager gitops

  # --- RKE2 HA Cluster ---
  # (fill the HA groups in hosts and review rke2Cluster.highAvailability.dataStorage in master.yaml first)
  ./scripts/setup.sh rke2 ha-setup

${BOLD}SUBCOMMAND HELP${NC}
  ./scripts/setup.sh <command> help

${BOLD}DEBUGGING${NC}
  ./scripts/setup.sh --debug <command> ...     Trace every command (file:line function) and print the call stack
                                               of the first failure. --debug must be the first argument
  KUBEWEKEND_DEBUG=1 ./scripts/setup.sh ...    Same, from the environment
  KUBEWEKEND_DEBUG_LOG=/tmp/kw.log ...         Write the trace to a file instead of the terminal
  ./scripts/setup.sh config validate           Check master.yaml for settings no playbook reads

EOF
}

# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------
# shellcheck disable=SC2178,SC2128  # false positive: `cmd` is a local array in run_ansible_playbook, a plain string here
main() {
    local cmd="${1:-help}"; shift || true
    case "$cmd" in
        env)        cmd_env "$@" ;;
        vagrant)    cmd_vagrant "$@" ;;
        inventory)  cmd_inventory "$@" ;;
        kind)       cmd_kind "$@" ;;
        k3s)        cmd_k3s "$@" ;;
        rke2)       cmd_rke2 "$@" ;;
        network)    cmd_network "$@" ;;
        quickstart) cmd_quickstart "$@" ;;
        config)     cmd_config "$@" ;;
        versions)   cmd_versions "$@" ;;
        status)     cmd_status ;;
        help|--help|-h) show_help ;;
        *)
            error "Unknown command: $cmd"
            echo ""
            show_help
            return 1
            ;;
    esac
}

# Debug mode: `--debug` as the first argument, or KUBEWEKEND_DEBUG=1 (see lib/debug.sh)
if [[ "${1:-}" == "--debug" ]]; then
    shift
    KUBEWEKEND_DEBUG=1
fi
[[ "${KUBEWEKEND_DEBUG:-}" == "1" ]] && _debug_on

main "$@"
