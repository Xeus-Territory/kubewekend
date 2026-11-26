#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# Kubewekend CLI library: Utility tags
# =============================================================================
# UTILITY_REGISTRY (one entry per tag of k8s-utilities-playbook.yaml) and `utils --list`.
# Sourced by scripts/setup.sh (never run it directly). Functions only: nothing here runs until main() calls it.
# PROJECT_ROOT, HOST_VARS_DIR and the other path variables come from setup.sh; colours and info/warn/error from core.sh.

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

# Read `utilities.<block>.<dotted.path>` from master.yaml
_util_value() { _yaml_get "$HOST_VARS_DIR/master.yaml" "utilities" "$1.$2"; }

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
