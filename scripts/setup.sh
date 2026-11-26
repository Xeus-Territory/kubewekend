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
    echo "SSH_KEY           = ${SSH_KEY:-<not set>}"
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

    load_env
    header "Generating ansible inventory from Vagrant"

    local running
    running=$(vagrant status | grep -E "running" | awk '{print $1}')

    if [[ -z "$running" ]]; then
        error "No running VMs found. Run: kubewekend vagrant up <machines>"
        return 1
    fi

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
ansible_ssh_private_key_file="~/.ssh/${SSH_KEY:-vmbox}"
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
# K8s utilities: one registry shared by `kind|k3s|rke2 utils`, their help and `utils --list`
# ---------------------------------------------------------------------------
# One entry per tag of ansible/k8s-utilities-playbook.yaml:
#   tag | master.yaml key (under `utilities:`) | description | supported options | in development | current-value paths
# - supported options: what the playbook implements today
# - in development:    options documented in master.yaml that the playbook does not implement yet
# - current-value paths: comma-separated keys under `utilities.<key>` shown by `utils --list`
# Keep this table in sync when changing tags in k8s-utilities-playbook.yaml.
# master.yaml blocks without an entry here are listed as "in development" automatically.
UTILITY_REGISTRY=(
    "ingress_test|ingressTestDeployment|Deploy a test nginx Deployment + Service + Ingress|ingressClass: traefik|ingressClass: nginx, cilium, kong (archived controllers, see the archive NOTE above SETUP_REGISTRY_KIND)|ingressClass,host"
    "apigateway_test|apiGatewayTestDeployment|Deploy a test Gateway + HTTPRoute (Gateway API)|gatewayClass: traefik|gatewayClass: cilium, kong (archived controllers; templates in ansible/templates/archives/)|gatewayClass,host"
    "certmanager|certmanager|Install cert-manager|selfSignedIssuer (local CA for *.kubewekend.local hosts)||selfSignedIssuer.enable"
    "dashboard|dashboard|Install a Kubernetes dashboard|type: kubernetes-dashboard, headlamp, rancher||type,host"
    "storage|storage|Install Kubernetes Storage for workloads provisioned|type: longhorn (namespace longhorn-system; longhorn.setup: iscsi, nfs; longhorn.replicaStorage), local-path (rancher local-path-provisioner manifest); test.enable: nginx Pod + 2Gi RWO PVC (StorageClass = type) in test.namespace|csi.nfs (nfs-subdir-external-provisioner or csi-driver-nfs)|type,longhorn.setup.iscsi,longhorn.setup.nfs,longhorn.replicaStorage,test.enable"
    "secret_management|secretManagement|Install Vault or OpenBao|type: vault, openbao; config.mode: dev, standalone (needs a StorageClass); config.injector (Vault agent injector); host, ingressClass||type,config.mode,config.injector,host"
    "k8s_extensions|extensions|Install cluster extensions|reflector, reloader, externalsecrets|sealedsecrets, schemahero|reflector.enable,reloader.enable,externalsecrets.enable"
    "gitops|gitops|Install GitOps tooling|type: argocd (argocdImageUpdater, argocdExtensions), flux (ui); kargo||type,kargo.enable"
    "security|security|Install a policy engine and an identity provider|policy.type: kyverno, opa-gatekeeper; identity.type: dex|policy.type: default (VAP/MAP); kubernetesAuth.type: impersonation-proxy (impersonationProxy.type: pinniped; conf: issuerUrl, clientId, clientSecret), oidc, authentication-proxy; intelligence.type: falco, tetragon|policy.type,identity.enable"
    "monitoring|monitoring|Install the LGTM observability stack|type: kube-prometheus-stack; apm: alloy; logging: loki; tracing: tempo; profiling: pyroscope; alertmanager; grafana operator|alertmanager.config (notification, oncall); logging.config.collector; logging.config.pattern_ingester|type,apm.enable,logging.enable,tracing.enable,profiling.enable"
    "service_mesh|serviceMesh|Install the Istio service mesh|type: istio (sidecar mode)|dataplane.mode: ambient|type,dataplane.mode"
)

# Field accessors for a registry entry
_util_field() { local -a f; IFS='|' read -r -a f <<< "$1"; printf '%s' "${f[$2]:-}"; }

# Registry entry for a tag (empty when the tag is unknown)
_util_entry() {
    local entry
    for entry in "${UTILITY_REGISTRY[@]}"; do
        [[ "$(_util_field "$entry" 0)" == "$1" ]] && { printf '%s' "$entry"; return 0; }
    done
    return 1
}

# Read `<top>.<dotted.path>` from a host_vars YAML file, matching the exact indentation (2 spaces per level)
# so that nested keys with the same name (e.g. `enable`, `type`) never collide.
# Scalars are returned as-is, block lists ("- item") comma-joined, block scalars (`|`) as "(multi-line)".
# Missing keys return an empty string.
_yaml_get() {
    local file="$1" top="$2" path="$3" data indent=2 part last line value
    [[ -f "$file" ]] || return 0
    data=$(_yblock "$top" "$file")
    local -a parts
    IFS='.' read -r -a parts <<< "$path"
    last="${parts[${#parts[@]}-1]}"
    for part in "${parts[@]:0:${#parts[@]}-1}"; do
        data=$(printf '%s\n' "$data" | _ysub "$part" "$indent")
        indent=$((indent + 2))
    done
    line=$({ printf '%s\n' "$data" | grep -m1 -E "^ {${indent}}${last}:" || true; })
    [[ -n "$line" ]] || return 0
    value=$(printf '%s\n' "$line" | sed -E 's/^[^:]*:[[:space:]]*//; s/[[:space:]]+#.*$//; s/^#.*$//' \
        | tr -d '"' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
    case "$value" in
        "|"|"|-"|">"|">-") value="(multi-line)" ;;
        "")
            value=$(printf '%s\n' "$data" | _ysub "$last" "$indent" \
                | { grep -E '^[[:space:]]*-[[:space:]]' || true; } \
                | sed -E 's/^[[:space:]]*-[[:space:]]*//; s/[[:space:]]+#.*$//' | tr -d '"' \
                | paste -sd, - | sed 's/,/, /g') ;;
    esac
    printf '%s' "$value"
}

# Read `utilities.<block>.<dotted.path>` from master.yaml
_util_value() { _yaml_get "$HOST_VARS_DIR/master.yaml" "utilities" "$1.$2"; }

# Highlight a current value from master.yaml / worker.yaml for `--list` output:
# bold green when set, red "(unset)" when the key is missing
_cur() {
    if [[ -n "$1" ]]; then
        printf '%s' "${BOLD}${GREEN}$1${NC}"
    else
        printf '%s' "${RED}(unset)${NC}"
    fi
}

# Bold "current:" label used by the `--list` views
_cur_label() { printf '%s' "${BOLD}current:${NC}"; }

# Top-level keys under `utilities:` in master.yaml
_util_master_blocks() {
    local file="$HOST_VARS_DIR/master.yaml"
    [[ -f "$file" ]] || return 0
    _yblock "utilities" "$file" | { grep -E '^  [A-Za-z][A-Za-z0-9]*:' || true; } | sed -E 's/^  ([A-Za-z0-9]+):.*/\1/'
}

# master.yaml blocks that no tag installs yet, with their documented options when available
_util_in_development() {
    local file="$HOST_VARS_DIR/master.yaml" block entry known opts
    for block in $(_util_master_blocks); do
        known=false
        for entry in "${UTILITY_REGISTRY[@]}"; do
            [[ "$(_util_field "$entry" 1)" == "$block" ]] && { known=true; break; }
        done
        [[ "$known" == true ]] && continue
        # Options from the inline comment of `type:` (e.g. `type: "k8gb"  # k8gb`), else the sub-keys
        opts=$(_yblock "utilities" "$file" | _ysub "$block" 2 \
            | { grep -m1 -E '^    type:.*#' || true; } | sed -E 's/^[^#]*#[[:space:]]*//')
        if [[ -z "$opts" ]]; then
            opts=$(_yblock "utilities" "$file" | _ysub "$block" 2 \
                | { grep -E '^    [A-Za-z][A-Za-z0-9]*:' || true; } | sed -E 's/^    ([A-Za-z0-9]+):.*/\1/' \
                | { grep -v '^enable$' || true; } | paste -sd, - | sed 's/,/, /g')
        fi
        printf '%s|%s\n' "$block" "$opts"
    done
}

# Compact tag table for the kind/k3s/rke2 help pages
utils_help_section() {
    local entry dev_blocks
    echo "UTILITY TAGS (options supported by k8s-utilities-playbook.yaml; enable each in master.yaml)"
    for entry in "${UTILITY_REGISTRY[@]}"; do
        printf "  %-20s %s\n" "$(_util_field "$entry" 0)" "$(_util_field "$entry" 2)"
        printf "  %-20s   options: %s\n" "" "$(_util_field "$entry" 3)"
    done
    dev_blocks=$(_util_in_development | cut -d'|' -f1 | paste -sd, - | sed 's/,/, /g')
    if [[ -n "$dev_blocks" ]]; then
        echo ""
        echo "  In development (in master.yaml, no tag yet): $dev_blocks"
    fi
    echo "  Details and current values from master.yaml: ./scripts/setup.sh <kind|k3s|rke2> utils --list"
    echo ""
}

# Full list: tags, supported / in-development options and the current values from master.yaml
utils_list() {
    local file="$HOST_VARS_DIR/master.yaml" entry tag key desc opts dev paths path enabled status current line
    header "Kubewekend utility tags"
    printf "  Playbook: ${BOLD}%s${NC}\n" "$ANSIBLE_DIR/k8s-utilities-playbook.yaml"
    printf "  Values:   ${BOLD}%s${NC}\n" "$file"
    [[ -f "$file" ]] || warn "master.yaml not found: status and current values are unavailable"

    _sec "SUPPORTED TAGS"
    for entry in "${UTILITY_REGISTRY[@]}"; do
        tag=$(_util_field "$entry" 0);  key=$(_util_field "$entry" 1)
        desc=$(_util_field "$entry" 2); opts=$(_util_field "$entry" 3)
        dev=$(_util_field "$entry" 4);  paths=$(_util_field "$entry" 5)
        enabled=$(_util_value "$key" "enable")
        if [[ "$enabled" == "true" ]]; then status="${GREEN}ON ${NC}"; else status="${RED}OFF${NC}"; fi
        printf "  ${CYAN}%-20s${NC} %s  %s\n" "$tag" "$status" "$desc"
        printf "  %-20s      key:     utilities.%s\n" "" "$key"
        printf "  %-20s      options: %s\n" "" "$opts"
        [[ -n "$dev" ]] && printf "  %-20s      ${YELLOW}in dev:${NC}  %s\n" "" "$dev"
        current=""
        IFS=',' read -r -a line <<< "$paths"
        for path in "${line[@]}"; do
            [[ -n "$path" ]] && current+="${path}=$(_cur "$(_util_value "$key" "$path")") "
        done
        [[ -n "$current" ]] && printf "  %-20s      %s %s\n" "" "$(_cur_label)" "${current% }"
    done

    _sec "IN DEVELOPMENT (defined in master.yaml, not supported yet)"
    local block bopts found=false
    while IFS='|' read -r block bopts; do
        [[ -z "$block" ]] && continue
        found=true
        printf "  ${YELLOW}%-20s${NC} %s\n" "$block" "${bopts:--}"
    done < <(_util_in_development)
    [[ "$found" == true ]] || echo "  (none)"

    echo ""
    info "Install: ./scripts/setup.sh <kind|k3s|rke2> utils <tag...>  (set utilities.<key>.enable: true first)"
}

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

# ---------------------------------------------------------------------------
# Cluster setup options: one registry per distribution (kindCluster / k3sCluster / rke2Cluster in master.yaml)
# ---------------------------------------------------------------------------
# One entry per top-level key of the cluster block:
#   key | description | supported options | in development | current-value paths
# - supported options: what the setup playbooks / templates implement today
# - in development:    options documented in master.yaml that the playbooks do not read yet
# - current-value paths: comma-separated keys under `<cluster>.` shown by `config --list`
# Keep these tables in sync with kind-playbook / k3s-(ha-)playbook / rke2-(ha-)playbook and their templates.
# Cluster keys without an entry here are listed as "in development" automatically.
#
# NOTE — Archived (2026-11-20): ingress / Gateway API controllers other than Traefik.
#   NGINX, Kong and Cilium ingress, and Kong and Cilium Gateway API, changed too often to keep working, so
#   Kubewekend now supports Traefik only, for Kind, K3s and RKE2. They are archived, not deleted:
#   - Kind tasks: commented out in ansible/kind-playbook.yaml ("(Archive - Stop supporting)" blocks)
#   - RKE2 ingress-nginx (`rke2Cluster.ingress.class: ingress-nginx`): no longer in rke2-playbook.yaml or
#     rke2-ha-playbook.yaml; its HelmChartConfig template is ansible/templates/archives/rke2-ingress-nginx-config.yaml.j2
#   - test-deployment templates: ansible/templates/archives/
#   - version pins: commented-out entries in VERSION_REGISTRY (kong, traefik-gateway-rbac)
#   Cilium stays supported as CNI (`cni: cilium`) and as the Kind load balancer (`loadbalancer.type: cilium-ipam-lb`).
#   To restore one: uncomment its tasks / registry entries and move it back to the supported options below.
KIND_ARCHIVED_INGRESS_CLASSES="nginx kong cilium"
KIND_ARCHIVED_GATEWAY_CLASSES="kong cilium"
RKE2_ARCHIVED_INGRESS_CLASSES="ingress-nginx"
SETUP_REGISTRY_KIND=(
    "numberOfNodes|Node count (Kind always needs one control-plane)|controlPlane, worker||numberOfNodes.controlPlane,numberOfNodes.worker"
    "image|Node image, sets the Kubernetes version|kindest/node:<version>||image"
    "networking|API server, subnets, CNI and kube-proxy|apiServer; podSubnet; serviceSubnet; disableDefaultCNI (kindnet); cni: calico, flannel, cilium; kubeProxyMode: iptables, nftables, ipvs, none||networking.disableDefaultCNI,networking.cni,networking.kubeProxyMode,networking.podSubnet,networking.serviceSubnet"
    "loadbalancer|Service type LoadBalancer|type: cloud-provider-kind, metallb, cilium-ipam-lb (needs cni: cilium)||loadbalancer.enable,loadbalancer.type"
    "ingress|Ingress controller (Traefik only)|class: traefik; traefik.ports (web, websecure); traefik.allowCrossNamespace; traefik.dashboard (enable, host)|class: nginx, kong, cilium (archived, see NOTE above)|ingress.enable,ingress.class,ingress.traefik.dashboard.enable"
    "apigateway|Gateway API controller (Traefik only)|class: traefik; crd (install, version)|class: kong, cilium (archived, see NOTE above)|apigateway.enable,apigateway.class,apigateway.crd.install"
    "networkForwarding|Forward host ports 80/443 to the cluster (socat services)|enable||networkForwarding.enable"
)
SETUP_REGISTRY_K3S=(
    "version|K3s release, sets the Kubernetes version|vX.Y.Z+k3sN||version"
    "highAvailability|HA control plane, used by \`k3s ha-setup\`|dataStorage.type: etcd, postgres (externalDatabase)|clusterLB (bring your own HAProxy / Kube-VIP)|highAvailability.dataStorage.type"
    "tlsSANs|Extra SANs for the API server certificate|list of hostnames / IPs||tlsSANs"
    "nodeLabels|Kubelet node labels|list of key=value||nodeLabels"
    "nodeTaints|Kubelet node taints|list of key=value:effect||nodeTaints"
    "cni|CNI plugin|type: flannel (default), calico, cilium||cni.type"
    "loadBalancer|Service type LoadBalancer|type: servicelb, metallb||loadBalancer.enable,loadBalancer.type"
    "ingress|Traefik ingress controller (Helm; the bundled K3s Traefik is disabled)|class: traefik; traefik.ports (web, websecure); traefik.allowCrossNamespace; traefik.dashboard (enable, host); traefik.gateway (enable, crd.install, crd.version)||ingress.enable,ingress.class,ingress.traefik.dashboard.enable,ingress.traefik.gateway.enable"
)
SETUP_REGISTRY_RKE2=(
    "version|RKE2 release, sets the Kubernetes version|vX.Y.Z+rke2rN||version"
    "highAvailability|HA control plane, used by \`rke2 ha-setup\`|dataStorage.type: etcd, postgres (externalDatabase)|clusterLB (bring your own HAProxy / Kube-VIP)|highAvailability.dataStorage.type"
    "tlsSANs|Extra SANs for the API server certificate|list of hostnames / IPs||tlsSANs"
    "nodeLabels|Kubelet node labels|list of key=value||nodeLabels"
    "nodeTaints|Kubelet node taints|list of key=value:effect||nodeTaints"
    "cni|CNI plugin|type: canal (default), calico, cilium, flannel||cni.type"
    "loadBalancer|Service type LoadBalancer|type: servicelb, metallb||loadBalancer.enable,loadBalancer.type"
    "ingress|Bundled Traefik ingress controller|class: traefik; config.traefik (HelmChartConfig values)|class: ingress-nginx (archived, see the archive NOTE above SETUP_REGISTRY_KIND)|ingress.enable,ingress.class"
)

# master.yaml top-level key for a distribution
_setup_top() {
    case "$1" in
        kind) echo "kindCluster" ;;
        k3s)  echo "k3sCluster" ;;
        rke2) echo "rke2Cluster" ;;
        *)    return 1 ;;
    esac
}

# Print the registry entries of a distribution, one per line
_setup_entries() {
    local -n _reg="SETUP_REGISTRY_${1^^}"
    printf '%s\n' "${_reg[@]}"
}

# Cluster keys that no playbook reads yet: "key|current value or sub-keys"
_setup_in_development() {
    local distro="$1" top file="$HOST_VARS_DIR/master.yaml" key value known
    top=$(_setup_top "$distro") || return 0
    [[ -f "$file" ]] || return 0
    known=$(_setup_entries "$distro" | cut -d'|' -f1)
    for key in $(_yblock "$top" "$file" | { grep -E '^  [A-Za-z][A-Za-z0-9]*:' || true; } | sed -E 's/^  ([A-Za-z0-9]+):.*/\1/'); do
        grep -qx "$key" <<< "$known" && continue
        value=$(_yaml_get "$file" "$top" "$key")
        if [[ -z "$value" ]]; then
            value=$(_yblock "$top" "$file" | _ysub "$key" 2 \
                | { grep -E '^    [A-Za-z][A-Za-z0-9]*:' || true; } | sed -E 's/^    ([A-Za-z0-9]+):.*/\1/' \
                | paste -sd, - | sed 's/,/, /g')
        fi
        printf '%s|%s\n' "$key" "$value"
    done
}

# Compact setup-option table for the kind/k3s/rke2 help pages
setup_help_section() {
    local distro="$1" top entry key desc opts dev_keys
    top=$(_setup_top "$distro") || return 0
    echo "SETUP OPTIONS (master.yaml → $top)"
    while IFS= read -r entry; do
        IFS='|' read -r key desc opts _ <<< "$entry"
        printf "  %-20s %s\n" "$key" "$desc"
        printf "  %-20s   options: %s\n" "" "$opts"
    done < <(_setup_entries "$distro")
    dev_keys=$(_setup_in_development "$distro" | cut -d'|' -f1 | paste -sd, - | sed 's/,/, /g')
    [[ -n "$dev_keys" ]] && echo "" && echo "  In development (in master.yaml, not read by the playbooks yet): $dev_keys"
    echo "  Details and current values from master.yaml: ./scripts/setup.sh config --list $distro"
    echo ""
}

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

# Warn when master.yaml selects an ingress / Gateway API class whose tasks are archived (see the archive NOTE
# above SETUP_REGISTRY_KIND): the playbook would not install that controller, or not the way you expect.
# Usage: _check_archived_classes <kind|rke2>
_check_archived_classes() {
    local file="$HOST_VARS_DIR/master.yaml" top enabled class
    case "$1" in
        kind)
            top="kindCluster"
            enabled=$(_yaml_get "$file" "$top" ingress.enable); class=$(_yaml_get "$file" "$top" ingress.class)
            if [[ "$enabled" == "true" && " $KIND_ARCHIVED_INGRESS_CLASSES " == *" $class "* ]]; then
                warn "$top.ingress.class: $class is archived, so no ingress controller will be installed (supported: traefik)"
            fi
            enabled=$(_yaml_get "$file" "$top" apigateway.enable); class=$(_yaml_get "$file" "$top" apigateway.class)
            if [[ "$enabled" == "true" && " $KIND_ARCHIVED_GATEWAY_CLASSES " == *" $class "* ]]; then
                warn "$top.apigateway.class: $class is archived, so no Gateway API controller will be installed (supported: traefik)"
            fi
            ;;
        rke2)
            top="rke2Cluster"
            enabled=$(_yaml_get "$file" "$top" ingress.enable); class=$(_yaml_get "$file" "$top" ingress.class)
            if [[ "$enabled" == "true" && " $RKE2_ARCHIVED_INGRESS_CLASSES " == *" $class "* ]]; then
                warn "$top.ingress.class: $class is archived and no longer supported (supported: traefik)"
            fi
            ;;
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
# A missing key returns an empty string instead of failing: under `set -euo pipefail` a grep without a match
# would otherwise abort the whole command (e.g. `config show` after a key moves in master.yaml).
_yval() {
    { grep -m1 "^\s*${1}:" || true; } \
      | sed 's/[^:]*:[[:space:]]*//' \
      | tr -d '"' \
      | sed 's/[[:space:]]*#.*//' \
      | sed -E 's/^[[:space:]]+|[[:space:]]+$//g'
}

# Collect YAML list items ("  - value") from stdin → comma-joined
_ylist() {
    local result
    result=$({ grep "^\s*-[[:space:]]" || true; } \
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
    # printf repetition instead of `tr`, which is byte-based and garbles the multi-byte '─'
    printf '  %s\n' "$(printf '─%.0s' {1..52})"
}

# ---------------------------------------------------------------------------
# config show: master.yaml summary table
# ---------------------------------------------------------------------------
config_show_master() {
    local file="$HOST_VARS_DIR/master.yaml"
    [[ -f "$file" ]] || { error "File not found: $file"; return 1; }

    header "Master Node Configuration"
    printf "  File: ${BOLD}%s${NC}\n" "$file"

    local kind k3s rke2 util
    kind=$(_yblock "kindCluster" "$file")
    k3s=$( _yblock "k3sCluster"  "$file")
    rke2=$(_yblock "rke2Cluster" "$file")
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

    # Traefik dashboard: ingress.traefik.dashboard; Gateway API CRDs: apigateway.crd
    local k_dash k_dash_en k_dash_host k_crd k_crd_install k_crd_ver
    k_dash=$(       echo "$k_ing"  | _ysub "traefik" 4 | _ysub "dashboard" 6)
    k_dash_en=$(    echo "$k_dash" | _yval "enable")
    k_dash_host=$(  echo "$k_dash" | _yval "host")
    k_crd=$(        echo "$k_gw"   | _ysub "crd" 4)
    k_crd_install=$(echo "$k_crd"  | _yval "install")
    k_crd_ver=$(    echo "$k_crd"  | _yval "version")

    _row "Node Image"          "$k_image"
    _row "Pod Subnet"          "$k_pod"
    _row "Service Subnet"      "$k_svc"
    _row "CNI"                 "$k_cni  (disable default: $k_dis_cni)"
    _row "kube-proxy Mode"     "$k_proxy"
    _row "Load Balancer"       "$(_badge "$k_lb_en" "$k_lb_type")"
    [[ "$k_lb_type" == "metallb" ]] && \
        _row "  LB IP Pool"    "$k_lb_cidr"
    _row "Ingress"             "$(_badge "$k_ing_en" "$k_ing_cls")"
    _row "  Dashboard"         "$(_badge "$k_dash_en" "$k_dash_host")"
    _row "API Gateway"         "$(_badge "$k_gw_en" "$k_gw_cls")"
    _row "  Gateway API CRDs"  "$(_badge "$k_crd_install" "$k_crd_ver")"
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
    # Traefik options live under ingress.traefik (dashboard, gateway, ports, allowCrossNamespace)
    local k3_trf k3_gw k3_gw_crd gw_en crd_install crd_ver
    k3_trf=$(     echo "$k3_ing" | _ysub "traefik"          4)
    k3_ing_dash=$(echo "$k3_trf" | _ysub "dashboard"        6)
    k3_gw=$(      echo "$k3_trf" | _ysub "gateway"          6)
    k3_gw_crd=$(  echo "$k3_gw"  | _ysub "crd"              8)
    gw_en=$(      echo "$k3_gw"     | _yval "enable")
    crd_install=$(echo "$k3_gw_crd" | _yval "install")
    crd_ver=$(    echo "$k3_gw_crd" | _yval "version")

    local version ha_db_type cni_type lb_en lb_type lb_cidr
    local ing_en ing_cls dash_en dash_host labels tlssans
    version=$(    echo "$k3s"         | _yval "version")
    ha_db_type=$( echo "$k3_ds"       | _yval "type")
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
    # HA is not a master.yaml switch: `k3s ha-setup` + the inventory groups decide the control-plane count
    _row "High Availability" "datastore: $ha_db_type (used by \`k3s ha-setup\`; nodes from inventory)"
    _row "CNI"              "$cni_type"
    _row "Load Balancer"    "$(_badge "$lb_en" "$lb_type")"
    [[ "$lb_type" == "metallb" ]] && \
        _row "  LB IP Pool"    "$lb_cidr"
    _row "Ingress"          "$(_badge "$ing_en" "$ing_cls")"
    _row "  Dashboard"      "$(_badge "$dash_en" "$dash_host")"
    _row "  Gateway API"    "$(_badge "$gw_en" "traefik provider, CRDs: $( [[ "$crd_install" == "true" ]] && echo "${crd_ver:-?}" || echo "not installed")")"
    _row "Node Labels"      "$labels"
    _row "TLS SANs"         "$tlssans"

    # ---- RKE2 CLUSTER --------------------------------------------------------
    _sec "RKE2 CLUSTER"

    local rk_ha rk_ds rk_db rk_cni rk_lb rk_lb_pool rk_ing
    rk_ha=$(      echo "$rke2"    | _ysub "highAvailability" 2)
    rk_ds=$(      echo "$rk_ha"  | _ysub "dataStorage"      4)
    rk_db=$(      echo "$rk_ds"  | _ysub "externalDatabase" 6)
    rk_cni=$(     echo "$rke2"    | _ysub "cni"              2)
    rk_lb=$(      echo "$rke2"    | _ysub "loadBalancer"     2)
    rk_lb_pool=$( echo "$rk_lb"  | _ysub "ippool"           4)
    rk_ing=$(     echo "$rke2"    | _ysub "ingress"          2)

    local version ha_db_type cni_type lb_en lb_type lb_cidr
    local ing_en ing_cls labels tlssans
    version=$(    echo "$rke2"         | _yval "version")
    ha_db_type=$( echo "$rk_ds"       | _yval "type")
    cni_type=$(   echo "$rk_cni"      | _yval "type")
    lb_en=$(      echo "$rk_lb"       | _yval "enable")
    lb_type=$(    echo "$rk_lb"       | _yval "type")
    lb_cidr=$(    echo "$rk_lb_pool"  | _yval "cidr")
    ing_en=$(     echo "$rk_ing"      | _yval "enable")
    ing_cls=$(    echo "$rk_ing"      | _yval "class")
    labels=$(     echo "$rke2"         | _ysub "nodeLabels" 2 | _ylist)
    tlssans=$(    echo "$rke2"         | _ysub "tlsSANs"    2 | _ylist)

    _row "Version"          "$version"
    # HA is not a master.yaml switch: `rke2 ha-setup` + the inventory groups decide the control-plane count
    _row "High Availability" "datastore: $ha_db_type (used by \`rke2 ha-setup\`; nodes from inventory)"
    _row "CNI"              "$cni_type"
    _row "Load Balancer"    "$(_badge "$lb_en" "$lb_type")"
    [[ "$lb_type" == "metallb" ]] && \
        _row "  LB IP Pool"    "$lb_cidr"
    _row "Ingress"          "$(_badge "$ing_en" "$ing_cls")"
    _row "Node Labels"      "$labels"
    _row "TLS SANs"         "$tlssans"

    # ---- UTILITIES ----------------------------------------------------------
    _sec "UTILITIES"

    local u_ing u_gw u_cm u_dash u_stor u_sec u_git u_ext u_security u_mon u_svcmesh
    u_ing=$(     echo "$util" | _ysub "ingressTestDeployment"    2)
    u_gw=$(      echo "$util" | _ysub "apiGatewayTestDeployment" 2)
    u_cm=$(      echo "$util" | _ysub "certmanager"              2)
    u_dash=$(    echo "$util" | _ysub "dashboard"                2)
    u_stor=$(    echo "$util" | _ysub "storage"                  2)
    u_sec=$(     echo "$util" | _ysub "secretManagement"         2)
    u_git=$(     echo "$util" | _ysub "gitops"                   2)
    u_ext=$(     echo "$util" | _ysub "extensions"               2)
    u_security=$(echo "$util" | _ysub "security"                 2)
    u_mon=$(     echo "$util" | _ysub "monitoring"               2)
    u_svcmesh=$( echo "$util" | _ysub "serviceMesh"              2)

    local ing_en2 ing_host gw_en gw_host cm_en
    local dash_en2 dash_type 
    local stor_en stor_type stor_test stor_test_en
    local git_en git_type
    local ext_en ext_reloader ext_eso ext_reflector
    local sec_en sec_type
    local security_en policy_en policy_type identity_en identity_type k8sauth_en k8sauth_type 
    local mon_en mon_type 
    local svcmesh_en svcmesh_type
    ing_en2=$(    echo "$u_ing"      | _yval "enable")
    ing_host=$(   echo "$u_ing"      | _yval "host")
    gw_en=$(      echo "$u_gw"       | _yval "enable")
    gw_host=$(    echo "$u_gw"       | _yval "host")
    cm_en=$(      echo "$u_cm"       | _yval "enable")
    dash_en2=$(   echo "$u_dash"     | _yval "enable")
    dash_type=$(  echo "$u_dash"     | _yval "type")
    stor_en=$(    echo "$u_stor"     | _yval "enable")
    stor_type=$(  echo "$u_stor"     | _yval "type")
    stor_test=$(  echo "$u_stor"     | _ysub "test" 4)
    stor_test_en=$(echo "$stor_test" | _yval "enable")
    sec_en=$(     echo "$u_sec"      | _yval "enable")
    sec_type=$(   echo "$u_sec"      | _yval "type")
    git_en=$(     echo "$u_git"      | _yval "enable")
    git_type=$(   echo "$u_git"      | _yval "type")
    ext_en=$(     echo "$u_ext"      | _yval "enable")
    ext_reloader=$(echo "$u_ext" | _ysub "reloader" 4 | _yval "enable")
    ext_eso=$(echo "$u_ext" | _ysub "externalsecrets" 4 | _yval "enable")
    ext_reflector=$(echo "$u_ext"| _ysub "reflector" 4 | _yval "enable")
    security_en=$(echo "$u_security" | _yval "enable")
    policy_en=$(echo "$u_security" | _ysub "policy" 4 | _yval "enable")
    policy_type=$(echo "$u_security" | _ysub "policy" 4 | _yval "type")
    identity_en=$(echo "$u_security" | _ysub "identity" 4 | _yval "enable")
    identity_type=$(echo "$u_security" | _ysub "identity" 4 | _yval "type")
    k8sauth_en=$(echo "$u_security" | _ysub "kubernetesAuth" 4 | _yval "enable")
    k8sauth_type=$(echo "$u_security" | _ysub "kubernetesAuth" 4 | _yval "type")
    mon_en=$(     echo "$u_mon"      | _yval "enable")
    mon_type=$(   echo "$u_mon"      | _yval "type")
    svcmesh_en=$( echo "$u_svcmesh"  | _yval "enable")
    svcmesh_type=$(echo "$u_svcmesh" | _yval "type")

    _sec "UTILITIES — TEST DEPLOYMENTS"
    _row "Ingress Test"       "$(_badge "$ing_en2"  "$(echo "$u_ing" | _yval "ingressClass") → $ing_host")"
    _row "API Gateway Test"   "$(_badge "$gw_en"    "$(echo "$u_gw" | _yval "gatewayClass") → $gw_host")"
    # Runs with the `storage` tag (needs utilities.storage.enable); the PVC uses the StorageClass named after storage.type
    _row "Storage Test (PVC)" "$(_badge "$stor_test_en" "RWO 2Gi on $stor_type → ns $(echo "$stor_test" | _yval "namespace")")"

    _sec "UTILITIES — CLUSTER SERVICES"
    _row "Cert-Manager"       "$(_badge "$cm_en")"
    _row "Dashboard"          "$(_badge "$dash_en2" "$dash_type")"
    _row "Storage"            "$(_badge "$stor_en"  "$stor_type")"
    _row "Secret Management"  "$(_badge "$sec_en"   "$sec_type")"
    _row "Extensions"         "$(_badge "$ext_en" "externalsecrets: $ext_eso, reloader: $ext_reloader, reflector: $ext_reflector")"

    _sec "UTILITIES — GITOPS & SECURITY"
    _row "GitOps"             "$(_badge "$git_en"   "$git_type")"
    _row "Security"           "$(_badge "$security_en")"
    _row "  Security (Policy)"  "$(_badge "$policy_en" "$policy_type")"
    _row "  Security (Identity)" "$(_badge "$identity_en" "$identity_type")"
    _row "  Security (K8s Auth)" "$(_badge "$k8sauth_en" "$k8sauth_type")"

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

    local k3s rke2
    k3s=$(_yblock "k3sCluster" "$file")
    rke2=$(_yblock "rke2Cluster" "$file")

    _sec "K3S AGENT"

    local version labels taints
    version=$(echo "$k3s" | _yval "version")
    labels=$( echo "$k3s" | _ysub "nodeLabels" 2 | _ylist)
    taints=$( echo "$k3s" | _ysub "nodeTaints" 2 | _ylist)

    _row "Version"     "$version"
    _row "Node Labels" "$labels"
    _row "Node Taints" "$taints"

    _sec "RKE2 AGENT"

    local version labels taints
    version=$(echo "$rke2" | _yval "version")
    labels=$( echo "$rke2" | _ysub "nodeLabels" 2 | _ylist)
    taints=$( echo "$rke2" | _ysub "nodeTaints" 2 | _ylist)

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
  list [target]         Supported setup / utility options with current values from master.yaml
                        target: kind | k3s | rke2 | utils (default: kind, k3s and rke2)
                        aliases: --list, -l
  show [--raw]          Summary table of master.yaml (--raw: full file)
  edit                  Open master.yaml in $EDITOR
  worker-show [--raw]   Summary table of worker.yaml (--raw: full file)
  worker-edit           Open worker.yaml in $EDITOR

EXAMPLES
  ./scripts/setup.sh config --list
  ./scripts/setup.sh config --list k3s
  ./scripts/setup.sh config --list utils
  ./scripts/setup.sh config show
  ./scripts/setup.sh config show --raw
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
# COMMAND: versions — list and bump pinned versions (charts, tools, manifests)
# ---------------------------------------------------------------------------
# One entry per pinned component (also the source of the README.md "Versions" table, see `versions sync`):
#   name | group | files (globs relative to the project root) | anchor (ERE) | extract (ERE, group 1 = version) | note
# - note (optional): essential configuration Kubewekend applies to the component, shown in `versions list`,
#   the `versions bump` preview and the README.md Versions table, so users do not need to read the playbooks.
#   Plain text or Markdown code spans; no `|` and no single quote.
# - The anchor finds the line; the version is read with `extract` from that line or one of the next 4 lines
#   (multi-line `helm upgrade --install` commands, `repository:` + `tag:`, `- name:` + `version:` in Chart.yaml).
# - Helm charts leave `extract` empty: it defaults to `--version <v>`.
# - Pins are located by pattern, not line number, so edits elsewhere in the files do not break them.
# - Patterns must not contain `|` (field separator): use `( .*)?$` instead of `( |$)` alternations.
# - Groups (in display order): kubernetes, host-tools, networking, utilities, templates, charts, examples, repo-tooling.
# Not tracked (listed by hand in README.md): unpinned tools (kubectl, Helm, Calico, Flux CLI).
VERSION_REGISTRY=(
    # --- Kubernetes distributions (ansible/inventories/host_vars) ---
    'kind-node|kubernetes|ansible/inventories/host_vars/master.yaml|kindest/node:v|kindest/node:(v[0-9][^" ]*)'
    'k3s|kubernetes|ansible/inventories/host_vars/master.yaml ansible/inventories/host_vars/worker.yaml|^ +version: "v[^"]+\+k3s|version: "(v[^"]+)"'
    'rke2|kubernetes|ansible/inventories/host_vars/master.yaml ansible/inventories/host_vars/worker.yaml|^ +version: "v[^"]+\+rke2|version: "(v[^"]+)"'
    'gateway-api-crd|kubernetes|ansible/inventories/host_vars/master.yaml|^ +crd: *$|version: "(v[^"]+)"|Standard channel CRDs applied before the Traefik Gateway API provider: Kind `apigateway.crd`, K3s `ingress.traefik.gateway.crd` (when `install: true`); keep both on the same version'
    # --- Host tools (install_common + Python requirements) ---
    'ansible|host-tools|requirements.txt|^ansible==|ansible==([0-9][^ ]*)'
    'ansible-core|host-tools|requirements.txt|^ansible-core==|ansible-core==([0-9][^ ]*)'
    'kind-cli|host-tools|ansible/kind-playbook.yaml|kind\.sigs\.k8s\.io/dl/|kind\.sigs\.k8s\.io/dl/(v[^/]+)/'
    'vault-cli|host-tools|ansible/*-playbook.yaml|releases\.hashicorp\.com/vault/|releases\.hashicorp\.com/vault/([0-9][^/]*)/'
    'openbao-cli|host-tools|ansible/*-playbook.yaml|openbao/releases/download/|openbao/releases/download/v([0-9][^/]*)/'
    'weave-gitops-cli|host-tools|ansible/k8s-utilities-playbook.yaml|weave-gitops/releases/download/|weave-gitops/releases/download/(v[^/]+)/'
    # --- Cluster networking (setup playbooks) ---
    'cloud-provider-kind|networking|ansible/kind-playbook.yaml|/cloud-provider-kind:|cloud-provider-kind:([^ ]+)|Runs as a Docker container on the `kind` network, not inside the cluster'
    'metallb|networking|ansible/*.yaml|metallb/metallb( .*)?$||L2 mode; the IP pool comes from `<cluster>.loadBalancer.ippool.cidr` (Kind: `kindCluster.loadbalancer.ippool.cidr`)'
    'cni-plugins|networking|ansible/kind-playbook.yaml|containernetworking/plugins/releases/download/|plugins/releases/download/(v[^/]+)/|Required for Kind run Flannel CNI; not needed for K3s or RKE2'
    'flannel|networking|ansible/kind-playbook.yaml|flannel-io/flannel/refs/tags/|flannel/refs/tags/(v[^/]+)/'
    'cilium|networking|ansible/*.yaml|cilium/cilium( .*)?$||CNI only (Hubble relay + UI, `ipam.mode=cluster-pool`, 1 operator replica) when `cni: cilium` (Kind needs `disableDefaultCNI: true`); Kind ingress / Gateway API with Cilium are archived'
    'traefik|networking|ansible/*.yaml|traefik/traefik( .*)?$||Only ingress / Gateway API controller for Kind, K3s and RKE2 (NGINX, Kong, Cilium and RKE2 ingress-nginx archived). Installed in steps: ingress, optional dashboard, optional Gateway API provider (Kind: `ingress.traefik.*`, `apigateway.class: traefik`; K3s: `ingress.traefik.dashboard.enable`, `ingress.traefik.gateway.enable`); the base install resets the dashboard and the dashboard step enables it'
    # Archived (2026-11-20), kept for reference: their tasks are commented out in ansible/kind-playbook.yaml,
    # so `versions sync` would report them as missing. Uncomment when the tasks are restored.
    # 'kong|networking|ansible/*.yaml|kong/kong( .*)?$||Kind ingress / Gateway API controller (archived)'
    # 'traefik-gateway-rbac|networking|ansible/kind-playbook.yaml|traefik/traefik/refs/tags/|traefik/refs/tags/(v[^/]+)/'
    # --- Utilities (ansible/k8s-utilities-playbook.yaml) ---
    'cert-manager|utilities|ansible/k8s-utilities-playbook.yaml|jetstack/cert-manager( .*)?$||CRDs installed by the chart (`crds.enabled=true`); optional self-signed CA issuer via `utilities.certmanager.selfSignedIssuer`'
    'kubernetes-dashboard|utilities|ansible/k8s-utilities-playbook.yaml|kubernetes-dashboard/kubernetes-dashboard( .*)?$|'
    'headlamp|utilities|ansible/k8s-utilities-playbook.yaml|headlamp/headlamp( .*)?$|'
    'rancher|utilities|ansible/k8s-utilities-playbook.yaml|rancher-stable/rancher( .*)?$|'
    'longhorn|utilities|ansible/k8s-utilities-playbook.yaml|longhorn/longhorn( .*)?$||UI with 1 replica; default volume replica count from `utilities.storage.longhorn.replicaStorage`; iSCSI / NFS node setup from `utilities.storage.longhorn.setup`; namespace `longhorn-system`'
    'local-path-provisioner|utilities|ansible/k8s-utilities-playbook.yaml|rancher/local-path-provisioner/|local-path-provisioner/(v[^/]+)/|Manifest applied when `utilities.storage.type: local-path` (StorageClass `local-path`)'
    'vault|utilities|ansible/k8s-utilities-playbook.yaml|hashicorp/vault( .*)?$||Namespace `vault`; ingress at `utilities.secretManagement.host` (`ingressClass`); `config.mode` dev (in-memory, root token) or standalone (needs a StorageClass); agent injector with `config.injector`'
    'openbao|utilities|ansible/k8s-utilities-playbook.yaml|openbao/openbao( .*)?$||Namespace `openbao`; ingress at `utilities.secretManagement.host`; `config.mode` dev or standalone (needs a StorageClass); recent charts need Kubernetes >= 1.30'
    # Archived (2026-11-20), kept for reference: the Vault Secrets Operator task is commented out in
    # k8s-utilities-playbook.yaml, so `versions sync` would report it as missing. Uncomment when restored.
    # 'vault-secrets-operator|utilities|ansible/k8s-utilities-playbook.yaml|hashicorp/vault-secrets-operator( .*)?$|'
    'reflector|utilities|ansible/k8s-utilities-playbook.yaml|emberstack/reflector( .*)?$|'
    'reloader|utilities|ansible/k8s-utilities-playbook.yaml|stakater/reloader( .*)?$|'
    'external-secrets|utilities|ansible/k8s-utilities-playbook.yaml|external-secrets/external-secrets( .*)?$|'
    'argo-cd|utilities|ansible/k8s-utilities-playbook.yaml|argo/argo-cd( .*)?$||Ingress at `utilities.gitops.argocd.host` with `server.insecure=true` (TLS ends at the ingress); bundled Dex disabled'
    'argocd-image-updater|utilities|ansible/k8s-utilities-playbook.yaml|argo/argocd-image-updater( .*)?$|'
    'argocd-extension-metrics|utilities|ansible/k8s-utilities-playbook.yaml|argocd-extension-metrics/releases/download/|argocd-extension-metrics/releases/download/(v[^/]+)/'
    'argocd-rollout-extension|utilities|ansible/k8s-utilities-playbook.yaml|rollout-extension/releases/download/|rollout-extension/releases/download/(v[^/]+)/'
    'flux|utilities|ansible/k8s-utilities-playbook.yaml|fluxcd/flux2/releases/download/|flux2/releases/download/(v[^/]+)/'
    'weave-gitops|utilities|ansible/k8s-utilities-playbook.yaml|charts/weave-gitops:|weave-gitops:([0-9][^ ]*)'
    'kargo|utilities|ansible/k8s-utilities-playbook.yaml|kargo-charts/kargo( .*)?$|'
    'gatekeeper|utilities|ansible/k8s-utilities-playbook.yaml|gatekeeper/gatekeeper( .*)?$|'
    'kyverno|utilities|ansible/k8s-utilities-playbook.yaml|kyverno/kyverno( .*)?$|'
    'dex|utilities|ansible/k8s-utilities-playbook.yaml|dex/dex( .*)?$|'
    'kube-prometheus-stack|utilities|ansible/k8s-utilities-playbook.yaml|prometheus-community/kube-prometheus-stack( .*)?$||Values from `ansible/templates/kube-prometheus-stack-values.yaml.j2`, which also pins Prometheus / Alertmanager / Thanos images (see templates)'
    'grafana-operator|utilities|ansible/k8s-utilities-playbook.yaml|grafana/grafana-operator( .*)?$|'
    'alloy|utilities|ansible/k8s-utilities-playbook.yaml|grafana/alloy( .*)?$||Values from `ansible/templates/alloy-values.yaml.j2`'
    'loki|utilities|ansible/k8s-utilities-playbook.yaml|grafana-community/loki( .*)?$||Values from `ansible/templates/loki-values.yaml.j2`'
    'tempo|utilities|ansible/k8s-utilities-playbook.yaml|grafana-community/tempo( .*)?$||Values from `ansible/templates/tempo-values.yaml.j2`'
    'pyroscope|utilities|ansible/k8s-utilities-playbook.yaml|grafana/pyroscope( .*)?$||Values from `ansible/templates/pyroscope-values.yaml.j2`'
    'istio|utilities|ansible/k8s-utilities-playbook.yaml|istio/[a-z]+( .*)?$||Installs `base` + `istiod` only (sidecar mode); `serviceMesh.dataplane.mode: ambient` is not supported yet'
#     # --- Image pins inside templates / test workloads ---
#     'alertmanager|templates|ansible/templates/kube-prometheus-stack-values.yaml.j2|repository: prometheus/alertmanager *$|tag: "?(v[^" ]+)'
#     'prometheus|templates|ansible/templates/kube-prometheus-stack-values.yaml.j2|repository: prometheus/prometheus *$|tag: "?(v[^" ]+)'
#     'thanos|templates|ansible/templates/kube-prometheus-stack-values.yaml.j2|repository: thanos/thanos *$|tag: "?(v[^" ]+)'
#     'kube-webhook-certgen|templates|ansible/templates/kube-prometheus-stack-values.yaml.j2|repository: jkroepke/kube-webhook-certgen *$|tag: "?([0-9v][^" ]*)'
#     'go-echo|templates|ansible/templates/apigateway-test-deployment.yaml.j2|image: kong/go-echo:|go-echo:([^" ]+)'
#     'ingress-test-nginx|templates|ansible/inventories/host_vars/master.yaml|^ +image: "nginx:|nginx:([^"]+)"'
#     'longhorn-iscsi-alpine|templates|ansible/templates/longhorn-iscsi-installation.yaml.j2|image: alpine:|alpine:([^" ]+)'
#     'longhorn-nfs-alpine|templates|ansible/templates/longhorn-nfs-installation.yaml.j2|image: alpine:|alpine:([^" ]+)'
#     'pause|templates|ansible/templates/longhorn-*-installation.yaml.j2|registry\.k8s\.io/pause:|pause:([^" ]+)'
#     # --- Helm charts in this repository ---
#     'chart-common|charts|kubernetes/charts/common/Chart.yaml|^version: |^version: "?([0-9][^" ]*)'
#     'chart-pinniped|charts|kubernetes/charts/pinniped/Chart.yaml|^version: |^version: "?([0-9][^" ]*)'
#     'pinniped-app|charts|kubernetes/charts/pinniped/Chart.yaml|^appVersion: |^appVersion: "?(v?[0-9][^" ]*)'
#     # --- Examples ---
#     'example-cert-manager|examples|examples/argocd-apps/manifests/platform/cert-manager/Chart.yaml|- name: cert-manager *$|version: "?(v?[0-9][^" ]*)'
#     'example-argo-rollouts|examples|examples/argocd-apps/manifests/infrastructure/argo-rollouts/Chart.yaml|- name: argo-rollouts *$|version: "?([0-9][^" ]*)'
#     'example-argo-workflows|examples|examples/argocd-apps/manifests/infrastructure/argo-workflow/Chart.yaml|- name: argo-workflows *$|version: "?([0-9][^" ]*)'
#     'example-argo-cd|examples|examples/argocd-apps/manifests/infrastructure/argocd/Chart.yaml|- name: argo-cd *$|version: "?([0-9][^" ]*)'
#     'example-argocd-image-updater|examples|examples/argocd-apps/manifests/infrastructure/argocd/Chart.yaml|- name: argocd-image-updater *$|version: "?([0-9][^" ]*)'
#     'lgtm-postgres|examples|examples/lgtm-testing/docker-compose.yaml examples/lgtm-testing/k8s/postgres.yaml|image: postgres:|postgres:([^" ]+)'
#     'lgtm-python|examples|examples/lgtm-testing/backend/Dockerfile|^FROM python:|python:([^ ]+)'
#     'lgtm-nginx|examples|examples/lgtm-testing/frontend/Dockerfile|^FROM nginx:|nginx:([^ ]+)'
#     'lgtm-backend-image|examples|examples/lgtm-testing/k8s/backend.yaml|lgtm-testing-backend:|lgtm-testing-backend:([^" ]+)'
#     'lgtm-frontend-image|examples|examples/lgtm-testing/k8s/frontend.yaml|lgtm-testing-frontend:|lgtm-testing-frontend:([^" ]+)'
#     # --- Repository tooling ---
#     'actions-checkout|repo-tooling|.github/workflows/*.yaml|uses: actions/checkout@|actions/checkout@([^ ]+)'
#     'chart-releaser-action|repo-tooling|.github/workflows/*.yaml|uses: helm/chart-releaser-action@|chart-releaser-action@([^ ]+)'
#     'actions-configure-pages|repo-tooling|.github/workflows/*.yaml|uses: actions/configure-pages@|configure-pages@([^ ]+)'
#     'actions-jekyll-build-pages|repo-tooling|.github/workflows/*.yaml|uses: actions/jekyll-build-pages@|jekyll-build-pages@([^ ]+)'
#     'actions-upload-pages-artifact|repo-tooling|.github/workflows/*.yaml|uses: actions/upload-pages-artifact@|upload-pages-artifact@([^ ]+)'
#     'actions-deploy-pages|repo-tooling|.github/workflows/*.yaml|uses: actions/deploy-pages@|deploy-pages@([^ ]+)'
#     'helm-docs|repo-tooling|.pre-commit-config.yaml|norwoodj/helm-docs *$|rev: +"?(v[^" ]+)'
#     'jekyll-theme-primer|repo-tooling|_config.yml|pages-themes/primer@|primer@([^ ]+)'
)

# Registry entry for a component name (empty + non-zero when unknown)
_ver_entry() {
    local entry
    for entry in "${VERSION_REGISTRY[@]}"; do
        [[ "${entry%%|*}" == "$1" ]] && { printf '%s' "$entry"; return 0; }
    done
    return 1
}

# Note (6th field) of a registry entry, empty when not set
_ver_note() {
    local -a f
    IFS='|' read -r -a f <<< "$1"
    printf '%s' "${f[5]:-}"
}

# Locate every pin of a registry entry: prints "relative/file|line|version", one per pin (sorted, unique)
_ver_locate() {
    local name group files anchor extract note g f n i ln v
    IFS='|' read -r name group files anchor extract note <<< "$1"
    [[ -n "$extract" ]] || extract='--version ([0-9v][^ ]*)'   # Helm charts
    local -a globs
    read -r -a globs <<< "$files"
    {
        for g in "${globs[@]}"; do
            for f in $(cd "$PROJECT_ROOT" && compgen -G "$g" || true); do
                while IFS=: read -r n _; do
                    # The version sits on the anchor line or one of the next 4 lines
                    i=0
                    # `|| [[ -n $ln ]]` keeps a last line that has no trailing newline
                    while IFS= read -r ln || [[ -n "$ln" ]]; do
                        v=$(sed -nE "s#.*${extract}.*#\1#p" <<< "$ln")
                        if [[ -n "$v" ]]; then
                            printf '%s|%s|%s\n' "$f" "$((n + i))" "$v"
                            break
                        fi
                        i=$((i + 1))
                    done < <(sed -n "${n},$((n + 4))p" "$PROJECT_ROOT/$f")
                done < <(grep -nE -- "$anchor" "$PROJECT_ROOT/$f" | grep -vE '^[0-9]+:[[:space:]]*#' || true)
            done
        done
    } | sort -t'|' -k1,1 -k2,2n -u
}

# Replace every literal occurrence of <old> with <new> on one line of a file.
# Keeps the file permissions and a missing trailing newline, so only the version line changes.
_ver_replace_line() {
    local file="$1" line="$2" old="$3" new="$4" tmp
    tmp=$(mktemp)
    awk -v n="$line" -v old="$old" -v new="$new" '
        NR == n {
            out = ""; s = $0
            while ((i = index(s, old)) > 0) { out = out substr(s, 1, i - 1) new; s = substr(s, i + length(old)) }
            $0 = out s
        }
        { print }' "$file" > "$tmp"
    if [[ -n "$(tail -c1 "$file")" ]]; then
        head -c -1 "$tmp" > "$file"   # original had no trailing newline: drop the one awk added
    else
        cat "$tmp" > "$file"
    fi
    rm -f "$tmp"
}

# Disclaimer shown before every bump
_ver_disclaimer() {
    printf "\n  ${BOLD}${YELLOW}DISCLAIMER — bumping versions is at your own risk${NC}\n"
    cat <<'EOF'
  Kubewekend only tests the versions pinned in this repository. A newer chart or tool can change its
  templates, values and defaults, drop support for your Kubernetes version, or stop matching the
  Kubewekend playbooks and value templates (ansible/templates/*-values.yaml.j2), and can break the
  setup, the utilities or an upgrade of a running cluster.
  Before bumping: read the release notes / upgrade guide, preview with --dry-run, and try it on a
  disposable cluster first. You decide whether to keep, adjust or revert the change.
EOF
    echo ""
}

# `versions list [filter]`: current pinned versions and where they live
versions_list() {
    local filter="${1:-}" entry name group current_group="" locs versions where mixed note count=0
    header "Kubewekend pinned versions"
    printf "  Source of truth: the files below; overview with notes in README.md → Versions\n"
    for entry in "${VERSION_REGISTRY[@]}"; do
        IFS='|' read -r name group _ <<< "$entry"
        if [[ -n "$filter" && "$name" != *"$filter"* && "$group" != "$filter" ]]; then continue; fi
        if [[ "$group" != "$current_group" ]]; then
            _sec "${group^^}"
            current_group="$group"
        fi
        locs=$(_ver_locate "$entry")
        count=$((count + 1))
        if [[ -z "$locs" ]]; then
            printf "  ${CYAN}%-24s${NC} %s\n" "$name" "${RED}not found (pattern needs an update)${NC}"
            continue
        fi
        versions=$(cut -d'|' -f3 <<< "$locs" | sort -u | paste -sd, - | sed 's/,/, /g')
        mixed=""
        [[ "$versions" == *,* ]] && mixed="  ${YELLOW}(mixed versions)${NC}"
        # Group locations per file: file:l1,l2
        where=$(awk -F'|' '{ sub(/^ansible\//, "", $1); a[$1] = (a[$1] ? a[$1] "," : "") $2; if (!($1 in o)) { o[$1] = ++k; f[k] = $1 } }
            END { for (j = 1; j <= k; j++) printf "%s%s:%s", (j > 1 ? "  " : ""), f[j], a[f[j]] }' <<< "$locs")
        printf "  ${CYAN}%-24s${NC} %s%s\n" "$name" "$(_cur "$versions")" "$mixed"
        printf "  %-24s %s\n" "" "$where"
        note=$(_ver_note "$entry")
        [[ -n "$note" ]] && printf "  %-24s ${YELLOW}note:${NC} %s\n" "" "$note"
    done
    [[ "$count" -gt 0 ]] || warn "No component matches '$filter' (groups: kubernetes, host-tools, networking, utilities, templates, charts, examples, repo-tooling)"
    echo ""
    info "Bump: ./scripts/setup.sh versions bump <component> <new-version> [--dry-run]"
    echo "  Not tracked (hand-written in README.md): kubectl (latest) / Helm (V3 latest) / Calico (latest) / Flux CLI (latest)"
}

# `versions bump <component> <new-version> [--dry-run] [--yes]`
versions_bump() {
    local name="" new="" dry_run=false assume_yes=false arg entry locs file line old changed=0
    for arg in "$@"; do
        case "$arg" in
            --dry-run) dry_run=true ;;
            --yes|-y)  assume_yes=true ;;
            -*)        warn "Unknown option: $arg" ;;
            *)         if [[ -z "$name" ]]; then name="$arg"; elif [[ -z "$new" ]]; then new="$arg"; fi ;;
        esac
    done
    if [[ -z "$name" || -z "$new" ]]; then
        error "Usage: ./scripts/setup.sh versions bump <component> <new-version> [--dry-run] [--yes]"
        echo "  Components: ./scripts/setup.sh versions list"
        return 1
    fi
    if ! entry=$(_ver_entry "$name"); then
        error "Unknown component: $name"
        echo "  Components: ./scripts/setup.sh versions list"
        return 1
    fi
    locs=$(_ver_locate "$entry")
    if [[ -z "$locs" ]]; then
        error "No pin found for '$name' (the registry pattern may need an update)"
        return 1
    fi

    header "Bump $name → $new"
    _ver_disclaimer
    local note
    note=$(_ver_note "$entry")
    if [[ -n "$note" ]]; then
        printf "  ${BOLD}Kubewekend configuration:${NC} %s\n\n" "$note"
    fi

    # Keep the `v` prefix style consistent with the current pins
    old=$(head -1 <<< "$locs" | cut -d'|' -f3)
    if [[ "${old:0:1}" == "v" && "${new:0:1}" != "v" ]] || [[ "${old:0:1}" != "v" && "${new:0:1}" == "v" ]]; then
        warn "Current pins look like '$old' but the new version is '$new' (check the 'v' prefix)"
    fi

    echo "  Changes:"
    while IFS='|' read -r file line old; do
        if [[ "$old" == "$new" ]]; then
            printf "    %-48s %s\n" "$file:$line" "already $new"
        else
            printf "    %-48s %s → %s\n" "$file:$line" "$old" "$(_cur "$new")"
            changed=$((changed + 1))
        fi
    done <<< "$locs"
    echo ""

    if [[ "$changed" -eq 0 ]]; then
        info "Nothing to change: $name is already $new"
        return 0
    fi
    if [[ "$dry_run" == true ]]; then
        info "[DRY RUN] $changed line(s) would change; no file was modified"
        return 0
    fi
    if [[ "$assume_yes" != true ]]; then
        confirm "Apply $changed change(s) for $name? You accept the risk described above" || { info "Aborted, nothing changed"; return 0; }
    fi

    while IFS='|' read -r file line old; do
        [[ "$old" == "$new" ]] || _ver_replace_line "$PROJECT_ROOT/$file" "$line" "$old" "$new"
    done <<< "$locs"
    info "Bumped $name to $new in $changed line(s)"
    echo "  Next: review with 'git diff', run './scripts/setup.sh versions sync' (or commit: the pre-commit hook runs it)"
    echo "        to refresh the README.md Versions table, and test on a disposable cluster"
}

# Title of a registry group in README.md
_ver_group_title() {
    case "$1" in
        kubernetes)   echo "Kubernetes distributions" ;;
        host-tools)   echo "Host tools" ;;
        networking)   echo "Cluster networking" ;;
        utilities)    echo "Utilities" ;;
        templates)    echo "Image pins in templates" ;;
        charts)       echo "Helm charts in this repository" ;;
        examples)     echo "Examples" ;;
        repo-tooling) echo "Repository tooling" ;;
        *)            echo "$1" ;;
    esac
}

# Markdown tables of every registry entry (the generated part of README.md → Versions)
_ver_markdown() {
    local entry name group current_group="" locs versions where
    for entry in "${VERSION_REGISTRY[@]}"; do
        IFS='|' read -r name group _ <<< "$entry"
        if [[ "$group" != "$current_group" ]]; then
            [[ -n "$current_group" ]] && echo ""
            echo "#### $(_ver_group_title "$group")"
            echo ""
            echo "| Component | Version | Where to update | Notes |"
            echo "| --------- | ------- | --------------- | ----- |"
            current_group="$group"
        fi
        locs=$(_ver_locate "$entry")
        if [[ -z "$locs" ]]; then
            echo "| \`$name\` | not found | pattern in \`VERSION_REGISTRY\` needs an update | |"
            continue
        fi
        versions=$(cut -d'|' -f3 <<< "$locs" | sort -u | sed 's/.*/`&`/' | paste -sd, - | sed 's/,/, /g')
        # file:l1,l2 per file, in a code span
        where=$(awk -F'|' '{ a[$1] = (a[$1] ? a[$1] "," : "") $2; if (!($1 in o)) { o[$1] = ++k; f[k] = $1 } }
            END { for (j = 1; j <= k; j++) printf "%s`%s:%s`", (j > 1 ? ", " : ""), f[j], a[f[j]] }' <<< "$locs")
        echo "| \`$name\` | $versions | $where | $(_ver_note "$entry") |"
    done
}

# Validate the registry against the files: every entry must be found and pinned to one version.
# Prints one line per problem; returns the number of problems.
_ver_validate() {
    local entry name locs versions problems=0
    for entry in "${VERSION_REGISTRY[@]}"; do
        name="${entry%%|*}"
        locs=$(_ver_locate "$entry")
        if [[ -z "$locs" ]]; then
            error "$name: no pin found (update its pattern in VERSION_REGISTRY or remove the entry)"
            problems=$((problems + 1))
            continue
        fi
        versions=$(cut -d'|' -f3 <<< "$locs" | sort -u)
        if [[ $(wc -l <<< "$versions") -gt 1 ]]; then
            error "$name: pinned to different versions:"
            awk -F'|' '{ printf "          %s:%s  %s\n", $1, $2, $3 }' <<< "$locs" >&2
            echo "        fix: ./scripts/setup.sh versions bump $name <version>" >&2
            problems=$((problems + 1))
        fi
    done
    return "$problems"
}

# Files that carry the generated Versions tables between the markers: README.md (required) and the
# documentation site page (optional, skipped when the file does not exist)
VERSION_SYNC_TARGETS=("README.md" "docs/reference/versions.md")

# `versions sync [--check]`: validate the pins and regenerate the Versions tables (between the markers) in
# every VERSION_SYNC_TARGETS file. Pre-commit friendly: rewrites a stale file (the hook then reports the
# modified file); with --check (CI) it only reports. Exits 1 on validation problems or, with --check, a stale file.
versions_sync() {
    local check=false begin="<!-- versions:begin -->" end="<!-- versions:end -->"
    local generated current tmp target file problems=0 rc=0
    [[ "${1:-}" == "--check" ]] && check=true
    if ! grep -qxF "$begin" "$PROJECT_ROOT/README.md" || ! grep -qxF "$end" "$PROJECT_ROOT/README.md"; then
        error "README.md is missing the '$begin' / '$end' markers around the generated Versions tables"
        return 1
    fi

    _ver_validate || problems=$?

    generated=$(_ver_markdown)
    # Exact block between the markers: blank lines around the tables keep the end marker out of the last
    # table (kramdown on the docs site otherwise renders that table as plain text). The trailing `x`
    # sentinel stops $(...) from stripping the final blank line.
    local block
    block=$(printf '\n%s\n\n' "$generated"; echo x); block=${block%x}
    for target in "${VERSION_SYNC_TARGETS[@]}"; do
        file="$PROJECT_ROOT/$target"
        [[ -f "$file" ]] || continue
        if ! grep -qxF "$begin" "$file" || ! grep -qxF "$end" "$file"; then
            error "$target is missing the '$begin' / '$end' markers around the generated Versions tables"
            rc=1
            continue
        fi
        current=$(awk -v b="$begin" -v e="$end" '$0 == e { f = 0 } f { print } $0 == b { f = 1 }' "$file"; echo x)
        current=${current%x}
        if [[ "$block" == "$current" ]]; then
            info "$target Versions table is up to date"
        elif [[ "$check" == true ]]; then
            error "$target Versions table is out of date: run ./scripts/setup.sh versions sync"
            rc=1
        else
            tmp=$(mktemp)
            printf '%s' "$block" > "$tmp"
            awk -v b="$begin" -v e="$end" -v gen="$tmp" '
                $0 == b { print; while ((getline line < gen) > 0) print line; skip = 1; next }
                $0 == e { skip = 0 }
                !skip { print }' "$file" > "$tmp.out"
            cat "$tmp.out" > "$file"
            rm -f "$tmp" "$tmp.out"
            info "Updated $target Versions table (review and stage it)"
        fi
    done

    if [[ "$problems" -gt 0 ]]; then
        error "$problems version problem(s) found"
        return 1
    fi
    return "$rc"
}

cmd_versions_help() {
    cat <<'EOF'
kubewekend versions - List and bump pinned versions of charts, tools and manifests

SUBCOMMANDS
  list [filter]                         Current pinned versions and their file:line locations
                                        filter: component name or group (kubernetes, host-tools,
                                        networking, utilities)
  bump <component> <version> [opts]     Replace the pinned version everywhere it is used
  sync [--check]                        Validate the pins (found, one version each) and regenerate the
                                        Versions tables in README.md and docs/reference/versions.md;
                                        --check only reports (CI).
                                        Runs as a pre-commit hook (.pre-commit-config.yaml)

OPTIONS (bump)
  --dry-run                             Show the changes without modifying files
  --yes, -y                             Skip the confirmation prompt

DISCLAIMER
  Bumping is at your own risk: Kubewekend only tests the versions pinned in this repository. A newer
  chart or tool can change templates, values or defaults and stop working with the Kubewekend
  playbooks and value templates. Read the release notes, use --dry-run, and test on a disposable
  cluster first.

EXAMPLES
  ./scripts/setup.sh versions list
  ./scripts/setup.sh versions list networking
  ./scripts/setup.sh versions bump cilium 1.20.6 --dry-run
  ./scripts/setup.sh versions bump k3s v1.35.8+k3s1
EOF
}

cmd_versions() {
    local sub="${1:-help}"; shift || true
    case "$sub" in
        list|ls) versions_list "$@" ;;
        bump)    versions_bump "$@" ;;
        sync)    versions_sync "$@" ;;
        *)       cmd_versions_help ;;
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

main "$@"
