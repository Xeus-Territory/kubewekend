#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# Kubewekend CLI library: config show
# =============================================================================
# The master.yaml and worker.yaml summary tables printed by `config show` and `config worker-show`.
# Sourced by scripts/setup.sh (never run it directly). Functions only: nothing here runs until main() calls it.
# PROJECT_ROOT, HOST_VARS_DIR and the other path variables come from setup.sh; colours and info/warn/error from core.sh.

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

    local k3_ha k3_ds k3_cni k3_lb k3_lb_pool k3_ing k3_ing_dash
    k3_ha=$(      echo "$k3s"    | _ysub "highAvailability" 2)
    k3_ds=$(      echo "$k3_ha"  | _ysub "dataStorage"      4)
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

    local rk_ha rk_ds rk_cni rk_lb rk_lb_pool rk_ing
    rk_ha=$(      echo "$rke2"    | _ysub "highAvailability" 2)
    rk_ds=$(      echo "$rk_ha"  | _ysub "dataStorage"      4)
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
