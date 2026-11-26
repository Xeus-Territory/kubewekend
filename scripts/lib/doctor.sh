#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# Kubewekend CLI library: doctor command
# =============================================================================
# `doctor` checks this machine, .env, master.yaml and the inventory BEFORE you run a setup, and says what to fix.
# It is read-only and never contacts a cluster; `doctor --ping` additionally runs `ansible all -m ping`.
# Sourced by scripts/setup.sh (never run it directly). PROJECT_ROOT, HOST_VARS_DIR, HOSTS_FILE and the colours come
# from setup.sh and core.sh; the YAML readers from yaml.sh; _inv_hosts from inventory.sh.

# ---------------------------------------------------------------------------
# COMMAND: doctor
# ---------------------------------------------------------------------------
cmd_doctor_help() {
    cat <<'EOF'
kubewekend doctor - Check this machine, the configuration and the inventory before a setup

USAGE
  ./scripts/setup.sh doctor [--ping]

OPTIONS
  --ping        Also run `ansible all -m ping` to test that every inventory host is reachable

CHECKS
  tools          ansible-playbook and ssh are required; the rest is optional and only reported
  environment    .env and the SSH key that `vagrant up` needs
  configuration  master.yaml / worker.yaml: tabs, column-0 comments, keys no playbook reads, archived controllers
  inventory      the groups the playbooks need (standalone, or the HA groups) and the SSH key it names
  host           ports Kind forwarding would use, Docker, and the current kubectl context

Each line is [ OK ], [ -- ] (optional, nothing to do), [WARN] or [FAIL]. The exit code is 1 when anything fails.
Nothing is changed and no cluster is contacted. For the settings themselves see: ./scripts/setup.sh config validate

EXAMPLES
  ./scripts/setup.sh doctor
  ./scripts/setup.sh doctor --ping
EOF
}

cmd_doctor() {
    local arg ping=false
    for arg in "$@"; do
        case "$arg" in
            help|--help|-h) cmd_doctor_help; return 0 ;;
            --ping)         ping=true ;;
            *)              error "Unknown option: $arg"; cmd_doctor_help; return 1 ;;
        esac
    done
    doctor_run "$ping"
}

# Result counters and the four line styles
DOCTOR_OK=0
DOCTOR_WARN=0
DOCTOR_FAIL=0
_doc_ok()   { DOCTOR_OK=$((DOCTOR_OK + 1));     printf "  ${GREEN}[ OK ]${NC} %s\n" "$*"; }
_doc_skip() {                                    printf "  [ -- ] %s\n" "$*"; }
_doc_warn() { DOCTOR_WARN=$((DOCTOR_WARN + 1)); printf "  ${YELLOW}[WARN]${NC} %s\n" "$*"; }
_doc_fail() { DOCTOR_FAIL=$((DOCTOR_FAIL + 1)); printf "  ${RED}[FAIL]${NC} %s\n" "$*"; }

doctor_run() {
    local ping="$1"
    DOCTOR_OK=0; DOCTOR_WARN=0; DOCTOR_FAIL=0
    header "Kubewekend doctor ($PROJECT_ROOT)"
    _doctor_tools
    _doctor_environment
    _doctor_configuration
    _doctor_inventory "$ping"
    _doctor_host
    echo ""
    if [[ $DOCTOR_FAIL -gt 0 ]]; then
        error "$DOCTOR_FAIL failure(s), $DOCTOR_WARN warning(s), $DOCTOR_OK ok: fix the [FAIL] lines first"
        return 1
    fi
    info "No failures ($DOCTOR_WARN warning(s), $DOCTOR_OK ok)"
}

_doctor_tools() {
    _sec "TOOLS ON THIS MACHINE"
    local spec tool level why path
    local -a specs=(
        "ansible-playbook|required|every setup, ha-setup, destroy and utils command"
        "ssh|required|reaching the nodes"
        "ansible|optional|inventory ping"
        "vagrant|optional|the vagrant command (VM nodes)"
        "VBoxManage|optional|the network command and VirtualBox VMs"
        "kubectl|optional|using the cluster from this machine"
        "helm|optional|using the cluster from this machine (the playbooks install their own copy on the nodes)"
        "docker|optional|looking at Kind clusters on this machine"
        "jq|optional|reading JSON output"
        "yq|optional|reading YAML output"
    )
    for spec in "${specs[@]}"; do
        IFS='|' read -r tool level why <<< "$spec"
        path=$(command -v "$tool" 2>/dev/null || true)
        if [[ -n "$path" ]]; then
            _doc_ok "$tool  $path"
        elif [[ "$level" == "required" ]]; then
            _doc_fail "$tool is not installed (needed for: $why). Install the pinned Ansible with: pip install -r requirements.txt"
        else
            _doc_skip "$tool not installed (optional: $why)"
        fi
    done
    _doctor_ansible_version
}

# Installed ansible-core vs the version pinned in requirements.txt
_doctor_ansible_version() {
    command -v ansible-playbook >/dev/null 2>&1 || return 0
    local have want
    have=$(ansible-playbook --version 2>/dev/null | sed -n '1s/.*core \([0-9][0-9.]*\).*/\1/p' || true)
    want=$(sed -n 's/^ansible-core==\([0-9][0-9.]*\).*/\1/p' "$PROJECT_ROOT/requirements.txt" 2>/dev/null | head -1 || true)
    if [[ -z "$have" || -z "$want" ]]; then
        return 0
    elif [[ "$have" == "$want" ]]; then
        _doc_ok "ansible-core $have matches requirements.txt"
    else
        _doc_warn "ansible-core $have is installed, requirements.txt pins $want (pip install -r requirements.txt)"
    fi
}

_doctor_environment() {
    _sec "ENVIRONMENT"
    if [[ -f "$ENV_FILE" ]]; then
        _doc_ok ".env found"
    else
        _doc_warn ".env not found (only the vagrant command needs it): ./scripts/setup.sh env init"
    fi
    load_env
    local key="${SSH_KEY:-vmbox}"
    if ! command -v vagrant >/dev/null 2>&1; then
        _doc_skip "SSH key check skipped: vagrant is not installed (the inventory check below tests the key it names)"
    elif [[ -f "$HOME/.ssh/$key" && -f "$HOME/.ssh/$key.pub" ]]; then
        _doc_ok "SSH key ~/.ssh/$key and ~/.ssh/$key.pub found"
    else
        _doc_warn "SSH key ~/.ssh/$key (and .pub) not found: vagrant up needs it (ssh-keygen -t rsa -b 2048 -C \"vmbox\" -f ~/.ssh/$key)"
    fi
}

_doctor_configuration() {
    _sec "CONFIGURATION (ansible/inventories/host_vars)"
    local name path line out
    for name in master.yaml worker.yaml; do
        path="$HOST_VARS_DIR/$name"
        if [[ ! -f "$path" ]]; then
            if [[ "$name" == "master.yaml" ]]; then _doc_fail "$name not found at $path"; else _doc_warn "$name not found (K3s and RKE2 workers read it)"; fi
            continue
        fi
        _doc_ok "$name found"
        while IFS= read -r line; do
            [[ -n "$line" ]] && _doc_fail "$name:$line"
        done < <(_doctor_yaml_problems "$path")
    done
    if [[ -f "$HOST_VARS_DIR/master.yaml" ]]; then
        # config validate prints one [ERROR] / [WARN] line per finding (plus a summary line); show them as doctor lines
        local rc=0 findings=0
        out=$(config_validate 2>&1) || rc=$?
        while IFS= read -r line; do
            case "$line" in
                *"error(s)"*|*"(--strict)"*) ;;   # the summary line, not a finding
                *"[ERROR]"*) _doc_fail "master.yaml: ${line#*\] }"; findings=$((findings + 1)) ;;
                *"[WARN]"*)  _doc_warn "master.yaml: ${line#*\] }"; findings=$((findings + 1)) ;;
            esac
        done <<< "$out"
        if [[ $rc -eq 0 && $findings -eq 0 ]]; then
            _doc_ok "master.yaml passes config validate"
        fi
    fi
}

# Problems the YAML readers (and Ansible) trip over, as "line: message", one per line
_doctor_yaml_problems() {
    local file="$1"
    awk '
        /\t/ { printf "%d: contains a tab character (YAML only allows spaces)\n", NR }
        /^[A-Za-z][A-Za-z0-9]*:[[:space:]]*$/ { blk = 1; next }
        blk && /^#/ { printf "%d: comment in column 0 inside a block: setup.sh stops reading the block here; indent it by two spaces\n", NR }
        blk && /^[^# \t]/ { printf "%d: unexpected column-0 line inside a block\n", NR }
    ' "$file"
}

_doctor_inventory() {
    local ping="$1"
    _sec "INVENTORY ($HOSTS_FILE)"
    if [[ ! -f "$HOSTS_FILE" ]]; then
        _doc_warn "no inventory yet: ./scripts/setup.sh inventory generate (Vagrant VMs) or inventory set-remote (a VPS)"
        return 0
    fi
    local masters workers init join ha_workers n_masters n_workers n_init n_join n_haw
    masters=$(_inv_hosts standalone-masters); workers=$(_inv_hosts standalone-workers)
    init=$(_inv_hosts ha_master_init); join=$(_inv_hosts ha_master_join); ha_workers=$(_inv_hosts ha_worker)
    n_masters=$(_doctor_count "$masters"); n_workers=$(_doctor_count "$workers")
    n_init=$(_doctor_count "$init"); n_join=$(_doctor_count "$join"); n_haw=$(_doctor_count "$ha_workers")

    if [[ $n_masters -eq 0 && $n_init -eq 0 ]]; then
        _doc_fail "no master: [standalone-masters] and [ha_master_init] are both empty"
    fi
    if [[ $n_masters -eq 1 ]]; then
        _doc_ok "standalone: 1 master ($masters), $n_workers worker(s): kind setup, k3s setup, rke2 setup"
    elif [[ $n_masters -gt 1 ]]; then
        _doc_warn "standalone: $n_masters hosts in [standalone-masters]; a standalone cluster has exactly one master"
    else
        _doc_skip "standalone group empty (needed for kind setup, k3s setup and rke2 setup)"
    fi
    if [[ $((n_init + n_join + n_haw)) -eq 0 ]]; then
        _doc_skip "HA groups empty (only k3s ha-setup and rke2 ha-setup need them)"
    else
        _doctor_ha "$n_init" "$n_join" "$n_haw"
    fi
    _doctor_inventory_key
    if [[ "$ping" == true ]]; then
        _doctor_ping
    fi
}

# Number of non-empty lines in a string
_doctor_count() { [[ -n "$1" ]] && printf '%s\n' "$1" | grep -c . || echo 0; }

# HA group sizes against what the HA playbooks and etcd need
_doctor_ha() {
    local n_init="$1" n_join="$2" n_haw="$3" total k3_ds rk_ds
    total=$((n_init + n_join))
    k3_ds=$(_yaml_get "$HOST_VARS_DIR/master.yaml" k3sCluster highAvailability.dataStorage.type)
    rk_ds=$(_yaml_get "$HOST_VARS_DIR/master.yaml" rke2Cluster highAvailability.dataStorage.type)
    if [[ $n_init -ne 1 ]]; then
        _doc_fail "HA: [ha_master_init] has $n_init host(s); it needs exactly 1 (it bootstraps the cluster)"
    elif [[ $n_join -lt 1 ]]; then
        _doc_warn "HA: [ha_master_join] is empty, so there is only 1 control-plane node (no high availability)"
    else
        _doc_ok "HA: $n_init init + $n_join join = $total control-plane node(s), $n_haw worker(s)"
    fi
    if [[ $total -gt 1 && $((total % 2)) -eq 0 && ( "${k3_ds:-etcd}" == "etcd" || "${rk_ds:-etcd}" == "etcd" ) ]]; then
        _doc_warn "HA: $total control-plane nodes with embedded etcd: use an odd number (3, 5) for quorum"
    fi
}

# The SSH key named in [all:vars] must exist
_doctor_inventory_key() {
    local key
    key=$(sed -n 's/^ansible_ssh_private_key_file=//p' "$HOSTS_FILE" | head -1 | tr -d "\"'")
    [[ -n "$key" ]] || return 0
    key="${key/#\~/$HOME}"
    if [[ -f "$key" ]]; then
        _doc_ok "inventory SSH key $key found"
    else
        _doc_warn "inventory SSH key $key not found: ssh to the nodes will fail"
    fi
}

_doctor_ping() {
    if ! command -v ansible >/dev/null 2>&1; then
        _doc_skip "--ping skipped: ansible is not installed"
        return 0
    fi
    local out
    if out=$(timeout 90 ansible -i "$HOSTS_FILE" all -m ping -o 2>&1); then
        _doc_ok "ansible ping: every host answered ($(grep -c SUCCESS <<< "$out") host(s))"
    else
        _doc_fail "ansible ping failed: $(tail -n 3 <<< "$out" | tr '\n' ' ')"
    fi
}

_doctor_host() {
    _sec "THIS MACHINE (only matters when Kind runs here)"
    local file="$HOST_VARS_DIR/master.yaml" port
    if [[ "$(_yaml_get "$file" kindCluster networkForwarding.enable)" == "true" ]]; then
        for port in 80 443; do
            if _doctor_port_in_use "$port"; then
                _doc_warn "port $port is already in use: kindCluster.networkForwarding would clash with it"
            else
                _doc_ok "port $port is free for kindCluster.networkForwarding"
            fi
        done
    else
        _doc_skip "kindCluster.networkForwarding is off: no port check needed"
    fi
    if command -v docker >/dev/null 2>&1; then
        if timeout 10 docker info >/dev/null 2>&1; then
            _doc_ok "Docker daemon is reachable"
        else
            _doc_warn "docker is installed but its daemon is not reachable (is it running, are you in the docker group?)"
        fi
    fi
    if command -v kubectl >/dev/null 2>&1; then
        _doc_skip "kubectl context: $(kubectl config current-context 2>/dev/null || echo "none") (doctor never contacts a cluster)"
    fi
}

# True when something listens on the TCP port (needs `ss`; reports "not in use" when it is missing)
_doctor_port_in_use() {
    command -v ss >/dev/null 2>&1 || return 1
    ss -ltn 2>/dev/null | awk -v p=":$1\$" '$4 ~ p { found = 1 } END { exit !found }'
}
