---
title: Utilities
description: "Install Kubernetes utilities with one command: cert-manager, dashboards, Longhorn, Vault or OpenBao, Argo CD or Flux, Kyverno, LGTM monitoring and Istio."
nav_order: 3
has_children: true
permalink: /docs/utilities/
---

# Kubernetes utilities
{: .no_toc }

Add platform tools to any Kubewekend cluster with one command. Each utility is an Ansible tag in [`k8s-utilities-playbook.yaml`]({{ site.repo_url }}/blob/main/ansible/k8s-utilities-playbook.yaml), configured by a block under `utilities:` in [`master.yaml`]({{ site.repo_url }}/blob/main/ansible/inventories/host_vars/master.yaml).
{: .fs-5 .fw-300 }

1. TOC
{:toc}

## How it works

```bash
# every tag, its options, what is in development, current values
./scripts/setup.sh <kind|k3s|rke2> utils --list
# install one or more utilities
./scripts/setup.sh <kind|k3s|rke2> utils <tag> [<tag> ...]
./scripts/setup.sh k3s utils storage secret_management --dry-run
```

- A tag only installs when its block is enabled: `utilities.<key>.enable: true`. The CLI warns about disabled tags and rejects unknown ones.
- Options are read from the same block, for example `utilities.storage.type: longhorn`.
- `utils --list` and `config show` print the current values, so you can check the configuration before running anything.

## Available utilities

| Tag | Installs | Main options | Guide |
|-----|----------|--------------|-------|
| `ingress_test` | Test nginx Deployment + Service + Ingress | `ingressClass: traefik`, `host` | [Test deployments](#test-deployments) |
| `apigateway_test` | Test Gateway + HTTPRoute (Gateway API) with weighted routing | `gatewayClass: traefik`, `host` | [Test deployments](#test-deployments) |
| `certmanager` | cert-manager | `selfSignedIssuer` (local CA for `*.kubewekend.local`) | |
| `dashboard` | A Kubernetes dashboard; Rancher also works as an authentication proxy for `kubectl` | `type`: `headlamp`, `kubernetes-dashboard`, `rancher` (needs `certmanager`) | [Dashboard]({% link docs/utilities/dashboard.md %}) |
| `storage` | Longhorn or local-path-provisioner, plus a PVC test | `type`: `longhorn`, `local-path`; `test.enable` | [Storage]({% link docs/utilities/storage.md %}) |
| `secret_management` | Vault or OpenBao | `type`: `vault`, `openbao`; `config.mode`: `dev`, `standalone`; `config.injector` | [Secret management]({% link docs/utilities/secret-management.md %}) |
| `k8s_extensions` | Reflector, Reloader, External Secrets Operator | one `enable` per extension | |
| `gitops` | Argo CD (+ Image Updater, extensions) or Flux (+ Weave GitOps UI); Kargo | `type`: `argocd`, `flux`; `kargo.enable` | [GitOps]({% link docs/utilities/gitops.md %}) |
| `security` | Kyverno or OPA Gatekeeper; Dex identity provider | `policy.type`: `kyverno`, `opa-gatekeeper`; `identity.enable` | |
| `monitoring` | kube-prometheus-stack, Alloy, Loki, Tempo, Pyroscope (LGTM) | `apm` / `logging` / `tracing` / `profiling` `.enable` | [LGTM example]({% link examples/lgtm-testing/README.md %}) |
| `service_mesh` | Istio (`base` + `istiod`, sidecar mode) | `type: istio` | [Istio case studies]({% link examples/istio-case-studies/README.md %}) |

Pinned chart versions are listed in [Versions]({% link docs/reference/versions.md %}).

## Test deployments

Kubewekend ships small workloads that prove a feature works end to end. Run them right after the feature they test:

| What to verify | Command | Check |
|----------------|---------|-------|
| Ingress routing (Traefik) | `utils ingress_test` | `kubectl get ingress -A`, then open `utilities.ingressTestDeployment.host` |
| Gateway API routing | `utils apigateway_test` | `kubectl get gateway,httproute -A`, then open `utilities.apiGatewayTestDeployment.host` |
| Storage provisioning | `utils storage` with `storage.test.enable: true` | `kubectl get pvc test-storage-pvc` is `Bound`, Pod `volume-test` is `Running` |

## In development

Documented in `master.yaml` but not read by the playbook yet (shown as "in dev" by `utils --list`):

| Area | Options |
|------|---------|
| Storage | `csi.nfs` (nfs-subdir-external-provisioner or csi-driver-nfs) |
| Extensions | `sealedsecrets`, `schemahero` |
| Security | `policy.type: default` (ValidatingAdmissionPolicy / MutatingAdmissionPolicy); `kubernetesAuth` (Pinniped impersonation proxy); `intelligence` (Falco, Tetragon) |
| Monitoring | `alertmanager.config` (notification, oncall); `logging.config.collector`, `logging.config.pattern_ingester` |
| Service mesh | `dataplane.mode: ambient` |
| Whole blocks without a tag | `dns`, `glb`, `objectStorage`, `idp`, `scaling`, `devex`, `backupRestore`, `chaosEngineering`, `scheduler`, `workflow`, `rollout`, `gpu`, `operator` |
