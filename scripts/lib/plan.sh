#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# Kubewekend CLI library: plan command
# =============================================================================
# `plan <kind|k3s|rke2|utils>` prints what the next setup would build, from master.yaml and the inventory, and the exact
# commands to run in order. Read-only: nothing is installed, changed or contacted.
# Sourced by scripts/setup.sh (never run it directly). HOST_VARS_DIR and the colours come from setup.sh and core.sh;
# _yaml_get from yaml.sh, the registries from utilities.sh and options.sh, _inv_hosts from inventory.sh.

# ---------------------------------------------------------------------------
# COMMAND: plan
# ---------------------------------------------------------------------------
cmd_plan_help() {
    cat <<'EOF'
kubewekend plan - Show what the next setup would build, without running anything

SUBCOMMANDS
  kind                  The Kind cluster, the utilities you enabled, and the commands to run
  k3s                   The K3s cluster: settings, inventory nodes, utilities and commands
  rke2                  The RKE2 cluster: settings, inventory nodes, utilities and commands
  utils                 Only the utilities enabled in master.yaml and the tags to install

The plan is read from ansible/inventories/host_vars/master.yaml and the inventory. Nothing is installed, changed or
contacted: it is the "what will happen" view that goes with `config --list` (what is supported) and `doctor` (is this
machine ready).

EXAMPLES
  ./scripts/setup.sh plan kind
  ./scripts/setup.sh plan k3s
  ./scripts/setup.sh plan utils
EOF
}

cmd_plan() {
    local sub="${1:-help}"
    case "$sub" in
        kind|k3s|rke2) plan_cluster "$sub" ;;
        utils)         plan_utils_only ;;
        *)             cmd_plan_help ;;
    esac
}

# Value of a key under a cluster block of master.yaml. Usage: _plan_v <top> <dotted.path>
_plan_v() { _yaml_get "$HOST_VARS_DIR/master.yaml" "$1" "$2"; }

plan_cluster() {
    local distro="$1" top label
    top=$(_setup_top "$distro")
    case "$distro" in kind) label="Kind" ;; k3s) label="K3s" ;; rke2) label="RKE2" ;; esac
    header "Plan: $label (read-only: nothing is installed or changed)"
    printf "  Settings: ${BOLD}%s${NC} (%s)\n" "$HOST_VARS_DIR/master.yaml" "$top"
    [[ -f "$HOST_VARS_DIR/master.yaml" ]] || { warn "master.yaml not found: there is nothing to plan"; return 0; }
    if [[ "$distro" == "kind" ]]; then _plan_kind; else _plan_node_cluster "$distro" "$top"; fi
    _plan_warnings "$distro"
    _plan_utilities
    _plan_commands "$distro"
}

_plan_kind() {
    local t=kindCluster cp w
    cp=$(_plan_v $t numberOfNodes.controlPlane); w=$(_plan_v $t numberOfNodes.worker)
    _sec "KIND CLUSTER"
    _row "Node image"            "$(_cur "$(_plan_v $t image)")"
    _row "Nodes"                 "${cp:-?} control-plane, ${w:-0} worker"
    _row "Default CNI disabled"  "$(_cur "$(_plan_v $t networking.disableDefaultCNI)")"
    _row "CNI plugin setting"    "$(_cur "$(_plan_v $t networking.cni)")"
    _row "kube-proxy mode"       "$(_cur "$(_plan_v $t networking.kubeProxyMode)")"
    _row "Load balancer"         "$(_badge "$(_plan_v $t loadbalancer.enable)" "$(_plan_v $t loadbalancer.type)")"
    _row "Ingress"               "$(_badge "$(_plan_v $t ingress.enable)" "$(_plan_v $t ingress.class)")"
    _row "  Traefik dashboard"   "$(_badge "$(_plan_v $t ingress.traefik.dashboard.enable)" "$(_plan_v $t ingress.traefik.dashboard.host)")"
    _row "API Gateway"           "$(_badge "$(_plan_v $t apigateway.enable)" "$(_plan_v $t apigateway.class)")"
    _row "  Gateway API CRDs"    "$(_badge "$(_plan_v $t apigateway.crd.install)" "$(_plan_v $t apigateway.crd.version)")"
    _row "Host port forwarding"  "$(_badge "$(_plan_v $t networkForwarding.enable)") (ports 80 and 443)"
}

# K3s and RKE2 share most settings. Usage: _plan_node_cluster <k3s|rke2> <k3sCluster|rke2Cluster>
_plan_node_cluster() {
    local distro="$1" t="$2" lb_type
    lb_type=$(_plan_v "$t" loadBalancer.type)
    _sec "${distro^^} CLUSTER"
    _row "Version"            "$(_cur "$(_plan_v "$t" version)")"
    _row "CNI"                "$(_cur "$(_plan_v "$t" cni.type)")"
    _row "Load balancer"      "$(_badge "$(_plan_v "$t" loadBalancer.enable)" "$lb_type")"
    [[ "$lb_type" == "metallb" ]] && _row "  MetalLB IP pool" "$(_cur "$(_plan_v "$t" loadBalancer.ippool.cidr)")"
    _row "Ingress"            "$(_badge "$(_plan_v "$t" ingress.enable)" "$(_plan_v "$t" ingress.class)")"
    if [[ "$distro" == "k3s" ]]; then
        _row "  Traefik dashboard" "$(_badge "$(_plan_v "$t" ingress.traefik.dashboard.enable)" "$(_plan_v "$t" ingress.traefik.dashboard.host)")"
        _row "  Gateway API"       "$(_badge "$(_plan_v "$t" ingress.traefik.gateway.enable)")"
    fi
    _row "TLS SANs"           "$(_plan_list "$(_plan_v "$t" tlsSANs)")"
    _row "Node labels"        "$(_plan_list "$(_plan_v "$t" nodeLabels)")"
    _row "Node taints"        "$(_plan_list "$(_plan_v "$t" nodeTaints)")"
    _row "HA datastore"       "$(_cur "$(_plan_v "$t" highAvailability.dataStorage.type)") (only read by ha-setup)"
    _plan_nodes
}

# The inventory groups the playbooks target
_plan_nodes() {
    _sec "NODES (ansible/inventories/hosts)"
    if [[ ! -f "$HOSTS_FILE" ]]; then
        echo "  No inventory yet: ./scripts/setup.sh inventory generate  (or: inventory set-remote)"
        return 0
    fi
    local group
    for group in standalone-masters standalone-workers ha_master_init ha_master_join ha_worker; do
        _row "[$group]" "$(_plan_join "$(_inv_hosts "$group")")"
    done
}

# A list value from master.yaml: "none" when it is missing or an empty `[]`
_plan_list() { if [[ -z "$1" || "$1" == "[]" ]]; then echo "none"; else _cur "$1"; fi; }

# Lines of a string joined with ", " (or "none")
_plan_join() { if [[ -n "$1" ]]; then printf '%s\n' "$1" | paste -sd, - | sed 's/,/, /g'; else echo "none"; fi; }

_plan_warnings() {
    local distro="$1" msg found=false
    while IFS= read -r msg; do
        [[ -z "$msg" ]] && continue
        [[ "$found" == false ]] && { _sec "WARNINGS (see: ./scripts/setup.sh config validate)"; found=true; }
        warn "$msg"
    done < <(_archived_class_msgs "$distro"; _removed_key_msgs "$distro")
}

# Tags of the utilities enabled in master.yaml (space separated), set by _plan_utilities
PLAN_UTIL_TAGS=""

# Utilities enabled in master.yaml, and the tags to install them with
_plan_utilities() {
    local entry tag key desc on=() off=()
    _sec "UTILITIES"
    for entry in "${UTILITY_REGISTRY[@]}"; do
        tag=$(_util_field "$entry" 0); key=$(_util_field "$entry" 1); desc=$(_util_field "$entry" 2)
        if [[ "$(_util_value "$key" enable)" == "true" ]]; then
            on+=("$tag")
            printf "  ${CYAN}%-20s${NC} ${GREEN}ON${NC}   %s\n" "$tag" "$desc"
        else
            off+=("$tag")
        fi
    done
    [[ ${#on[@]} -gt 0 ]] || echo "  No utility is enabled (set utilities.<name>.enable: true in master.yaml)"
    [[ ${#off[@]} -gt 0 ]] && printf "  ${RED}OFF${NC}: %s\n" "$(printf '%s\n' "${off[@]}" | paste -sd, - | sed 's/,/, /g')"
    PLAN_UTIL_TAGS="${on[*]:-}"
}

_plan_commands() {
    local distro="$1" host
    _sec "COMMANDS, IN ORDER"
    echo "  1. ./scripts/setup.sh doctor"
    case "$distro" in
        kind)
            echo "  2. ./scripts/setup.sh kind setup"
            ;;
        k3s|rke2)
            local hosts
            hosts=$(_inv_hosts standalone-masters; _inv_hosts standalone-workers)
            if [[ -n "$hosts" ]]; then
                echo "  2. Standalone: master first, then each worker (one host per run)"
                for host in $hosts; do
                    echo "       ./scripts/setup.sh $distro setup --host $host"
                done
            elif [[ -f "$HOSTS_FILE" ]]; then
                echo "  2. Standalone: no hosts in [standalone-masters] or [standalone-workers]"
            else
                echo "  2. Standalone: master first, then each worker (one host per run)"
                echo "       ./scripts/setup.sh $distro setup --host <name>   (after: inventory generate)"
            fi
            echo "     High availability: ./scripts/setup.sh $distro ha-setup   (all nodes of the HA groups at once)"
            ;;
    esac
    if [[ -n "$PLAN_UTIL_TAGS" ]]; then
        echo "  3. ./scripts/setup.sh $distro utils $PLAN_UTIL_TAGS"
    else
        echo "  3. ./scripts/setup.sh $distro utils <tag>   (nothing is enabled yet)"
    fi
    echo ""
    info "Add --dry-run to any of them to see the ansible command first; --debug (first argument) traces a run."
}

plan_utils_only() {
    header "Plan: utilities (read-only)"
    printf "  Settings: ${BOLD}%s${NC} (utilities)\n" "$HOST_VARS_DIR/master.yaml"
    [[ -f "$HOST_VARS_DIR/master.yaml" ]] || { warn "master.yaml not found: there is nothing to plan"; return 0; }
    _plan_utilities
    echo ""
    if [[ -n "$PLAN_UTIL_TAGS" ]]; then
        info "Install: ./scripts/setup.sh <kind|k3s|rke2> utils $PLAN_UTIL_TAGS"
    fi
}
