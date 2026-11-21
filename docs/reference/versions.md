---
title: Versions
description: "Pinned versions of every chart, tool and image Kubewekend installs, with the file and line to change each one."
parent: Reference
nav_order: 3
---

# Pinned versions
{: .no_toc }

Pinned versions of the tools, charts and images Kubewekend installs, and the exact file and line to change them.
{: .fs-5 .fw-300 }

1. TOC
{:toc}

The tables between the `versions:begin` / `versions:end` markers are **generated** from `VERSION_REGISTRY` in `scripts/setup.sh` by `./scripts/setup.sh versions sync` (also a pre-commit hook), here and in the root README: do not edit them by hand. The **Notes** column shows the essential configuration Kubewekend applies, so you do not need to read the playbooks.

```bash
# current pins and their file:line locations
./scripts/setup.sh versions list
# change a pin everywhere it is used
./scripts/setup.sh versions bump cilium 1.20.6 --dry-run
# validate pins + regenerate these tables
./scripts/setup.sh versions sync
```

> [!WARNING]
>
> Bumping is at your own risk: Kubewekend only tests the versions pinned below. A newer chart or tool can change its templates, values or defaults and stop working with the Kubewekend playbooks. Read the release notes and test on a disposable cluster first.

<!-- versions:begin -->

#### Kubernetes distributions

| Component | Version | Where to update | Notes |
| --------- | ------- | --------------- | ----- |
| `kind-node` | `v1.36.4` | `ansible/inventories/host_vars/master.yaml:21` |  |
| `k3s` | `v1.36.5+k3s1` | `ansible/inventories/host_vars/master.yaml:78`, `ansible/inventories/host_vars/worker.yaml:11` |  |
| `rke2` | `v1.36.5+rke2r1` | `ansible/inventories/host_vars/master.yaml:182`, `ansible/inventories/host_vars/worker.yaml:32` |  |
| `gateway-api-crd` | `v1.6.3` | `ansible/inventories/host_vars/master.yaml:51,163` | Standard channel CRDs applied before the Traefik Gateway API provider: Kind `apigateway.crd`, K3s `ingress.traefik.gateway.crd` (when `install: true`); keep both on the same version |

#### Host tools

| Component | Version | Where to update | Notes |
| --------- | ------- | --------------- | ----- |
| `ansible` | `12.0.0` | `requirements.txt:1` |  |
| `ansible-core` | `2.19.2` | `requirements.txt:2` |  |
| `kind-cli` | `v0.33.0` | `ansible/kind-playbook.yaml:21` |  |
| `vault-cli` | `1.21.4` | `ansible/k3s-ha-playbook.yaml:73`, `ansible/k3s-playbook.yaml:42`, `ansible/kind-playbook.yaml:49`, `ansible/rke2-ha-playbook.yaml:74`, `ansible/rke2-playbook.yaml:42` |  |
| `openbao-cli` | `2.7.0` | `ansible/k3s-ha-playbook.yaml:79`, `ansible/k3s-playbook.yaml:48`, `ansible/kind-playbook.yaml:55`, `ansible/rke2-ha-playbook.yaml:80`, `ansible/rke2-playbook.yaml:48` |  |
| `weave-gitops-cli` | `v0.38.0` | `ansible/k8s-utilities-playbook.yaml:748` |  |

#### Cluster networking

| Component | Version | Where to update | Notes |
| --------- | ------- | --------------- | ----- |
| `cloud-provider-kind` | `latest` | `ansible/kind-playbook.yaml:249` | Runs as a Docker container on the `kind` network, not inside the cluster |
| `metallb` | `0.15.3` | `ansible/k3s-ha-playbook.yaml:220`, `ansible/k3s-playbook.yaml:198`, `ansible/kind-playbook.yaml:269`, `ansible/rke2-ha-playbook.yaml:309`, `ansible/rke2-playbook.yaml:279` | L2 mode; the IP pool comes from `<cluster>.loadBalancer.ippool.cidr` (Kind: `kindCluster.loadbalancer.ippool.cidr`) |
| `cni-plugins` | `v1.7.1` | `ansible/kind-playbook.yaml:167` | Required for Kind run Flannel CNI; not needed for K3s or RKE2 |
| `flannel` | `v0.28.0` | `ansible/kind-playbook.yaml:206` |  |
| `cilium` | `1.20.5` | `ansible/k3s-ha-playbook.yaml:450`, `ansible/k3s-playbook.yaml:251`, `ansible/kind-playbook.yaml:222,306` | CNI only (Hubble relay + UI, `ipam.mode=cluster-pool`, 1 operator replica) when `cni: cilium` (Kind needs `disableDefaultCNI: true`); Kind ingress / Gateway API with Cilium are archived |
| `traefik` | `42.0.0` | `ansible/k3s-ha-playbook.yaml:474,497,529`, `ansible/k3s-playbook.yaml:276,299,331`, `ansible/kind-playbook.yaml:335,357,465` | Only ingress / Gateway API controller for Kind, K3s and RKE2 (NGINX, Kong, Cilium and RKE2 ingress-nginx archived). Installed in steps: ingress, optional dashboard, optional Gateway API provider (Kind: `ingress.traefik.*`, `apigateway.class: traefik`; K3s: `ingress.traefik.dashboard.enable`, `ingress.traefik.gateway.enable`); the base install resets the dashboard and the dashboard step enables it |

#### Utilities

| Component | Version | Where to update | Notes |
| --------- | ------- | --------------- | ----- |
| `cert-manager` | `v1.19.2` | `ansible/k8s-utilities-playbook.yaml:78` | CRDs installed by the chart (`crds.enabled=true`); optional self-signed CA issuer via `utilities.certmanager.selfSignedIssuer` |
| `kubernetes-dashboard` | `7.14.0` | `ansible/k8s-utilities-playbook.yaml:169` |  |
| `headlamp` | `0.39.0` | `ansible/k8s-utilities-playbook.yaml:188` |  |
| `rancher` | `2.13.1` | `ansible/k8s-utilities-playbook.yaml:239` |  |
| `longhorn` | `1.11.1` | `ansible/k8s-utilities-playbook.yaml:319` | UI with 1 replica; default volume replica count from `utilities.storage.longhorn.replicaStorage`; iSCSI / NFS node setup from `utilities.storage.longhorn.setup`; namespace `longhorn-system` |
| `local-path-provisioner` | `v0.0.37` | `ansible/k8s-utilities-playbook.yaml:337` | Manifest applied when `utilities.storage.type: local-path` (StorageClass `local-path`) |
| `vault` | `0.32.0` | `ansible/k8s-utilities-playbook.yaml:380,396,417` | Namespace `vault`; ingress at `utilities.secretManagement.host` (`ingressClass`); `config.mode` dev (in-memory, root token) or standalone (needs a StorageClass); agent injector with `config.injector` |
| `openbao` | `0.30.1` | `ansible/k8s-utilities-playbook.yaml:438,455,476` | Namespace `openbao`; ingress at `utilities.secretManagement.host`; `config.mode` dev or standalone (needs a StorageClass); recent charts need Kubernetes >= 1.30 |
| `reflector` | `9.1.45` | `ansible/k8s-utilities-playbook.yaml:613` |  |
| `reloader` | `2.2.7` | `ansible/k8s-utilities-playbook.yaml:629` |  |
| `external-secrets` | `1.2.1` | `ansible/k8s-utilities-playbook.yaml:645` |  |
| `argo-cd` | `9.1.3` | `ansible/k8s-utilities-playbook.yaml:669,706` | Ingress at `utilities.gitops.argocd.host` with `server.insecure=true` (TLS ends at the ingress); bundled Dex disabled |
| `argocd-image-updater` | `1.0.1` | `ansible/k8s-utilities-playbook.yaml:692` |  |
| `argocd-extension-metrics` | `v1.0.3` | `ansible/k8s-utilities-playbook.yaml:711` |  |
| `argocd-rollout-extension` | `v0.3.7` | `ansible/k8s-utilities-playbook.yaml:716` |  |
| `flux` | `v2.7.5` | `ansible/k8s-utilities-playbook.yaml:733` |  |
| `weave-gitops` | `4.0.36` | `ansible/k8s-utilities-playbook.yaml:753` |  |
| `kargo` | `1.8.6` | `ansible/k8s-utilities-playbook.yaml:783` |  |
| `gatekeeper` | `3.22.0` | `ansible/k8s-utilities-playbook.yaml:819` |  |
| `kyverno` | `3.7.1` | `ansible/k8s-utilities-playbook.yaml:838` |  |
| `dex` | `0.24.0` | `ansible/k8s-utilities-playbook.yaml:855` |  |
| `kube-prometheus-stack` | `82.16.0` | `ansible/k8s-utilities-playbook.yaml:895` | Values from `ansible/templates/kube-prometheus-stack-values.yaml.j2`, which also pins Prometheus / Alertmanager / Thanos images (see templates) |
| `grafana-operator` | `5.22.2` | `ansible/k8s-utilities-playbook.yaml:912` |  |
| `alloy` | `1.7.0` | `ansible/k8s-utilities-playbook.yaml:937` | Values from `ansible/templates/alloy-values.yaml.j2` |
| `loki` | `9.5.1` | `ansible/k8s-utilities-playbook.yaml:963` | Values from `ansible/templates/loki-values.yaml.j2` |
| `tempo` | `1.26.7` | `ansible/k8s-utilities-playbook.yaml:989` | Values from `ansible/templates/tempo-values.yaml.j2` |
| `pyroscope` | `1.19.2` | `ansible/k8s-utilities-playbook.yaml:1015` | Values from `ansible/templates/pyroscope-values.yaml.j2` |
| `istio` | `1.32.0` | `ansible/k8s-utilities-playbook.yaml:1037,1040` | Installs `base` + `istiod` only (sidecar mode); `serviceMesh.dataplane.mode: ambient` is not supported yet |

<!-- versions:end -->

## Not tracked by `versions` (update by hand)

| Component | Version | Where to update |
| --------- | ------- | --------------- |
| kubectl | unpinned (`stable.txt`) | `install_common` in `ansible/kind-playbook.yaml`, `k3s-playbook.yaml`, `k3s-ha-playbook.yaml`, `rke2-playbook.yaml`, `rke2-ha-playbook.yaml` |
| Helm | unpinned (`get-helm-3`, latest v3) | `install_common` in the same playbooks |
| Calico (manifest) | unpinned (`docs.projectcalico.org/manifests/calico.yaml`, latest) | `ansible/kind-playbook.yaml`, `k3s-playbook.yaml`, `k3s-ha-playbook.yaml` |
| Flux CLI | unpinned (`fluxcd.io/install.sh`, latest) | `ansible/k8s-utilities-playbook.yaml` (`gitops` tag) |

**Unpinned** means the latest release is installed at setup time. K3s and RKE2 also bundle their own CNI, ingress controller and ServiceLB, whose versions follow `k3sCluster.version` / `rke2Cluster.version`.
