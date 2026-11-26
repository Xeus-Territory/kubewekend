#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# Kubewekend CLI library: Pinned versions table
# =============================================================================
# VERSION_REGISTRY: one entry per pinned component, and the files `versions sync` rewrites.
# Sourced by scripts/setup.sh (never run it directly). Functions only: nothing here runs until main() calls it.
# PROJECT_ROOT, HOST_VARS_DIR and the other path variables come from setup.sh; colours and info/warn/error from core.sh.

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

# Files that carry the generated Versions tables between the markers: README.md (required) and the
# documentation site page (optional, skipped when the file does not exist)
VERSION_SYNC_TARGETS=("README.md" "docs/reference/versions.md")
