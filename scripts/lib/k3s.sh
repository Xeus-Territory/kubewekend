#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# Kubewekend CLI library: k3s command
# =============================================================================
# K3s cluster setup (standalone and HA), destroy and utilities.
# Sourced by scripts/setup.sh (never run it directly). Functions only: nothing here runs until main() calls it.
# PROJECT_ROOT, HOST_VARS_DIR and the other path variables come from setup.sh; colours and info/warn/error from core.sh.

# ---------------------------------------------------------------------------
# COMMAND: k3s
# ---------------------------------------------------------------------------
cmd_k3s_help() {
    cat <<'EOF'
kubewekend k3s - K3s lightweight Kubernetes cluster management

SUBCOMMANDS
  setup                 Setup standalone K3s cluster (1 master + N workers)
  ha-setup              Setup HA K3s cluster (3+ masters + N workers)
  destroy               Remove K3s from all nodes
  utils [tags...]       Run K8s utilities (see UTILITY TAGS below)
  utils --list          List utility tags with options and status from master.yaml
                        (setup options: ./scripts/setup.sh config --list k3s)

OPTIONS
  --host, -H <name>    Ansible host target (default: k8s-master-machine)
  --dry-run             Show ansible command without executing
  --skip-tags <tags>    Comma-separated tags to skip (e.g: install_common)
  --extra-vars <vars>   Additional ansible extra-vars (key=value)
  --ask-become-pass      Prompt for sudo password when needed

EOF
    setup_help_section k3s
    utils_help_section
    cat <<'EOF'
EXAMPLES
  # --- Standalone K3s (Vagrant VMs) ---
  # The playbook targets one host at a time and auto-detects master vs worker
  # from the hostname pattern (*master* / *worker*). Run per host: master first.

  # 1. Provision VMs
  ./scripts/setup.sh vagrant up k8s-master-machine k8s-worker-machine-1

  # 2. Generate inventory
  ./scripts/setup.sh inventory generate

  # 3. Setup master
  ./scripts/setup.sh k3s setup --host k8s-master-machine

  # 4. Setup each worker (skipping install_common if already done on master)
  ./scripts/setup.sh k3s setup --host k8s-worker-machine-1
  ./scripts/setup.sh k3s setup --host k8s-worker-machine-2 --skip-tags install_common

  # --- Standalone K3s (Remote VPS) ---

  # 1. Configure remote inventory
  ./scripts/setup.sh inventory set-remote

  # 2. Test connectivity
  ./scripts/setup.sh inventory ping

  # 3. Setup master then workers
  ./scripts/setup.sh k3s setup --host k8s-master-machine
  ./scripts/setup.sh k3s setup --host k8s-worker-machine-1

  # --- HA K3s (3 masters + worker) ---

  # 1. Edit ansible/inventories/hosts with HA groups (ha_master_init, ha_master_join, ha_worker).
  #    The groups decide how many control-plane nodes you get: there is no enable switch or replica count
  # 2. Review k3sCluster.highAvailability.dataStorage in ansible/inventories/host_vars/master.yaml
  #    (type: etcd | postgres; externalDatabase is only read for postgres)
  ./scripts/setup.sh k3s ha-setup

  # --- Re-run without reinstalling tools ---
  ./scripts/setup.sh k3s setup --host k8s-master-machine --skip-tags install_common

  # --- Utilities ---
  ./scripts/setup.sh k3s utils certmanager gitops dashboard
  ./scripts/setup.sh k3s utils --list

  # --- Teardown ---
  ./scripts/setup.sh k3s destroy
EOF
}

cmd_k3s() {
    local sub="${1:-help}"; shift || true
    case "$sub" in
        setup)    k3s_setup "$@" ;;
        ha-setup) k3s_ha_setup "$@" ;;
        destroy)  k3s_destroy "$@" ;;
        utils)    k3s_utils "$@" ;;
        *)        cmd_k3s_help ;;
    esac
}

k3s_setup() {
    parse_ansible_opts "$@"
    [[ "$HOST_NAME" == *master* ]] && _check_removed_keys k3s
    header "Setting up K3s node: $HOST_NAME"
    # The playbook detects master vs worker via hostname pattern:
    #   *master* → loads master.yaml → installs K3s server
    #   *worker* → loads worker.yaml → joins cluster as agent
    # Call once per host: master first, then each worker.
    run_ansible_playbook "k3s-playbook.yaml" "install_common,setup_k3s"
    info "K3s node setup complete: $HOST_NAME"
    if [[ "$HOST_NAME" == *master* ]]; then
        echo ""
        info "Retrieve kubeconfig after all nodes are set up:"
        echo "  ssh <master> 'sudo -S cat /etc/rancher/k3s/k3s.yaml' > ~/.kube/config"
        echo "  # Then replace 127.0.0.1 with the master node IP in the kubeconfig"
        echo "  sed -i 's/127.0.0.1/<master_ip>/g' ~/.kube/config"
    fi
}

k3s_ha_setup() {
    parse_ansible_opts "$@"
    _check_removed_keys k3s
    header "Setting up HA K3s cluster"

    info "Ensure you have configured:"
    echo "  - ansible/inventories/hosts (ha_master_init, ha_master_join, ha_worker groups)"
    echo "  - ansible/inventories/host_vars/master.yaml (k3sCluster.highAvailability.dataStorage: etcd | postgres)"
    echo ""
    confirm "Proceed with HA K3s setup?" || return 0

    run_ansible_playbook "k3s-ha-playbook.yaml" ""
    info "HA K3s cluster setup complete!"
}

k3s_destroy() {
    parse_ansible_opts "$@"
    header "Removing K3s from all nodes"
    confirm "This will uninstall K3s from all inventory nodes. Continue?" || return 0
    run_ansible_playbook "k3s-remove-playbook.yaml" ""
    info "K3s removed from all nodes"
}

k3s_utils() { run_utils k3s "$@"; }
