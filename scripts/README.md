# Kubewekend CLI

> Unified Bash CLI to setup and operate **Kind** / **K3s** Kubernetes clusters for workshops, demos, and local experiments.

---

## Table of Contents

- [Kubewekend CLI](#kubewekend-cli)
  - [Table of Contents](#table-of-contents)
  - [Prerequisites](#prerequisites)
  - [Getting Started](#getting-started)
  - [CLI Reference](#cli-reference)
    - [env — Environment Management](#env--environment-management)
    - [vagrant — VM Lifecycle](#vagrant--vm-lifecycle)
    - [inventory — Ansible Inventory](#inventory--ansible-inventory)
    - [kind — Kind Cluster Operations](#kind--kind-cluster-operations)
    - [k3s — K3s Cluster Operations](#k3s--k3s-cluster-operations)
    - [network — VirtualBox NAT Network](#network--virtualbox-nat-network)
    - [config — Cluster Configuration](#config--cluster-configuration)
    - [status — Project Dashboard](#status--project-dashboard)
    - [quickstart — Guided Workflows](#quickstart--guided-workflows)
  - [Global Options (kind / k3s)](#global-options-kind--k3s)
  - [Workflow Examples](#workflow-examples)
    - [1. Kind on Vagrant (VirtualBox)](#1-kind-on-vagrant-virtualbox)
    - [2. K3s Standalone on Vagrant](#2-k3s-standalone-on-vagrant)
    - [3. K3s on Remote VPS](#3-k3s-on-remote-vps)
    - [4. K3s High-Availability (HA)](#4-k3s-high-availability-ha)
    - [5. Kind on Localhost (No Vagrant)](#5-kind-on-localhost-no-vagrant)
  - [Available Utility Tags](#available-utility-tags)
  - [Project Structure](#project-structure)
  - [Configuration Files](#configuration-files)
  - [Contributing](#contributing)

---

## Prerequisites

| Tool | Required | Purpose |
|------|----------|---------|
| [vagrant](https://developer.hashicorp.com/vagrant/docs/installation) | Yes* | VM provisioning |
| [VirtualBox](https://www.virtualbox.org/wiki/Downloads) | Yes* | VM provider |
| [ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) | Yes | Cluster orchestration |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | Yes | Kubernetes CLI |
| [helm](https://helm.sh/docs/intro/install/) | Yes | Helm chart management |
| [docker](https://docs.docker.com/engine/install/) | Optional | Required for Kind clusters |
| [kind](https://kind.sigs.k8s.io/docs/user/quick-start#installation) | Optional | Kind cluster binary (installed by playbook) |
| [jq](https://jqlang.github.io/jq/download/) | Optional | JSON processing |

> \* Vagrant + VirtualBox are only required for local VM workflows. For remote VPS, only ansible + SSH are needed.

Verify with:

```bash
./scripts/setup.sh env check
```

---

## Getting Started

```bash
# 1. Make the script executable
chmod +x ./scripts/setup.sh

# 2. Initialize .env from template
./scripts/setup.sh env init
# Edit .env with your SSH_USER and SSH_KEY_LOCATION

# 3. Check tools
./scripts/setup.sh env check

# 4. Follow a quickstart guide
./scripts/setup.sh quickstart kind-vagrant
./scripts/setup.sh quickstart k3s-vagrant
./scripts/setup.sh quickstart k3s-remote
```

---

## CLI Reference

```
./scripts/setup.sh <command> [subcommand] [options]
./scripts/setup.sh help                        # global help
./scripts/setup.sh <command> help              # per-command help
```

### env — Environment Management

| Subcommand | Description |
|------------|-------------|
| `env check` | Verify all required/optional tools are installed |
| `env init` | Create `.env` from `template.env` |
| `env show` | Print current environment variables |

```bash
./scripts/setup.sh env check
./scripts/setup.sh env init
./scripts/setup.sh env show
```

### vagrant — VM Lifecycle

| Subcommand | Description |
|------------|-------------|
| `vagrant up [machines...]` | Provision VMs (default: `k8s-master-machine`) |
| `vagrant halt [machines...]` | Stop VMs |
| `vagrant destroy [machines...]` | Destroy VMs (with confirmation) |
| `vagrant status` | Show VM status |
| `vagrant ssh <machine>` | SSH into a VM |
| `vagrant reload [machines...]` | Reload VMs |

```bash
# Provision master
./scripts/setup.sh vagrant up k8s-master-machine

# Provision master + 2 workers
./scripts/setup.sh vagrant up k8s-master-machine k8s-worker-machine-1 k8s-worker-machine-2

# Provision workers by regex
./scripts/setup.sh vagrant up "/k8s-worker-machine-[1-2]/"

# SSH into master
./scripts/setup.sh vagrant ssh k8s-master-machine

# Halt all
./scripts/setup.sh vagrant halt
```

### inventory — Ansible Inventory

| Subcommand | Description |
|------------|-------------|
| `inventory generate` | Auto-generate inventory from running Vagrant VMs |
| `inventory show` | Display current inventory file |
| `inventory ping [group]` | Test SSH connectivity (defaults to `all`) |
| `inventory set-remote` | Interactive wizard to configure remote VPS inventory |

```bash
# Auto-generate from vagrant
./scripts/setup.sh inventory generate

# Test connectivity to all hosts
./scripts/setup.sh inventory ping

# Test only standalone masters
./scripts/setup.sh inventory ping standalone-masters

# Setup remote VPS inventory (interactive)
./scripts/setup.sh inventory set-remote
```

### kind — Kind Cluster Operations

| Subcommand | Description |
|------------|-------------|
| `kind setup` | Install tools + create Kind cluster + configure networking |
| `kind destroy` | Remove Kind cluster and related components |
| `kind utils <tags...>` | Install K8s utilities by [tag](#available-utility-tags) |

```bash
# Full setup
./scripts/setup.sh kind setup

# Setup targeting a specific host
./scripts/setup.sh kind setup --host k8s-master-machine

# Preview without executing
./scripts/setup.sh kind setup --dry-run

# Destroy
./scripts/setup.sh kind destroy

# Install utilities
./scripts/setup.sh kind utils certmanager dashboard
./scripts/setup.sh kind utils ingress_test apigateway_test
```

### k3s — K3s Cluster Operations

| Subcommand | Description |
|------------|-------------|
| `k3s setup` | Setup standalone K3s cluster (1 master + N workers) |
| `k3s ha-setup` | Setup HA K3s cluster (3+ masters + N workers) |
| `k3s destroy` | Uninstall K3s from all inventory nodes |
| `k3s utils <tags...>` | Install K8s utilities by [tag](#available-utility-tags) |

```bash
# Standalone setup
./scripts/setup.sh k3s setup

# HA setup (requires inventory + master.yaml pre-configured)
./scripts/setup.sh k3s ha-setup

# Destroy
./scripts/setup.sh k3s destroy

# Utilities
./scripts/setup.sh k3s utils certmanager gitops dashboard
```

### network — VirtualBox NAT Network

| Subcommand | Description |
|------------|-------------|
| `network hookup [name] [cidr]` | Create NAT network and attach VMs (default: `KubewekendNet 10.0.69.0/24`) |
| `network return-nat` | Revert all VMs back to default NAT |
| `network status` | List VirtualBox NAT networks |

```bash
./scripts/setup.sh network hookup
./scripts/setup.sh network hookup MyNet 10.0.100.0/24
./scripts/setup.sh network return-nat
./scripts/setup.sh network status
```

### config — Cluster Configuration

| Subcommand | Description |
|------------|-------------|
| `config show` | Print `ansible/inventories/host_vars/master.yaml` |
| `config edit` | Open `master.yaml` in `$EDITOR` |
| `config worker-show` | Print `worker.yaml` |
| `config worker-edit` | Open `worker.yaml` in `$EDITOR` |

```bash
./scripts/setup.sh config show
./scripts/setup.sh config edit
```

### status — Project Dashboard

Shows Vagrant VMs, inventory groups, kubectl contexts, and Docker Kind containers.

```bash
./scripts/setup.sh status
```

### quickstart — Guided Workflows

| Subcommand | Description |
|------------|-------------|
| `quickstart kind-local` | Kind on localhost (no Vagrant) |
| `quickstart kind-vagrant` | Kind on Vagrant VMs |
| `quickstart k3s-vagrant` | K3s on Vagrant VMs |
| `quickstart k3s-remote` | K3s on remote VPS |

```bash
./scripts/setup.sh quickstart kind-vagrant
./scripts/setup.sh quickstart k3s-remote
```

---

## Global Options (kind / k3s)

These options are available on `kind setup/destroy/utils` and `k3s setup/ha-setup/destroy/utils`:

| Option | Description |
|--------|-------------|
| `--host, -H <name>` | Ansible host target (default: `k8s-master-machine`) |
| `--dry-run` | Print the ansible command without executing |
| `--skip-tags <tags>` | Comma-separated ansible tags to skip |
| `--extra-vars <vars>` | Additional ansible extra-vars (`key=value`) |

```bash
# Dry run
./scripts/setup.sh kind setup --dry-run

# Target a different host
./scripts/setup.sh k3s setup --host my-vps-node

# Skip specific tasks
./scripts/setup.sh kind setup --skip-tags setup_cni

# Pass extra variables
./scripts/setup.sh kind setup --extra-vars "kindCluster_image=kindest/node:v1.30.13"
```

---

## Workflow Examples

### 1. Kind on Vagrant (VirtualBox)

```bash
# Provision VM
./scripts/setup.sh env init
./scripts/setup.sh vagrant up k8s-master-machine

# Generate inventory and verify
./scripts/setup.sh inventory generate
./scripts/setup.sh inventory ping

# Create Kind cluster
./scripts/setup.sh kind setup

# Add cert-manager + test ingress
./scripts/setup.sh kind utils certmanager ingress_test

# Teardown
./scripts/setup.sh kind destroy
./scripts/setup.sh vagrant destroy k8s-master-machine
```

### 2. K3s Standalone on Vagrant

```bash
# Provision master + worker
./scripts/setup.sh vagrant up k8s-master-machine k8s-worker-machine-1

# Generate inventory
./scripts/setup.sh inventory generate
./scripts/setup.sh inventory ping

# (Optional) Review / edit cluster config
./scripts/setup.sh config edit

# Setup K3s
./scripts/setup.sh k3s setup

# Get kubeconfig
ssh vagrant@192.168.56.99 'sudo cat /etc/rancher/k3s/k3s.yaml' > ~/.kube/config
# Replace 127.0.0.1 with 192.168.56.99 in the kubeconfig file

# Install utilities
./scripts/setup.sh k3s utils certmanager gitops ingress_test

# Teardown
./scripts/setup.sh k3s destroy
./scripts/setup.sh vagrant destroy
```

### 3. K3s on Remote VPS

```bash
# Interactive inventory wizard
./scripts/setup.sh inventory set-remote
# Enter: VPS IP, SSH port, SSH user, key path, number of workers

# Verify connectivity
./scripts/setup.sh inventory ping

# Edit cluster config (set tlsSANs, loadBalancer IP pool for your network)
./scripts/setup.sh config edit

# Setup K3s
./scripts/setup.sh k3s setup

# Get kubeconfig
ssh root@<vps-ip> 'sudo cat /etc/rancher/k3s/k3s.yaml' > ~/.kube/config
# Replace 127.0.0.1 with your VPS IP

# Install GitOps + cert-manager
./scripts/setup.sh k3s utils certmanager gitops

# Teardown
./scripts/setup.sh k3s destroy
```

### 4. K3s High-Availability (HA)

```bash
# 1. Edit inventory with HA groups
#    ansible/inventories/hosts needs:
#    [ha_master_init]    — exactly 1 bootstrap node
#    [ha_master_join]    — additional control-plane nodes
#    [ha_worker]         — agent nodes

# 2. Enable HA in config
./scripts/setup.sh config edit
# Set: k3sCluster.highAvailability.enable: true
# Set: k3sCluster.highAvailability.replicas: 3

# 3. Run HA setup
./scripts/setup.sh k3s ha-setup

# 4. Teardown
./scripts/setup.sh k3s destroy
```

### 5. Kind on Localhost (No Vagrant)

```bash
# Manually set inventory for localhost
cat > ansible/inventories/hosts <<'EOF'
[standalone-masters]
localhost ansible_host=127.0.0.1 ansible_connection=local

[standalone-all:children]
standalone-masters

[all:vars]
ansible_user=$USER
EOF

# Setup Kind
./scripts/setup.sh kind setup --host localhost

# Verify
kubectl cluster-info --context kind-kubewekend

# Cleanup
./scripts/setup.sh kind destroy
```

---

## Available Utility Tags

Used with `kind utils <tags...>` or `k3s utils <tags...>`:

| Tag | Description | Playbook |
|-----|-------------|----------|
| `ingress_test` | Deploy test nginx with ingress | `k8s-utilities-playbook.yaml` |
| `apigateway_test` | Deploy API Gateway test with weighted routing | `k8s-utilities-playbook.yaml` |
| `certmanager` | Install cert-manager (v1.19.2) | `k8s-utilities-playbook.yaml` |
| `dashboard` | Install K8s dashboard (kubernetes-dashboard / headlamp / rancher) | `k8s-utilities-playbook.yaml` |
| `secret_management` | Install Vault (v0.32.0) or OpenBao | `k8s-utilities-playbook.yaml` |
| `k8s_extensions` | Install reflector, reloader, external-secrets | `k8s-utilities-playbook.yaml` |
| `gitops` | Install ArgoCD (v9.1.3) or Flux (v2.7.5) | `k8s-utilities-playbook.yaml` |

Multiple tags can be combined:

```bash
./scripts/setup.sh kind utils certmanager dashboard gitops
./scripts/setup.sh k3s utils ingress_test apigateway_test k8s_extensions
```

---

## Project Structure

```
scripts/
├── setup.sh              # Kubewekend CLI (this script)
├── README.md             # This documentation
└── legacy/               # Legacy v1 scripts (Kind only)
    ├── operate-kind-cluster.sh   # Auto-generate inventory from Vagrant
    ├── hook-up-ip.sh             # VirtualBox NAT network setup
    ├── return-to-nat.sh          # Revert VMs to default NAT
    └── README.md                 # Legacy documentation

ansible/
├── k3s-playbook.yaml             # K3s standalone setup
├── k3s-ha-playbook.yaml          # K3s HA setup (embedded etcd / external postgres)
├── k3s-remove-playbook.yaml      # K3s teardown
├── kind-playbook.yaml            # Kind setup (CNI, LB, ingress, gateway)
├── k8s-utilities-playbook.yaml   # Post-cluster utilities (cert-manager, vault, gitops, etc.)
├── inventories/
│   ├── hosts                     # Ansible inventory (auto-generated or manual)
│   └── host_vars/
│       ├── master.yaml           # Master node config (Kind + K3s + utilities)
│       └── worker.yaml           # Worker node config (K3s only)
└── templates/
    ├── k3s-config.yaml.j2
    ├── kind-config.yaml.j2
    ├── ingress-test-deployment.yaml.j2
    └── apigateway-test-deployment.yaml.j2
```

---

## Configuration Files

| File | Purpose |
|------|---------|
| `.env` | SSH credentials (from `template.env`) |
| `ansible/inventories/hosts` | Ansible inventory (hosts, groups, SSH config) |
| `ansible/inventories/host_vars/master.yaml` | **Primary config** — Kind networking, K3s version/CNI/LB/ingress, utilities toggles |
| `ansible/inventories/host_vars/worker.yaml` | Worker-specific config (K3s version, labels, taints) |
| `ansible.cfg` | Ansible SSH options (host key checking disabled) |
| `Vagrantfile` | VM definitions (master + 3 workers, VirtualBox) |

Key settings in `master.yaml`:

```yaml
# Kind
kindCluster.image: "kindest/node:v1.28.9"
kindCluster.ingress.class: "traefik"     # nginx | traefik | cilium | kong
kindCluster.loadbalancer.type: "cloud-provider-kind"  # metallb | cloud-provider-kind

# K3s
k3sCluster.version: "v1.34.5+k3s1"
k3sCluster.cni.type: "flannel"           # flannel | calico | cilium
k3sCluster.loadBalancer.type: "servicelb" # servicelb | metallb
k3sCluster.ingress.class: "traefik"
k3sCluster.highAvailability.enable: false # true for HA

# Utilities
utilities.certmanager.enable: true
utilities.gitops.type: "flux"             # argocd | flux
utilities.dashboard.type: "headlamp"      # kubernetes-dashboard | headlamp | rancher
```

---

## Contributing

When adding new features to the CLI:

1. **Add a new command function** following the pattern: `cmd_<name>()` for dispatch + `cmd_<name>_help()` for documentation
2. **Register** in the `main()` case statement
3. **Use** `parse_ansible_opts` and `run_ansible_playbook` for any ansible-based operations
4. **Add confirmation** via `confirm()` for destructive operations
5. **Update this README** with the new command, subcommands, and examples
6. **Test** with `--dry-run` before running against real infrastructure

```bash
# Pattern for adding: "monitoring" command
cmd_monitoring_help() { ... }
cmd_monitoring() {
    local sub="${1:-help}"; shift || true
    case "$sub" in
        setup)   monitoring_setup "$@" ;;
        *)       cmd_monitoring_help ;;
    esac
}
# Add to main(): monitoring) cmd_monitoring "$@" ;;
```
