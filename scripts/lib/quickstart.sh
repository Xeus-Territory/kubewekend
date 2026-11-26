#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# Kubewekend CLI library: quickstart command
# =============================================================================
# Guided quick-start workflows.
# Sourced by scripts/setup.sh (never run it directly). Functions only: nothing here runs until main() calls it.
# PROJECT_ROOT, HOST_VARS_DIR and the other path variables come from setup.sh; colours and info/warn/error from core.sh.

# ---------------------------------------------------------------------------
# COMMAND: quickstart
# ---------------------------------------------------------------------------
cmd_quickstart_help() {
    cat <<'EOF'
kubewekend quickstart - Guided quick-start workflows

SUBCOMMANDS
  kind-local            Full Kind setup on localhost (no Vagrant needed)
  kind-vagrant          Kind cluster using Vagrant VMs
  k3s-vagrant           K3s cluster using Vagrant VMs
  k3s-remote            K3s cluster on remote VPS
  rke2-vagrant          RKE2 cluster using Vagrant VMs
  rke2-remote           RKE2 cluster on remote VPS

EXAMPLES
  ./scripts/setup.sh quickstart kind-local
  ./scripts/setup.sh quickstart kind-vagrant
  ./scripts/setup.sh quickstart k3s-vagrant
  ./scripts/setup.sh quickstart k3s-remote
  ./scripts/setup.sh quickstart rke2-vagrant
  ./scripts/setup.sh quickstart rke2-remote
EOF
}

cmd_quickstart() {
    local sub="${1:-help}"; shift || true
    case "$sub" in
        kind-local)   qs_kind_local "$@" ;;
        kind-vagrant) qs_kind_vagrant "$@" ;;
        k3s-vagrant)  qs_k3s_vagrant "$@" ;;
        k3s-remote)   qs_k3s_remote "$@" ;;
        rke2-vagrant) qs_rke2_vagrant "$@" ;;
        rke2-remote)  qs_rke2_remote "$@" ;;
        *)            cmd_quickstart_help ;;
    esac
}

qs_kind_local() {
    header "Quick Start: Kind on Localhost"
    echo "This workflow sets up a Kind cluster directly on your machine (not recommended)."
    echo "Requirements: docker, ansible"
    echo "NOTE: With networkForwarding enabled, socat services bind host port 80/443."
    echo "      Remember to run 'kind destroy' (or disable the services) when you finish."
    echo ""
    confirm "Start Kind local setup?" || return 0

    cat <<'GUIDE'

Step-by-step:
  1. Make sure Docker is running
  2. Point the master host to your own machine (keep the hostname k8s-master-machine):

     [standalone-masters]
     k8s-master-machine ansible_host=127.0.0.1 ansible_connection=local

  3. Run setup:
     ./scripts/setup.sh kind setup --host k8s-master-machine

  4. Verify:
     kubectl cluster-info --context kind-kubewekend

  5. Install utilities:
     ./scripts/setup.sh kind utils certmanager ingress_test

  6. Cleanup:
     ./scripts/setup.sh kind destroy

GUIDE
}

qs_kind_vagrant() {
    header "Quick Start: Kind on Vagrant VMs"
    cat <<'GUIDE'

Step-by-step:

  1. Initialize environment:
     ./scripts/setup.sh env init
     # Edit .env with your SSH user and key path

  2. Provision master VM:
     ./scripts/setup.sh vagrant up k8s-master-machine

  3. Generate inventory:
     ./scripts/setup.sh inventory generate

  4. Test connectivity:
     ./scripts/setup.sh inventory ping

  5. Setup Kind cluster:
     ./scripts/setup.sh kind setup

  6. Install utilities (optional):
     ./scripts/setup.sh kind utils ingress_test certmanager

  7. Teardown:
     ./scripts/setup.sh kind destroy
     ./scripts/setup.sh vagrant destroy k8s-master-machine

GUIDE
}

qs_k3s_vagrant() {
    header "Quick Start: K3s on Vagrant VMs"
    cat <<'GUIDE'

Step-by-step:

  1. Initialize environment:
     ./scripts/setup.sh env init

  2. Provision VMs (1 master + 1 worker):
     ./scripts/setup.sh vagrant up k8s-master-machine k8s-worker-machine-1

  3. Generate inventory:
     ./scripts/setup.sh inventory generate

  4. Test connectivity:
     ./scripts/setup.sh inventory ping

  5. Configure cluster settings:
     # Edit ansible/inventories/host_vars/master.yaml
     # Key settings: k3sCluster.version, cni.type, loadBalancer, ingress

  6. Setup K3s cluster:
     ./scripts/setup.sh k3s setup

  7. Get kubeconfig:
     ssh vagrant@192.168.56.99 'sudo -S cat /etc/rancher/k3s/k3s.yaml' > ~/.kube/config
     # Replace 127.0.0.1 with 192.168.56.99 in the kubeconfig
     sed -i "s/127.0.0.1/192.168.56.99/g" ~/.kube/config

  8. Install utilities:
     ./scripts/setup.sh k3s utils ingress_test certmanager

  9. Teardown:
     ./scripts/setup.sh k3s destroy
     ./scripts/setup.sh vagrant destroy

  --- HA Variant (3 masters + 1 worker) ---

  a. Edit ansible/inventories/hosts with HA groups (ha_master_init, ha_master_join, ha_worker)
  b. Review k3sCluster.highAvailability.dataStorage in master.yaml (etcd | postgres; there is no enable switch)
  c. Run: ./scripts/setup.sh k3s ha-setup

GUIDE
}

qs_k3s_remote() {
    header "Quick Start: K3s on Remote VPS"
    cat <<'GUIDE'

Step-by-step:

  1. Configure remote inventory:
     ./scripts/setup.sh inventory set-remote
     # Follow the interactive prompts

  2. Test connectivity:
     ./scripts/setup.sh inventory ping

  3. Configure cluster settings:
     # Edit ansible/inventories/host_vars/master.yaml
     # Important: set k3sCluster.tlsSANs to include your VPS IP/domain
     # Important: with loadBalancer.type: metallb, set k3sCluster.loadBalancer.ippool.cidr to a free range of your VPS network

  4. Setup K3s:
     ./scripts/setup.sh k3s setup

  5. Get kubeconfig:
     ssh <user>@<vps-ip> 'sudo cat /etc/rancher/k3s/k3s.yaml' > ~/.kube/config
     or
     ssh <user>@<vps-ip> 'cat /home/<user>/.kube/config' > ~/.kube/config
     # Replace 127.0.0.1 with your VPS IP in the kubeconfig
     sed -i "s/127.0.0.1/<vps-ip>/g" ~/.kube/config

  6. Install utilities:
     ./scripts/setup.sh k3s utils certmanager gitops

  7. Teardown:
     ./scripts/setup.sh k3s destroy

GUIDE
}

qs_rke2_vagrant() {
    header "Quick Start: RKE2 on Vagrant VMs"
    cat <<'GUIDE'

Step-by-step:

  1. Initialize environment:
     ./scripts/setup.sh env init

  2. Provision VMs (1 master + 1 worker):
     ./scripts/setup.sh vagrant up k8s-master-machine k8s-worker-machine-1

  3. Generate inventory:
     ./scripts/setup.sh inventory generate

  4. Test connectivity:
     ./scripts/setup.sh inventory ping

  5. Configure cluster settings:
     # Edit ansible/inventories/host_vars/master.yaml
     # Key settings: rke2Cluster.version, cni.type, loadBalancer, ingress

  6. Setup RKE2 cluster (master first, then each worker; RKE2 takes a few minutes to start):
     ./scripts/setup.sh rke2 setup --host k8s-master-machine
     ./scripts/setup.sh rke2 setup --host k8s-worker-machine-1

  7. Get kubeconfig:
     ssh vagrant@192.168.56.99 'sudo -S cat /etc/rancher/rke2/rke2.yaml' > ~/.kube/config
     # Replace 127.0.0.1 with 192.168.56.99 in the kubeconfig
     sed -i "s/127.0.0.1/192.168.56.99/g" ~/.kube/config

  8. Install utilities:
     ./scripts/setup.sh rke2 utils ingress_test certmanager

  9. Teardown:
     ./scripts/setup.sh rke2 destroy
     ./scripts/setup.sh vagrant destroy

  --- HA Variant (3 masters + 1 worker) ---

  a. Edit ansible/inventories/hosts with HA groups (ha_master_init, ha_master_join, ha_worker)
  b. Review rke2Cluster.highAvailability.dataStorage in master.yaml (etcd | postgres; there is no enable switch)
  c. Run: ./scripts/setup.sh rke2 ha-setup

GUIDE
}

qs_rke2_remote() {
    header "Quick Start: RKE2 on Remote VPS"
    cat <<'GUIDE'

Step-by-step:

  1. Configure remote inventory:
     ./scripts/setup.sh inventory set-remote
     # Follow the interactive prompts

  2. Test connectivity:
     ./scripts/setup.sh inventory ping

  3. Configure cluster settings:
     # Edit ansible/inventories/host_vars/master.yaml
     # Important: set rke2Cluster.tlsSANs to include your VPS IP/domain
     # Important: with loadBalancer.type: metallb, set rke2Cluster.loadBalancer.ippool.cidr to a free range of your VPS network

  4. Setup RKE2 (master first, then each worker):
     ./scripts/setup.sh rke2 setup --host k8s-master-machine
     ./scripts/setup.sh rke2 setup --host k8s-worker-machine-1

  5. Get kubeconfig:
     ssh <user>@<vps-ip> 'sudo -S cat /etc/rancher/rke2/rke2.yaml' > ~/.kube/config
     or
     ssh <user>@<vps-ip> 'cat /home/<user>/.kube/config' > ~/.kube/config
     # Replace 127.0.0.1 with your VPS IP in the kubeconfig
     sed -i "s/127.0.0.1/<vps-ip>/g" ~/.kube/config

  6. Install utilities:
     ./scripts/setup.sh rke2 utils certmanager gitops

  7. Teardown:
     ./scripts/setup.sh rke2 destroy

GUIDE
}
