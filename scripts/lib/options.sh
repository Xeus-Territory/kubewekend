#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# Kubewekend CLI library: Setup options
# =============================================================================
# Per-distribution option registries, archived ingress classes and master.yaml keys that no playbook reads.
# Sourced by scripts/setup.sh (never run it directly). Functions only: nothing here runs until main() calls it.
# PROJECT_ROOT, HOST_VARS_DIR and the other path variables come from setup.sh; colours and info/warn/error from core.sh.

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
# shellcheck disable=SC2034  # read through a nameref in _setup_entries
SETUP_REGISTRY_KIND=(
    "numberOfNodes|Node count (Kind always needs one control-plane)|controlPlane, worker||numberOfNodes.controlPlane,numberOfNodes.worker"
    "image|Node image, sets the Kubernetes version|kindest/node:<version>||image"
    "networking|API server, subnets, CNI and kube-proxy|apiServer; podSubnet; serviceSubnet; disableDefaultCNI (kindnet); cni: calico, flannel, cilium; kubeProxyMode: iptables, nftables, ipvs, none||networking.disableDefaultCNI,networking.cni,networking.kubeProxyMode,networking.podSubnet,networking.serviceSubnet"
    "loadbalancer|Service type LoadBalancer|type: cloud-provider-kind, metallb, cilium-ipam-lb (needs cni: cilium)||loadbalancer.enable,loadbalancer.type"
    "ingress|Ingress controller (Traefik only)|class: traefik; traefik.ports (web, websecure); traefik.allowCrossNamespace; traefik.dashboard (enable, host)|class: nginx, kong, cilium (archived, see NOTE above)|ingress.enable,ingress.class,ingress.traefik.dashboard.enable"
    "apigateway|Gateway API controller (Traefik only)|class: traefik; crd (install, version)|class: kong, cilium (archived, see NOTE above)|apigateway.enable,apigateway.class,apigateway.crd.install"
    "networkForwarding|Forward host ports 80/443 to the cluster (socat services)|enable||networkForwarding.enable"
)
# shellcheck disable=SC2034  # read through a nameref in _setup_entries
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
# shellcheck disable=SC2034  # read through a nameref in _setup_entries
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

# Messages (one per line) for archived ingress / Gateway API classes that master.yaml selects (see the archive NOTE
# above SETUP_REGISTRY_KIND): the playbook would not install that controller, or not the way you expect.
# Usage: _archived_class_msgs <kind|rke2>
_archived_class_msgs() {
    local file="$HOST_VARS_DIR/master.yaml" top enabled class
    case "$1" in
        kind)
            top="kindCluster"
            enabled=$(_yaml_get "$file" "$top" ingress.enable); class=$(_yaml_get "$file" "$top" ingress.class)
            if [[ "$enabled" == "true" && " $KIND_ARCHIVED_INGRESS_CLASSES " == *" $class "* ]]; then
                echo "$top.ingress.class: $class is archived, so no ingress controller will be installed (supported: traefik)"
            fi
            enabled=$(_yaml_get "$file" "$top" apigateway.enable); class=$(_yaml_get "$file" "$top" apigateway.class)
            if [[ "$enabled" == "true" && " $KIND_ARCHIVED_GATEWAY_CLASSES " == *" $class "* ]]; then
                echo "$top.apigateway.class: $class is archived, so no Gateway API controller will be installed (supported: traefik)"
            fi
            ;;
        rke2)
            top="rke2Cluster"
            enabled=$(_yaml_get "$file" "$top" ingress.enable); class=$(_yaml_get "$file" "$top" ingress.class)
            if [[ "$enabled" == "true" && " $RKE2_ARCHIVED_INGRESS_CLASSES " == *" $class "* ]]; then
                echo "$top.ingress.class: $class is archived and no longer supported (supported: traefik)"
            fi
            ;;
    esac
    return 0
}

# Warn (never fail) before a setup run. Usage: _check_archived_classes <kind|rke2>
_check_archived_classes() {
    local msg
    while IFS= read -r msg; do
        [[ -n "$msg" ]] && warn "$msg"
    done < <(_archived_class_msgs "$1")
    return 0
}

# master.yaml keys that no playbook reads (they were documented once, or never implemented). `config validate`
# fails on them and the setup commands warn about them, so a stale setting never looks like it does something.
#   top-level key | dotted path under it | why it is ignored
REMOVED_KEYS=(
    "k3sCluster|highAvailability.enable|HA is decided by the inventory groups (ha_master_init, ha_master_join, ha_worker), not by a master.yaml switch"
    "k3sCluster|highAvailability.replicas|the control-plane count is the number of hosts in ha_master_init and ha_master_join"
    "rke2Cluster|highAvailability.enable|HA is decided by the inventory groups (ha_master_init, ha_master_join, ha_worker), not by a master.yaml switch"
    "rke2Cluster|highAvailability.replicas|the control-plane count is the number of hosts in ha_master_init and ha_master_join"
)

# Messages (one per line) for removed keys that a cluster block of master.yaml still sets. Usage: _removed_key_msgs <k3s|rke2|all>
_removed_key_msgs() {
    local file="$HOST_VARS_DIR/master.yaml" entry top path why
    for entry in "${REMOVED_KEYS[@]}"; do
        IFS='|' read -r top path why <<< "$entry"
        [[ "$1" == "all" || "$top" == "$(_setup_top "$1")" ]] || continue
        if _yaml_has "$file" "$top" "$path"; then
            echo "$top.$path is ignored: $why"
        fi
    done
    return 0
}

# Warn (never fail) before a setup run. Usage: _check_removed_keys <k3s|rke2>
_check_removed_keys() {
    local msg
    while IFS= read -r msg; do
        [[ -n "$msg" ]] && warn "$msg"
    done < <(_removed_key_msgs "$1")
    return 0
}
