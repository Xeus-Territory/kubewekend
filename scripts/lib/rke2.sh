#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# Kubewekend CLI library: rke2 command
# =============================================================================
# RKE2 cluster setup (standalone and HA), destroy and utilities.
# Sourced by scripts/setup.sh (never run it directly). Functions only: nothing here runs until main() calls it.
# PROJECT_ROOT, HOST_VARS_DIR and the other path variables come from setup.sh; colours and info/warn/error from core.sh.

# ---------------------------------------------------------------------------
# COMMAND: rke2
# ---------------------------------------------------------------------------
cmd_rke2_help() {
    cat <<'EOF'
kubewekend rke2 - RKE2 (security-focused Kubernetes) cluster management

SUBCOMMANDS
  setup                 Setup standalone RKE2 cluster (1 master + N workers)
  ha-setup              Setup HA RKE2 cluster (3+ masters + N workers)
  destroy               Remove RKE2 from all nodes
  utils [tags...]       Run K8s utilities (see UTILITY TAGS below)
  utils --list          List utility tags with options and status from master.yaml
                        (setup options: ./scripts/setup.sh config --list rke2)

OPTIONS
  --host, -H <name>    Ansible host target (default: k8s-master-machine)
  --dry-run             Show ansible command without executing
  --skip-tags <tags>    Comma-separated tags to skip (e.g: install_common)
  --extra-vars <vars>   Additional ansible extra-vars (key=value)
  --ask-become-pass      Prompt for sudo password when needed

EOF
    setup_help_section rke2
    utils_help_section
    cat <<'EOF'
EXAMPLES
  # --- Standalone RKE2 (Vagrant VMs) ---
  # The playbook targets one host at a time and auto-detects master vs worker
  # from the hostname pattern (*master* / *worker*). Run per host: master first.

  # 1. Provision VMs
  ./scripts/setup.sh vagrant up k8s-master-machine k8s-worker-machine-1

  # 2. Generate inventory
  ./scripts/setup.sh inventory generate

  # 3. Setup master
  ./scripts/setup.sh rke2 setup --host k8s-master-machine

  # 4. Setup each worker (skipping install_common if already done on master)
  ./scripts/setup.sh rke2 setup --host k8s-worker-machine-1
  ./scripts/setup.sh rke2 setup --host k8s-worker-machine-2 --skip-tags install_common

  # --- Standalone RKE2 (Remote VPS) ---

  # 1. Configure remote inventory
  ./scripts/setup.sh inventory set-remote

  # 2. Test connectivity
  ./scripts/setup.sh inventory ping

  # 3. Setup master then workers
  ./scripts/setup.sh rke2 setup --host k8s-master-machine
  ./scripts/setup.sh rke2 setup --host k8s-worker-machine-1

  # --- HA RKE2 (3 masters + worker) ---

  # 1. Edit ansible/inventories/hosts with HA groups (ha_master_init, ha_master_join, ha_worker).
  #    The groups decide how many control-plane nodes you get: there is no enable switch or replica count
  # 2. Review rke2Cluster.highAvailability.dataStorage in ansible/inventories/host_vars/master.yaml
  #    (type: etcd | postgres; externalDatabase is only read for postgres)
  ./scripts/setup.sh rke2 ha-setup

  # --- Re-run without reinstalling tools ---
  ./scripts/setup.sh rke2 setup --host k8s-master-machine --skip-tags install_common

  # --- Utilities ---
  ./scripts/setup.sh rke2 utils certmanager gitops dashboard
  ./scripts/setup.sh rke2 utils --list

  # --- Teardown ---
  ./scripts/setup.sh rke2 destroy
EOF
}

cmd_rke2() {
    local sub="${1:-help}"; shift || true
    case "$sub" in
        setup)    rke2_setup "$@" ;;
        ha-setup) rke2_ha_setup "$@" ;;
        destroy)  rke2_destroy "$@" ;;
        utils)    rke2_utils "$@" ;;
        *)        cmd_rke2_help ;;
    esac
}

rke2_setup() {
    parse_ansible_opts "$@"
    [[ "$HOST_NAME" == *master* ]] && _check_archived_classes rke2
    [[ "$HOST_NAME" == *master* ]] && _check_removed_keys rke2
    header "Setting up RKE2 node: $HOST_NAME"
    # The playbook detects master vs worker via hostname pattern:
    #   *master* → loads master.yaml → installs RKE2 server
    #   *worker* → loads worker.yaml → joins cluster as agent
    # Call once per host: master first, then each worker.
    run_ansible_playbook "rke2-playbook.yaml" "install_common,setup_rke2"
    info "RKE2 node setup complete: $HOST_NAME"
    if [[ "$HOST_NAME" == *master* ]]; then
        echo ""
        info "Retrieve kubeconfig after all nodes are set up:"
        echo "  ssh <master> 'sudo -S cat /etc/rancher/rke2/rke2.yaml' > ~/.kube/config"
        echo "  # Then replace 127.0.0.1 with the master node IP in the kubeconfig"
        echo "  sed -i 's/127.0.0.1/<master_ip>/g' ~/.kube/config"
    fi
}

rke2_ha_setup() {
    parse_ansible_opts "$@"
    _check_archived_classes rke2
    _check_removed_keys rke2
    header "Setting up HA RKE2 cluster"

    info "Ensure you have configured:"
    echo "  - ansible/inventories/hosts (ha_master_init, ha_master_join, ha_worker groups)"
    echo "  - ansible/inventories/host_vars/master.yaml (rke2Cluster.highAvailability.dataStorage: etcd | postgres)"
    echo ""
    confirm "Proceed with HA RKE2 setup?" || return 0

    run_ansible_playbook "rke2-ha-playbook.yaml" ""
    info "HA RKE2 cluster setup complete!"
}

rke2_destroy() {
    parse_ansible_opts "$@"
    header "Removing RKE2 from all nodes"
    confirm "This will uninstall RKE2 from all inventory nodes. Continue?" || return 0
    run_ansible_playbook "rke2-remove-playbook.yaml" ""
    info "RKE2 removed from all nodes"
}

rke2_utils() { run_utils rke2 "$@"; }
