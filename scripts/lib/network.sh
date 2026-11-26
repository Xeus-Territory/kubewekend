#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# Kubewekend CLI library: network command
# =============================================================================
# VirtualBox NAT network management.
# Sourced by scripts/setup.sh (never run it directly). Functions only: nothing here runs until main() calls it.
# PROJECT_ROOT, HOST_VARS_DIR and the other path variables come from setup.sh; colours and info/warn/error from core.sh.

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
        if vagrant status "$vm" 2>/dev/null | grep -q "running"; then
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
