#!/usr/bin/env bash
# =============================================================================
# Kubewekend CLI - Setup & Operate Kind / K3s Kubernetes Clusters
# =============================================================================
# A unified CLI for provisioning VMs (Vagrant/VPS), configuring ansible
# inventories, deploying Kind/K3s clusters, and managing K8s utilities.
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
TEMPLATES_DIR="$ANSIBLE_DIR/templates"
ENV_FILE="$PROJECT_ROOT/.env"
TEMPLATE_ENV="$PROJECT_ROOT/template.env"

# Colours (disabled when not a terminal)
if [[ -t 1 ]]; then
    RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
    BLUE=$'\033[0;34m'; CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; NC=$'\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; NC=''
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()    { printf "${GREEN}[INFO]${NC}  %s\n" "$*"; }
warn()    { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
error()   { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }
header()  { printf "\n${BOLD}${CYAN}>>> %s${NC}\n\n" "$*"; }
confirm() {
    local msg="${1:-Continue?}"
    printf "${YELLOW}%s [y/N]:${NC} " "$msg"
    read -r ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

require_cmd() {
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then
            error "'$cmd' is required but not installed."
            return 1
        fi
    done
}

load_env() {
    if [[ -f "$ENV_FILE" ]]; then
        set -a
        # shellcheck source=/dev/null
        source "$ENV_FILE"
        set +a
    fi
}

# ---------------------------------------------------------------------------
# COMMAND: env
# ---------------------------------------------------------------------------
cmd_env_help() {
    cat <<'EOF'
kubewekend env - Environment management

SUBCOMMANDS
  check         Check required tools are installed
  init          Create .env from template.env
  show          Print current environment variables

EXAMPLES
  ./scripts/setup.sh env check
  ./scripts/setup.sh env init
EOF
}

cmd_env() {
    local sub="${1:-help}"; shift || true
    case "$sub" in
        check) env_check ;;
        init)  env_init ;;
        show)  env_show ;;
        *)     cmd_env_help ;;
    esac
}

env_check() {
    header "Checking required tools"
    local tools=(vagrant virtualbox ansible ansible-playbook ssh kubectl helm)
    local optional=(kind k3s docker jq yq)
    local missing=0

    for t in "${tools[@]}"; do
        if command -v "$t" &>/dev/null; then
            info "$t  $(command -v "$t")"
        else
            warn "$t  NOT FOUND (required)"
            missing=$((missing + 1))
        fi
    done

    printf "\n"
    info "Optional tools:"
    for t in "${optional[@]}"; do
        if command -v "$t" &>/dev/null; then
            info "$t  $(command -v "$t")"
        else
            warn "$t  not found (optional)"
        fi
    done

    if [[ $missing -gt 0 ]]; then
        error "$missing required tool(s) missing"
        return 1
    fi
    info "All required tools are available!"
}

env_init() {
    if [[ -f "$ENV_FILE" ]]; then
        warn ".env already exists"
        confirm "Overwrite?" || return 0
    fi
    cp "$TEMPLATE_ENV" "$ENV_FILE"
    info "Created .env from template.env - please edit it with your values"
}

env_show() {
    load_env
    header "Environment"
    echo "SSH_USER          = ${SSH_USER:-<not set>}"
    echo "SSH_KEY_LOCATION  = ${SSH_KEY_LOCATION:-<not set>}"
    echo "PROJECT_ROOT      = $PROJECT_ROOT"
    echo "ANSIBLE_DIR       = $ANSIBLE_DIR"
    echo "INVENTORY         = $HOSTS_FILE"
}

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
  Environment variables SSH_USER, SSH_PRIV_KEY_PATH are read from .env

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
    export SSH_PRIV_KEY_PATH="${SSH_PRIV_KEY_PATH:-${SSH_KEY_LOCATION:-~/.ssh/id_rsa}}"

    vagrant up "${machines[@]}" --provider=virtualbox
    info "VMs provisioned successfully"
}

vagrant_halt() {
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
    require_cmd vagrant || return 1
    cd "$PROJECT_ROOT"
    vagrant status
}

vagrant_ssh() {
    require_cmd vagrant || return 1
    cd "$PROJECT_ROOT"
    local machine="${1:?Machine name required. Usage: kubewekend vagrant ssh <machine>}"
    vagrant ssh "$machine"
}

vagrant_reload() {
    require_cmd vagrant || return 1
    cd "$PROJECT_ROOT"
    if [[ $# -eq 0 ]]; then
        vagrant reload
    else
        vagrant reload "$@"
    fi
}

# ---------------------------------------------------------------------------
# COMMAND: inventory
# ---------------------------------------------------------------------------
cmd_inventory_help() {
    cat <<'EOF'
kubewekend inventory - Ansible inventory management

SUBCOMMANDS
  generate              Auto-generate inventory from running Vagrant VMs
  show                  Display current inventory
  ping [group]          Test connectivity (default group: all)
  set-remote            Configure inventory for remote VPS (interactive)

EXAMPLES
  # Auto-generate from vagrant
  ./scripts/setup.sh inventory generate

  # Test all hosts
  ./scripts/setup.sh inventory ping

  # Test only masters
  ./scripts/setup.sh inventory ping standalone-masters

  # Configure for remote VPS
  ./scripts/setup.sh inventory set-remote
EOF
}

cmd_inventory() {
    local sub="${1:-help}"; shift || true
    case "$sub" in
        generate)   inventory_generate ;;
        show)       inventory_show ;;
        ping)       inventory_ping "${1:-all}" ;;
        set-remote) inventory_set_remote ;;
        *)          cmd_inventory_help ;;
    esac
}

inventory_generate() {
    require_cmd vagrant || return 1
    cd "$PROJECT_ROOT"

    header "Generating ansible inventory from Vagrant"

    local running
    running=$(vagrant status | grep -E "running" | awk '{print $1}')

    if [[ -z "$running" ]]; then
        error "No running VMs found. Run: kubewekend vagrant up <machines>"
        return 1
    fi

    load_env
    local masters="" workers=""
    while IFS= read -r vm; do
        local ssh_config host port user key_path node_ip
        ssh_config=$(vagrant ssh-config "$vm")
        host=$(echo "$ssh_config" | grep "HostName" | awk '{print $2}')
        port=$(echo "$ssh_config" | grep "Port" | head -1 | awk '{print $2}')
        user=$(echo "$ssh_config" | grep "User" | head -1 | awk '{print $2}')
        key_path=$(echo "$ssh_config" | grep "IdentityFile" | awk '{print $2}')

        # Add SSH key to agent
        ssh-add "$key_path" 2>/dev/null || true

        # Determine node_ip from Vagrantfile convention
        case "$vm" in
            k8s-master-machine)     node_ip="192.168.56.99" ;;
            k8s-worker-machine-1)   node_ip="192.168.56.101" ;;
            k8s-worker-machine-2)   node_ip="192.168.56.102" ;;
            k8s-worker-machine-3)   node_ip="192.168.56.103" ;;
            *)                      node_ip="$host" ;;
        esac

        local entry="$vm ansible_host=$host ansible_port=$port node_ip=$node_ip"
        if [[ "$vm" == *master* ]]; then
            masters+="$entry"$'\n'
        else
            workers+="$entry"$'\n'
        fi

        info "Discovered: $vm ($host:$port)"
    done <<< "$running"

    cat > "$HOSTS_FILE" <<INVENTORY
# =============================================================================
# Auto-generated by kubewekend CLI on $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# =============================================================================

# SECTION 1: STANDALONE MODE
[standalone-masters]
${masters}
[standalone-workers]
${workers}
[standalone-all:children]
standalone-masters
standalone-workers

# SECTION 2: GLOBAL CONFIGURATION
[all:vars]
ansible_user=${SSH_USER:-vagrant}
ansible_connection=ssh
ansible_ssh_private_key_file="${SSH_KEY_LOCATION:-~/.ssh/id_rsa}"
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
INVENTORY

    info "Inventory written to $HOSTS_FILE"
}

inventory_show() {
    header "Current Inventory"
    if [[ -f "$HOSTS_FILE" ]]; then
        cat "$HOSTS_FILE"
    else
        warn "No inventory file found at $HOSTS_FILE"
    fi
}

inventory_ping() {
    require_cmd ansible || return 1
    local group="${1:-all}"
    header "Pinging group: $group"
    ansible -i "$HOSTS_FILE" "$group" -m ping
}

inventory_set_remote() {
    header "Configure Remote VPS Inventory"
    echo "This will create an inventory for remote VPS/server access."
    echo ""

    local master_ip master_port master_user ssh_key num_workers
    read -rp "Master IP address: " master_ip
    read -rp "Master SSH port [22]: " master_port
    master_port="${master_port:-22}"
    read -rp "SSH user [root]: " master_user
    master_user="${master_user:-root}"
    read -rp "SSH private key path [~/.ssh/id_rsa]: " ssh_key
    ssh_key="${ssh_key:-~/.ssh/id_rsa}"
    read -rp "Number of workers [0]: " num_workers
    num_workers="${num_workers:-0}"

    local worker_entries=""
    for ((i=1; i<=num_workers; i++)); do
        local wip wport
        read -rp "  Worker $i IP address: " wip
        read -rp "  Worker $i SSH port [22]: " wport
        wport="${wport:-22}"
        worker_entries+="k8s-worker-machine-$i ansible_host=$wip ansible_port=$wport node_ip=$wip"$'\n'
    done

    cat > "$HOSTS_FILE" <<INVENTORY
# =============================================================================
# Remote VPS Inventory - Generated by kubewekend CLI on $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# =============================================================================

# SECTION 1: STANDALONE MODE
[standalone-masters]
k8s-master-machine ansible_host=${master_ip} ansible_port=${master_port} node_ip=${master_ip}

[standalone-workers]
${worker_entries}
[standalone-all:children]
standalone-masters
standalone-workers

# SECTION 2: GLOBAL CONFIGURATION
[all:vars]
ansible_user=${master_user}
ansible_connection=ssh
ansible_ssh_private_key_file="${ssh_key}"
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
INVENTORY

    info "Remote inventory written to $HOSTS_FILE"
    echo ""
    info "Test connectivity: ./scripts/setup.sh inventory ping"
}

# ---------------------------------------------------------------------------
# COMMAND: kind
# ---------------------------------------------------------------------------
cmd_kind_help() {
    cat <<'EOF'
kubewekend kind - KIND (Kubernetes in Docker) cluster management

SUBCOMMANDS
  setup                 Install tools + create Kind cluster + networking
  destroy               Remove Kind cluster and related components
  utils [tags...]       Run K8s utilities (see available tags below)

OPTIONS
  --host, -H <name>    Ansible host target (default: k8s-master-machine)
  --dry-run             Show ansible command without executing
  --skip-tags <tags>    Comma-separated tags to skip
  --extra-vars <vars>   Additional ansible extra-vars (key=value)

AVAILABLE UTILITY TAGS
  ingress_test          Deploy test ingress workload
  apigateway_test       Deploy test API gateway workload
  certmanager           Install cert-manager
  dashboard             Install K8s dashboard (kubernetes-dashboard / headlamp / rancher)
  storage               Install Longhorn distributed block storage (iSCSI / NFS)
  secret_management     Install Vault or OpenBao (auto-unseal, Vault Operator)
  k8s_extensions        Install Reflector, Reloader, External Secrets Operator
  gitops                Install ArgoCD (Image Updater + Extensions) or Flux + Kargo
  security              Install Kyverno / OPA Gatekeeper + Dex identity provider
  idp                   Install Backstage Internal Developer Portal
  monitoring            Install LGTM stack: kube-prometheus-stack + Alloy + Loki + Tempo + Pyroscope
  service_mesh          Install Istio service mesh

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

  # Install security policy engine + IDP portal
  ./scripts/setup.sh kind utils security idp

  # Install storage + secret management
  ./scripts/setup.sh kind utils storage secret_management

  # Dry run to see what ansible would execute
  ./scripts/setup.sh kind setup --dry-run

  # Setup with custom extra-vars
  ./scripts/setup.sh kind setup --extra-vars "kindCluster_image=kindest/node:v1.30.13"
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

# Parse common ansible flags used by kind/k3s commands
parse_ansible_opts() {
    HOST_NAME="k8s-master-machine"
    DRY_RUN=false
    SKIP_TAGS=""
    EXTRA_VARS=""
    ANSIBLE_TAGS=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --host|-H)       HOST_NAME="$2"; shift 2 ;;
            --dry-run)       DRY_RUN=true;  shift ;;
            --skip-tags)     SKIP_TAGS="$2"; shift 2 ;;
            --extra-vars)    EXTRA_VARS="$2"; shift 2 ;;
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

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY RUN] ${cmd[*]}"
        return 0
    fi

    info "Running: ${cmd[*]}"
    "${cmd[@]}"
}

kind_setup() {
    parse_ansible_opts "$@"
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

kind_utils() {
    parse_ansible_opts "$@"
    if [[ ${#ANSIBLE_TAGS[@]} -eq 0 ]]; then
        error "Specify at least one utility tag."
        echo ""
        echo "Available tags:"
        echo "  Test:        ingress_test, apigateway_test"
        echo "  Cluster:     certmanager, dashboard, storage, secret_management, k8s_extensions"
        echo "  GitOps:      gitops"
        echo "  Security:    security, idp"
        echo "  Observ.:     monitoring"
        echo "  Networking:  service_mesh"
        echo ""
        echo "Example: ./scripts/setup.sh kind utils certmanager monitoring"
        echo "         ./scripts/setup.sh kind utils security idp gitops"
        return 1
    fi

    local tags_str
    tags_str=$(IFS=,; echo "${ANSIBLE_TAGS[*]}")
    header "Installing K8s utilities: $tags_str on $HOST_NAME"
    run_ansible_playbook "k8s-utilities-playbook.yaml" "$tags_str"
    info "Utilities installed: $tags_str"
}

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
  utils [tags...]       Run K8s utilities (same tags as kind utils)

OPTIONS
  --host, -H <name>    Ansible host target (default: k8s-master-machine)
  --dry-run             Show ansible command without executing
  --skip-tags <tags>    Comma-separated tags to skip
  --extra-vars <vars>   Additional ansible extra-vars (key=value)

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

  # 1. Edit ansible/inventories/hosts with HA groups (ha_master_init, ha_master_join, ha_worker)
  # 2. Edit ansible/inventories/host_vars/master.yaml and enable highAvailability
  ./scripts/setup.sh k3s ha-setup

  # --- Re-run without reinstalling tools ---
  ./scripts/setup.sh k3s setup --host k8s-master-machine --skip-tags install_common

  # --- Utilities ---
  ./scripts/setup.sh k3s utils certmanager gitops dashboard

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
        echo "  ssh <master> 'sudo cat /etc/rancher/k3s/k3s.yaml' > ~/.kube/config"
    fi
}

k3s_ha_setup() {
    parse_ansible_opts "$@"
    header "Setting up HA K3s cluster"

    info "Ensure you have configured:"
    echo "  - ansible/inventories/hosts (ha_master_init, ha_master_join, ha_worker groups)"
    echo "  - ansible/inventories/host_vars/master.yaml (highAvailability.enable: true)"
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

k3s_utils() {
    parse_ansible_opts "$@"
    if [[ ${#ANSIBLE_TAGS[@]} -eq 0 ]]; then
        error "Specify at least one utility tag."
        echo ""
        echo "Available tags:"
        echo "  Test:        ingress_test, apigateway_test"
        echo "  Cluster:     certmanager, dashboard, storage, secret_management, k8s_extensions"
        echo "  GitOps:      gitops"
        echo "  Security:    security, idp"
        echo "  Observ.:     monitoring"
        echo "  Networking:  service_mesh"
        echo ""
        echo "Example: ./scripts/setup.sh k3s utils certmanager monitoring"
        echo "         ./scripts/setup.sh k3s utils security idp gitops"
        return 1
    fi

    local tags_str
    tags_str=$(IFS=,; echo "${ANSIBLE_TAGS[*]}")
    header "Installing K8s utilities: $tags_str (target: $HOST_NAME)"
    run_ansible_playbook "k8s-utilities-playbook.yaml" "$tags_str"
    info "Utilities installed: $tags_str"
}

# ---------------------------------------------------------------------------
# COMMAND: network (VirtualBox NAT Network management)
# ---------------------------------------------------------------------------
cmd_network_help() {
    cat <<'EOF'
kubewekend network - VirtualBox network management

SUBCOMMANDS
  hookup [name] [cidr]  Create NAT network and attach VMs (default: KubewekendNet 10.0.69.0/24)
  return-nat            Revert VMs back to default NAT network
  status                Show VirtualBox NAT networks

EXAMPLES
  # Attach VMs to NAT network
  ./scripts/setup.sh network hookup

  # Custom NAT network
  ./scripts/setup.sh network hookup MyNet 10.0.100.0/24

  # Revert to default NAT
  ./scripts/setup.sh network return-nat
EOF
}

cmd_network() {
    local sub="${1:-help}"; shift || true
    case "$sub" in
        hookup)     network_hookup "${1:-KubewekendNet}" "${2:-10.0.69.0/24}" ;;
        return-nat) network_return_nat ;;
        status)     network_status ;;
        *)          cmd_network_help ;;
    esac
}

network_hookup() {
    require_cmd VBoxManage vagrant || return 1
    cd "$PROJECT_ROOT"

    local net_name="$1"
    local net_range="$2"

    header "Hooking up VMs to NAT Network: $net_name ($net_range)"

    # Create network if not exists
    if ! VBoxManage list natnetworks | grep -q "$net_name"; then
        VBoxManage natnetwork add --netname "$net_name" --network "$net_range" --enable
        VBoxManage natnetwork modify --netname "$net_name" --dhcp on
        info "Created NAT network: $net_name"
    else
        info "NAT network '$net_name' already exists"
    fi

    local all_machines
    all_machines=$(vagrant status | grep -E "running|poweroff" | awk '{print $1}')

    for vm in $all_machines; do
        local is_running=false
        if vagrant status "$vm" 2>/dev/null | grep -q "running"; then
            is_running=true
            VBoxManage startvm "$vm" --type emergencystop 2>/dev/null || true
        fi

        VBoxManage modifyvm "$vm" --nic1 natnetwork --nat-network1 "$net_name"
        VBoxManage startvm "$vm" --type headless

        # Wait for VM to become ready
        info "Waiting for $vm to start..."
        local retries=30
        while ((retries > 0)); do
            if VBoxManage showvminfo "$vm" 2>/dev/null | grep -q "running (since"; then
                sleep 15
                break
            fi
            sleep 2
            retries=$((retries - 1))
        done

        # Retrieve IP and configure port forwarding
        local machine_ip ssh_config port_ssh
        machine_ip=$(VBoxManage guestproperty get "$vm" "/VirtualBox/GuestInfo/Net/0/V4/IP" 2>/dev/null | cut -d ":" -f2 | xargs)
        ssh_config=$(vagrant ssh-config "$vm" 2>/dev/null || true)
        port_ssh=$(echo "$ssh_config" | grep "Port" | head -1 | awk '{print $2}')

        if [[ -n "$machine_ip" && -n "$port_ssh" ]]; then
            # Remove existing rule if present, then add
            VBoxManage natnetwork modify --netname "$net_name" --port-forward-4 delete "Rule $vm" 2>/dev/null || true
            VBoxManage natnetwork modify --netname "$net_name" --port-forward-4 "Rule $vm:tcp:[127.0.0.1]:$port_ssh:[$machine_ip]:22"
            info "$vm hooked up ($machine_ip -> 127.0.0.1:$port_ssh)"
        else
            warn "Could not configure port forwarding for $vm"
        fi
    done

    info "NAT network hookup complete"
}

network_return_nat() {
    require_cmd VBoxManage vagrant || return 1
    cd "$PROJECT_ROOT"

    header "Reverting VMs to default NAT network"
    confirm "Halt and reconfigure all VMs?" || return 0

    local machines
    machines=$(vagrant status | grep -iE "poweroff|running" | awk '{print $1}')

    for vm in $machines; do
        vagrant halt "$vm" 2>/dev/null || true
        VBoxManage modifyvm "$vm" --nic1 nat
        info "Reverted $vm to NAT"
    done

    info "All VMs reverted to default NAT"
}

network_status() {
    require_cmd VBoxManage || return 1
    header "VirtualBox NAT Networks"
    VBoxManage list natnetworks
}

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

EXAMPLES
  ./scripts/setup.sh quickstart kind-local
  ./scripts/setup.sh quickstart kind-vagrant
  ./scripts/setup.sh quickstart k3s-vagrant
  ./scripts/setup.sh quickstart k3s-remote
EOF
}

cmd_quickstart() {
    local sub="${1:-help}"; shift || true
    case "$sub" in
        kind-local)   qs_kind_local "$@" ;;
        kind-vagrant) qs_kind_vagrant "$@" ;;
        k3s-vagrant)  qs_k3s_vagrant "$@" ;;
        k3s-remote)   qs_k3s_remote "$@" ;;
        *)            cmd_quickstart_help ;;
    esac
}

qs_kind_local() {
    header "Quick Start: Kind on Localhost"
    echo "This workflow sets up a Kind cluster directly on your machine."
    echo "Requirements: docker, ansible"
    echo ""
    confirm "Start Kind local setup?" || return 0

    cat <<'GUIDE'

Step-by-step:
  1. Make sure Docker is running
  2. Configure your inventory to use localhost:

     [standalone-masters]
     localhost ansible_host=127.0.0.1 ansible_connection=local

  3. Run setup:
     ./scripts/setup.sh kind setup --host localhost

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
     ssh vagrant@192.168.56.99 'sudo cat /etc/rancher/k3s/k3s.yaml' > ~/.kube/config
     # Replace 127.0.0.1 with 192.168.56.99 in the kubeconfig

  8. Install utilities:
     ./scripts/setup.sh k3s utils ingress_test certmanager

  9. Teardown:
     ./scripts/setup.sh k3s destroy
     ./scripts/setup.sh vagrant destroy

  --- HA Variant (3 masters + 1 worker) ---

  a. Edit ansible/inventories/hosts with HA groups
  b. Enable highAvailability in master.yaml
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
     # Important: set loadBalancer.ippool.cidr to your VPS network range

  4. Setup K3s:
     ./scripts/setup.sh k3s setup

  5. Get kubeconfig:
     ssh <user>@<vps-ip> 'sudo cat /etc/rancher/k3s/k3s.yaml' > ~/.kube/config
     # Replace 127.0.0.1 with your VPS IP in the kubeconfig

  6. Install utilities:
     ./scripts/setup.sh k3s utils certmanager gitops

  7. Teardown:
     ./scripts/setup.sh k3s destroy

GUIDE
}

# ---------------------------------------------------------------------------
# COMMAND: status
# ---------------------------------------------------------------------------
cmd_status() {
    header "Kubewekend Project Status"

    echo "Project Root: $PROJECT_ROOT"
    echo ""

    # Vagrant VMs
    if command -v vagrant &>/dev/null; then
        echo "${BOLD}Vagrant VMs:${NC}"
        cd "$PROJECT_ROOT"
        vagrant status 2>/dev/null | grep -E "running|poweroff|not created" | sed 's/^/  /'
        echo ""
    fi

    # Inventory
    echo "${BOLD}Ansible Inventory:${NC}"
    if [[ -f "$HOSTS_FILE" ]]; then
        grep -E "^\[|ansible_host" "$HOSTS_FILE" | sed 's/^/  /'
    else
        echo "  No inventory file"
    fi
    echo ""

    # Kubernetes clusters
    if command -v kubectl &>/dev/null; then
        echo "${BOLD}Kubernetes Contexts:${NC}"
        kubectl config get-contexts 2>/dev/null | head -10 | sed 's/^/  /' || echo "  No contexts"
        echo ""
    fi

    # Docker (for Kind)
    if command -v docker &>/dev/null; then
        echo "${BOLD}Docker Containers (kind):${NC}"
        docker ps --filter "label=io.x-k8s.kind.cluster" --format "  {{.Names}} ({{.Status}})" 2>/dev/null || echo "  No kind containers"
        echo ""
    fi
}

# ---------------------------------------------------------------------------
# COMMAND: config — YAML parsing helpers (pure bash, no yq/jq)
# ---------------------------------------------------------------------------

# Extract all indented lines under a 0-indent top-level YAML key (from file)
_yblock() {
    awk "/^${1}:/{f=1;next} f&&/^[^ ]/{exit} f{print}" "$2"
}

# Extract a sub-block at a fixed indent level from stdin
# $1 = key name, $2 = number of leading spaces the key sits at (default 2)
_ysub() {
    local key="$1" spc
    printf -v spc '%*s' "${2:-2}" ''
    awk "/^${spc}${key}:/{f=1;next} f&&/^${spc}[^ ]/{exit} f{print}"
}

# Get the first scalar value for a key from stdin
_yval() {
    grep -m1 "^\s*${1}:" \
      | sed 's/[^:]*:[[:space:]]*//' \
      | tr -d '"' \
      | sed 's/[[:space:]]*#.*//' \
      | xargs
}

# Collect YAML list items ("  - value") from stdin → comma-joined
_ylist() {
    local result
    result=$(grep "^\s*-[[:space:]]" \
      | sed 's/^\s*-[[:space:]]*//' \
      | tr -d '"' \
      | sed 's/[[:space:]]*#.*//' \
      | awk 'NR>1{printf ", "}{printf $0} END{if(NR>0)printf ""}')
    printf '%s' "${result:-none}"
}

# Coloured ON/OFF badge with optional trailing label
_badge() {
    local val="$1" label="${2:-}"
    if [[ "$val" == "true" ]]; then
        printf "${GREEN}ON${NC}%s"  "${label:+  $label}"
    else
        printf "${RED}OFF${NC}%s" "${label:+  $label}"
    fi
}

# Single table row: cyan label (24-char) + value
_row() { printf "  ${CYAN}%-24s${NC}  %s\n" "$1" "$2"; }

# Section header with divider line
_sec() {
    printf "\n  ${BOLD}${YELLOW}▸ %s${NC}\n" "$1"
    printf '  %s\n' "$(printf '%52s' '' | tr ' ' '─')"
}

# ---------------------------------------------------------------------------
# config show: master.yaml summary table
# ---------------------------------------------------------------------------
config_show_master() {
    local file="$HOST_VARS_DIR/master.yaml"
    [[ -f "$file" ]] || { error "File not found: $file"; return 1; }

    header "Master Node Configuration"
    printf "  File: ${BOLD}%s${NC}\n" "$file"

    local kind k3s util
    kind=$(_yblock "kindCluster" "$file")
    k3s=$( _yblock "k3sCluster"  "$file")
    util=$(_yblock "utilities"   "$file")

    # ---- KIND CLUSTER -------------------------------------------------------
    _sec "KIND CLUSTER"

    local k_net k_lb k_ing k_gw k_fwd
    k_net=$( echo "$kind" | _ysub "networking"       2)
    k_lb=$(  echo "$kind" | _ysub "loadbalancer"     2)
    k_ing=$( echo "$kind" | _ysub "ingress"          2)
    k_gw=$(  echo "$kind" | _ysub "apigateway"       2)
    k_fwd=$( echo "$kind" | _ysub "networkForwarding" 2)

    local k_image k_cni k_proxy k_pod k_svc k_dis_cni
    k_image=$(   echo "$kind"  | _yval "image")
    k_cni=$(     echo "$k_net" | _yval "cni")
    k_proxy=$(   echo "$k_net" | _yval "kubeProxyMode")
    k_pod=$(     echo "$k_net" | _yval "podSubnet")
    k_svc=$(     echo "$k_net" | _yval "serviceSubnet")
    k_dis_cni=$( echo "$k_net" | _yval "disableDefaultCNI")

    local k_lb_en k_lb_type k_lb_cidr k_ing_en k_ing_cls k_gw_en k_gw_cls k_fwd_en
    k_lb_en=$(  echo "$k_lb"  | _yval "enable")
    k_lb_type=$(echo "$k_lb"  | _yval "type")
    k_lb_cidr=$(echo "$k_lb"  | _yval "cidr")
    k_ing_en=$( echo "$k_ing" | _yval "enable")
    k_ing_cls=$(echo "$k_ing" | _yval "class")
    k_gw_en=$(  echo "$k_gw"  | _yval "enable")
    k_gw_cls=$( echo "$k_gw"  | _yval "class")
    k_fwd_en=$( echo "$k_fwd" | _yval "enable")

    _row "Node Image"          "$k_image"
    _row "Pod Subnet"          "$k_pod"
    _row "Service Subnet"      "$k_svc"
    _row "CNI"                 "$k_cni  (disable default: $k_dis_cni)"
    _row "kube-proxy Mode"     "$k_proxy"
    _row "Load Balancer"       "$(_badge "$k_lb_en" "$k_lb_type")"
    [[ "$k_lb_type" == "metallb" ]] && \
        _row "  LB IP Pool"    "$k_lb_cidr"
    _row "Ingress"             "$(_badge "$k_ing_en" "$k_ing_cls")"
    _row "API Gateway"         "$(_badge "$k_gw_en" "$k_gw_cls")"
    _row "Network Forwarding"  "$(_badge "$k_fwd_en")"

    # ---- K3S CLUSTER --------------------------------------------------------
    _sec "K3S CLUSTER"

    local k3_ha k3_ds k3_db k3_cni k3_lb k3_lb_pool k3_ing k3_ing_dash
    k3_ha=$(      echo "$k3s"    | _ysub "highAvailability" 2)
    k3_ds=$(      echo "$k3_ha"  | _ysub "dataStorage"      4)
    k3_db=$(      echo "$k3_ds"  | _ysub "externalDatabase" 6)
    k3_cni=$(     echo "$k3s"    | _ysub "cni"              2)
    k3_lb=$(      echo "$k3s"    | _ysub "loadBalancer"     2)
    k3_lb_pool=$( echo "$k3_lb"  | _ysub "ippool"           4)
    k3_ing=$(     echo "$k3s"    | _ysub "ingress"          2)
    k3_ing_dash=$(echo "$k3_ing" | _ysub "dashboard"        4)

    local version ha_en ha_rep ha_db_type cni_type lb_en lb_type lb_cidr
    local ing_en ing_cls dash_en dash_host labels tlssans
    version=$(    echo "$k3s"         | _yval "version")
    ha_en=$(      echo "$k3_ha"       | _yval "enable")
    ha_rep=$(     echo "$k3_ha"       | _yval "replicas")
    ha_db_type=$( echo "$k3_db"       | _yval "type")
    cni_type=$(   echo "$k3_cni"      | _yval "type")
    lb_en=$(      echo "$k3_lb"       | _yval "enable")
    lb_type=$(    echo "$k3_lb"       | _yval "type")
    lb_cidr=$(    echo "$k3_lb_pool"  | _yval "cidr")
    ing_en=$(     echo "$k3_ing"      | _yval "enable")
    ing_cls=$(    echo "$k3_ing"      | _yval "class")
    dash_en=$(    echo "$k3_ing_dash" | _yval "enable")
    dash_host=$(  echo "$k3_ing_dash" | _yval "host")
    labels=$(     echo "$k3s"         | _ysub "nodeLabels" 2 | _ylist)
    tlssans=$(    echo "$k3s"         | _ysub "tlsSANs"    2 | _ylist)

    _row "Version"          "$version"
    if [[ "$ha_en" == "true" ]]; then
        _row "High Availability" "$(_badge "$ha_en" "replicas: $ha_rep  datastore: $ha_db_type")"
    else
        _row "High Availability" "$(_badge "$ha_en")"
    fi
    _row "CNI"              "$cni_type"
    _row "Load Balancer"    "$(_badge "$lb_en" "$lb_type")"
    _row "  LB IP Pool"     "$lb_cidr"
    _row "Ingress"          "$(_badge "$ing_en" "$ing_cls")"
    _row "  Dashboard"      "$(_badge "$dash_en" "$dash_host")"
    _row "Node Labels"      "$labels"
    _row "TLS SANs"         "$tlssans"

    # ---- UTILITIES ----------------------------------------------------------
    _sec "UTILITIES"

    local u_ing u_gw u_cm u_dash u_stor u_sec u_git u_ext u_security u_idp u_mon u_svcmesh
    u_ing=$(     echo "$util" | _ysub "ingressTestDeployment"    2)
    u_gw=$(      echo "$util" | _ysub "apiGatewayTestDeployment" 2)
    u_cm=$(      echo "$util" | _ysub "certmanager"              2)
    u_dash=$(    echo "$util" | _ysub "dashboard"                2)
    u_stor=$(    echo "$util" | _ysub "storage"                  2)
    u_sec=$(     echo "$util" | _ysub "secretManagement"         2)
    u_git=$(     echo "$util" | _ysub "gitops"                   2)
    u_ext=$(     echo "$util" | _ysub "extensions"               2)
    u_security=$(echo "$util" | _ysub "security"                 2)
    u_idp=$(     echo "$util" | _ysub "idp"                      2)
    u_mon=$(     echo "$util" | _ysub "monitoring"               2)
    u_svcmesh=$( echo "$util" | _ysub "serviceMesh"              2)

    local ing_en2 ing_host gw_en gw_host cm_en
    local dash_en2 dash_type stor_en stor_type sec_en sec_type git_en git_type ext_en
    local security_en policy_type idp_en idp_type mon_en mon_type svcmesh_en svcmesh_type
    ing_en2=$(    echo "$u_ing"      | _yval "enable")
    ing_host=$(   echo "$u_ing"      | _yval "host")
    gw_en=$(      echo "$u_gw"       | _yval "enable")
    gw_host=$(    echo "$u_gw"       | _yval "host")
    cm_en=$(      echo "$u_cm"       | _yval "enable")
    dash_en2=$(   echo "$u_dash"     | _yval "enable")
    dash_type=$(  echo "$u_dash"     | _yval "type")
    stor_en=$(    echo "$u_stor"     | _yval "enable")
    stor_type=$(  echo "$u_stor"     | _yval "type")
    sec_en=$(     echo "$u_sec"      | _yval "enable")
    sec_type=$(   echo "$u_sec"      | _yval "type")
    git_en=$(     echo "$u_git"      | _yval "enable")
    git_type=$(   echo "$u_git"      | _yval "type")
    ext_en=$(     echo "$u_ext"      | _yval "enable")
    security_en=$(echo "$u_security" | _yval "enable")
    policy_type=$(echo "$u_security" | _ysub "policyEngine" 4 | _yval "type")
    idp_en=$(     echo "$u_idp"      | _yval "enable")
    idp_type=$(   echo "$u_idp"      | _ysub "portal" 4 | _yval "type")
    mon_en=$(     echo "$u_mon"      | _yval "enable")
    mon_type=$(   echo "$u_mon"      | _yval "type")
    svcmesh_en=$( echo "$u_svcmesh"  | _yval "enable")
    svcmesh_type=$(echo "$u_svcmesh" | _yval "type")

    _sec "UTILITIES — TEST DEPLOYMENTS"
    _row "Ingress Test"       "$(_badge "$ing_en2"  "$ing_host")"
    _row "API Gateway Test"   "$(_badge "$gw_en"    "$gw_host")"

    _sec "UTILITIES — CLUSTER SERVICES"
    _row "Cert-Manager"       "$(_badge "$cm_en")"
    _row "Dashboard"          "$(_badge "$dash_en2" "$dash_type")"
    _row "Storage"            "$(_badge "$stor_en"  "$stor_type")"
    _row "Secret Management"  "$(_badge "$sec_en"   "$sec_type")"
    _row "Extensions"         "$(_badge "$ext_en")"

    _sec "UTILITIES — GITOPS & SECURITY"
    _row "GitOps"             "$(_badge "$git_en"   "$git_type")"
    _row "Security"           "$(_badge "$security_en" "policy: $policy_type")"
    _row "IDP Portal"         "$(_badge "$idp_en"   "$idp_type")"

    _sec "UTILITIES — OBSERVABILITY & NETWORKING"
    _row "Monitoring (LGTM)"  "$(_badge "$mon_en"     "$mon_type")"
    _row "Service Mesh"       "$(_badge "$svcmesh_en" "$svcmesh_type")"

    echo ""
    printf "  ${YELLOW}Tip:${NC} use --raw to see the full file, or 'config edit' to modify.\n\n"
}

# ---------------------------------------------------------------------------
# config worker-show: worker.yaml summary table
# ---------------------------------------------------------------------------
config_show_worker() {
    local file="$HOST_VARS_DIR/worker.yaml"
    [[ -f "$file" ]] || { error "File not found: $file"; return 1; }

    header "Worker Node Configuration"
    printf "  File: ${BOLD}%s${NC}\n" "$file"

    local k3s
    k3s=$(_yblock "k3sCluster" "$file")

    _sec "K3S AGENT"

    local version labels taints
    version=$(echo "$k3s" | _yval "version")
    labels=$( echo "$k3s" | _ysub "nodeLabels" 2 | _ylist)
    taints=$( echo "$k3s" | _ysub "nodeTaints" 2 | _ylist)

    _row "Version"     "$version"
    _row "Node Labels" "$labels"
    _row "Node Taints" "$taints"

    echo ""
    printf "  ${YELLOW}Tip:${NC} use --raw to see the full file, or 'config worker-edit' to modify.\n\n"
}

# ---------------------------------------------------------------------------
# COMMAND: config
# ---------------------------------------------------------------------------
cmd_config_help() {
    cat <<'EOF'
kubewekend config - View and edit cluster configuration

SUBCOMMANDS
  show [--raw]          Summary table of master.yaml (--raw: full file)
  edit                  Open master.yaml in $EDITOR
  worker-show [--raw]   Summary table of worker.yaml (--raw: full file)
  worker-edit           Open worker.yaml in $EDITOR

EXAMPLES
  ./scripts/setup.sh config show
  ./scripts/setup.sh config show --raw
  ./scripts/setup.sh config edit
  ./scripts/setup.sh config worker-show
EOF
}

cmd_config() {
    local sub="${1:-help}"; shift || true
    case "$sub" in
        show)
            if [[ "${1:-}" == "--raw" ]]; then
                cat "$HOST_VARS_DIR/master.yaml"
            else
                config_show_master
            fi ;;
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
  ${CYAN}network${NC}        VirtualBox NAT network management
  ${CYAN}quickstart${NC}     Guided quick-start workflows with examples
  ${CYAN}config${NC}         View/edit cluster configuration (master.yaml, worker.yaml)
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
  # (edit hosts + master.yaml first)
  ./scripts/setup.sh k3s ha-setup

${BOLD}SUBCOMMAND HELP${NC}
  ./scripts/setup.sh <command> help

EOF
}

# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------
main() {
    local cmd="${1:-help}"; shift || true
    case "$cmd" in
        env)        cmd_env "$@" ;;
        vagrant)    cmd_vagrant "$@" ;;
        inventory)  cmd_inventory "$@" ;;
        kind)       cmd_kind "$@" ;;
        k3s)        cmd_k3s "$@" ;;
        network)    cmd_network "$@" ;;
        quickstart) cmd_quickstart "$@" ;;
        config)     cmd_config "$@" ;;
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

main "$@"
