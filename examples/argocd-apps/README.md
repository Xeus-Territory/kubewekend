# GitOps with ArgoCD — App of Apps & ApplicationSet Patterns

- [GitOps with ArgoCD — App of Apps \& ApplicationSet Patterns](#gitops-with-argocd--app-of-apps--applicationset-patterns)
  - [Overview](#overview)
  - [Repository Structure](#repository-structure)
  - [Three-Layer Architecture](#three-layer-architecture)
  - [Pattern 1 — App of Apps](#pattern-1--app-of-apps)
    - [How it works](#how-it-works)
    - [Bootstrap Strategy](#bootstrap-strategy)
    - [Example child Application](#example-child-application)
    - [Sync Waves](#sync-waves)
  - [Pattern 2 — ApplicationSet (Alternative)](#pattern-2--applicationset-alternative)
    - [Generator Strategies](#generator-strategies)
      - [1. List Generator](#1-list-generator)
      - [2. Git Generator (Directory)](#2-git-generator-directory)
      - [3. Git Generator (Files)](#3-git-generator-files)
      - [4. Cluster Generator](#4-cluster-generator)
      - [5. Matrix Generator](#5-matrix-generator)
      - [6. SCM Provider Generator](#6-scm-provider-generator)
      - [7. Pull Request Generator](#7-pull-request-generator)
    - [Pattern Comparison](#pattern-comparison)
  - [App Projects (RBAC Isolation)](#app-projects-rbac-isolation)
  - [From Scratch — Practice Guide](#from-scratch--practice-guide)
    - [Prerequisites](#prerequisites)
    - [Step 1 — Spin up a Kubernetes Cluster](#step-1--spin-up-a-kubernetes-cluster)
    - [Step 2 — Initial ArgoCD Installation](#step-2--initial-argocd-installation)
    - [Step 3 — Apply App Projects](#step-3--apply-app-projects)
    - [Step 4 — Apply the argocd Application (App of Apps entry point)](#step-4--apply-the-argocd-application-app-of-apps-entry-point)
    - [Step 5 — Apply Remaining app-of-apps Manifests](#step-5--apply-remaining-app-of-apps-manifests)
    - [Step 6 — Access the ArgoCD UI](#step-6--access-the-argocd-ui)
    - [Step 7 — Teardown](#step-7--teardown)
  - [Helm Chart Structure (Manifests)](#helm-chart-structure-manifests)
  - [References](#references)
    - [ArgoCD Official Docs](#argocd-official-docs)
    - [ApplicationSet Generator Docs](#applicationset-generator-docs)
    - [Examples](#examples)

## Overview

GitOps is an operational model that uses Git as the single source of truth for declarative infrastructure and application delivery. ArgoCD continuously reconciles the cluster state with what is defined in Git, providing automated drift detection and self-healing.

This directory demonstrates two complementary ArgoCD patterns for managing multiple applications at scale:

| Pattern | Best for |
|---|---|
| **App of Apps** | Small to medium clusters; explicit control over every application |
| **ApplicationSet** | Large fleets; dynamic generation from Git structure, cluster lists, or SCM providers |

---

## Repository Structure

```
examples/argocd-apps/
├── app-of-apps/            # ArgoCD Application manifests (child apps)
│   ├── apps/
│   │   └── todo-list.yaml
│   ├── infrastructure/
│   │   └── argocd.yaml     # ← App of Apps entry point (bootstraps ArgoCD self-management)
│   └── platform/
│       └── cert-manager.yaml
├── app-projects/           # AppProject resources (RBAC isolation)
│   ├── apps.yaml
│   ├── infrastructure.yaml
│   └── platform.yaml
└── manifests/              # Helm charts for each application
    ├── apps/
    │   └── todo-list/
    ├── infrastructure/
    │   └── argocd/         # ArgoCD Helm chart (argo-cd + argocd-apps + image-updater)
    └── platform/
        └── cert-manager/   # cert-manager + ClusterIssuer template
```

---

## Three-Layer Architecture

The example follows a three-layer separation of concerns, each backed by a dedicated `AppProject` with scoped RBAC:

```
┌─────────────────────────────────────────────────────┐
│                   INFRASTRUCTURE                     │
│  Project: infrastructure  (full cluster privileges)  │
│  ─────────────────────────────────────────────────  │
│  app-of-apps/infrastructure/argocd.yaml              │
│    └─▶ manifests/infrastructure/argocd/              │
│         (ArgoCD self-management via Helm)            │
├─────────────────────────────────────────────────────┤
│                     PLATFORM                         │
│  Project: platform  (cluster-level tooling)          │
│  ─────────────────────────────────────────────────  │
│  app-of-apps/platform/cert-manager.yaml              │
│    └─▶ manifests/platform/cert-manager/              │
│         (cert-manager CRDs + ClusterIssuers)         │
├─────────────────────────────────────────────────────┤
│                       APPS                           │
│  Project: apps  (namespace-scoped workloads only)    │
│  ─────────────────────────────────────────────────  │
│  app-of-apps/apps/todo-list.yaml                     │
│    └─▶ manifests/apps/todo-list/                     │
│         (workload Deployment + Service + Ingress)    │
└─────────────────────────────────────────────────────┘
```

| Layer | Project | Privileges | Contents |
|---|---|---|---|
| **Infrastructure** | `infrastructure` | Full cluster (`clusterResourceWhitelist: *`) | ArgoCD itself |
| **Platform** | `platform` | Selective cluster-wide (Namespace, CRD, RBAC, StorageClass, WebhookConfig) | cert-manager |
| **Apps** | `apps` | Namespace-scoped workloads only (`clusterResourceBlacklist: *`) | todo-list |

---

## Pattern 1 — App of Apps

### How it works

The App of Apps pattern uses a **bootstrap Application** that points ArgoCD at a directory of child `Application` manifests stored in Git. When it syncs, ArgoCD discovers and creates all child applications — each of which then manages its own Helm chart or manifest directory.

```
Git Repository
└── app-of-apps/
    ├── infrastructure/
    │   └── argocd.yaml          ← ArgoCD Application → manifests/infrastructure/argocd
    ├── platform/
    │   └── cert-manager.yaml    ← ArgoCD Application → manifests/platform/cert-manager
    └── apps/
        └── todo-list.yaml       ← ArgoCD Application → manifests/apps/todo-list

                ↕  continuously reconciled by ArgoCD

Kubernetes Cluster (argocd namespace)
    ├── Application: argocd         (self-manages ArgoCD via Helm)
    ├── Application: cert-manager   (manages cert-manager + ClusterIssuers)
    └── Application: todo-list      (manages workload Deployment)
```

### Bootstrap Strategy

The key insight is that **the `argocd` Application is both the entry point and the self-management declaration for ArgoCD**. Once applied manually, ArgoCD takes ownership of its own Helm release and uses the `argocd-apps` sub-chart to continuously reconcile all remaining Applications.

```
[Manual] kubectl apply → app-of-apps/infrastructure/argocd.yaml
                            │
                            ▼
              ArgoCD reconciles manifests/infrastructure/argocd/
              (Helm chart: argo-cd + argocd-apps + image-updater)
                            │
                            ▼
              argocd-apps sub-chart creates remaining Applications
              from values.yaml  ─────────────────────────────────▶  GitOps is fully self-driving
```

### Example child Application

```yaml
# app-of-apps/apps/todo-list.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: todo-list
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io   # cascading delete on app removal
spec:
  project: apps                                  # scoped to namespace workloads only
  source:
    repoURL: "https://github.com/Xeus-Territory/kubewekend"
    targetRevision: HEAD
    path: "examples/argocd-apps/manifests/apps/todo-list"
    helm:
      releaseName: todo-list
      valueFiles:
        - values.yaml
      version: v3
  destination:
    server: "https://kubernetes.default.svc"
    namespace: "default"
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
```

### Sync Waves

Use `argocd.argoproj.io/sync-wave` annotations to control the deployment order within a sync. Lower wave number = applied first. This is critical for infrastructure that has CRD-to-resource dependencies.

```yaml
# Wave 0: Install cert-manager operator (creates CRDs)
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0"

# Wave 1: Create ClusterIssuer resources (depend on cert-manager CRDs)
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"
```

The `cluster-issuers.yaml` template in `manifests/platform/cert-manager/templates/` already uses wave `"1"` so ClusterIssuers only apply after the operator is healthy.

---

## Pattern 2 — ApplicationSet (Alternative)

`ApplicationSet` is a higher-level CRD that **automatically generates** `Application` resources using generator strategies. This removes the need to manually write one YAML file per application.

### Generator Strategies

#### 1. List Generator

Hardcode a list of parameters. Suitable for a small, known set of environments or clusters.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: apps-list
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - env: staging
            namespace: staging
          - env: production
            namespace: production
  template:
    metadata:
      name: "todo-list-{{env}}"
    spec:
      project: apps
      source:
        repoURL: "https://github.com/Xeus-Territory/kubewekend"
        targetRevision: HEAD
        path: "examples/argocd-apps/manifests/apps/todo-list"
        helm:
          releaseName: "todo-list-{{env}}"
          parameters:
            - name: common.ingress.host
              value: "todo-list.{{env}}.example.com"
      destination:
        server: "https://kubernetes.default.svc"
        namespace: "{{namespace}}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

#### 2. Git Generator (Directory)

Generates one Application per directory found in a Git repo. Adding a new directory to Git automatically creates a new Application — no ApplicationSet changes needed.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: apps-git-dir
  namespace: argocd
spec:
  generators:
    - git:
        repoURL: "https://github.com/Xeus-Territory/kubewekend"
        revision: HEAD
        directories:
          - path: "examples/argocd-apps/manifests/apps/*"
  template:
    metadata:
      name: "{{path.basename}}"
    spec:
      project: apps
      source:
        repoURL: "https://github.com/Xeus-Territory/kubewekend"
        targetRevision: HEAD
        path: "{{path}}"
      destination:
        server: "https://kubernetes.default.svc"
        namespace: "{{path.basename}}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

#### 3. Git Generator (Files)

Reads a `config.json` (or any JSON/YAML file) from each directory and uses its fields as template parameters.

```yaml
# examples/argocd-apps/manifests/apps/todo-list/app-config.json
{
  "app": {
    "name": "todo-list",
    "namespace": "default",
    "env": "production"
  }
}
```

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: apps-git-files
  namespace: argocd
spec:
  generators:
    - git:
        repoURL: "https://github.com/Xeus-Territory/kubewekend"
        revision: HEAD
        files:
          - path: "examples/argocd-apps/manifests/apps/**/app-config.json"
  template:
    metadata:
      name: "{{app.name}}"
    spec:
      project: apps
      source:
        repoURL: "https://github.com/Xeus-Territory/kubewekend"
        targetRevision: HEAD
        path: "examples/argocd-apps/manifests/apps/{{app.name}}"
      destination:
        server: "https://kubernetes.default.svc"
        namespace: "{{app.namespace}}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

#### 4. Cluster Generator

Generates one Application per registered ArgoCD cluster. Ideal for multi-cluster fleet management.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: apps-per-cluster
  namespace: argocd
spec:
  generators:
    - clusters:
        selector:
          matchLabels:
            env: production        # target only production clusters
  template:
    metadata:
      name: "todo-list-{{name}}"
    spec:
      project: apps
      source:
        repoURL: "https://github.com/Xeus-Territory/kubewekend"
        targetRevision: HEAD
        path: "examples/argocd-apps/manifests/apps/todo-list"
      destination:
        server: "{{server}}"       # injected from cluster registration
        namespace: "default"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

#### 5. Matrix Generator

Combines two generators to produce a Cartesian product. For example, deploy every app to every environment.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: apps-matrix
  namespace: argocd
spec:
  generators:
    - matrix:
        generators:
          - git:
              repoURL: "https://github.com/Xeus-Territory/kubewekend"
              revision: HEAD
              directories:
                - path: "examples/argocd-apps/manifests/apps/*"
          - list:
              elements:
                - env: staging
                  server: "https://staging.k8s.local"
                - env: production
                  server: "https://prod.k8s.local"
  template:
    metadata:
      name: "{{path.basename}}-{{env}}"
    spec:
      project: apps
      source:
        repoURL: "https://github.com/Xeus-Territory/kubewekend"
        targetRevision: HEAD
        path: "{{path}}"
      destination:
        server: "{{server}}"
        namespace: "{{path.basename}}-{{env}}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

#### 6. SCM Provider Generator

Generates Applications from repositories discovered in a GitHub/GitLab organization. Useful for platform teams managing repos from multiple squads.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: org-apps
  namespace: argocd
spec:
  generators:
    - scmProvider:
        github:
          organization: MyOrg
          tokenRef:
            secretName: github-token
            key: token
        filters:
          - repositoryMatch: "^service-"    # only repos named service-*
          - branchMatch: "^main$"
  template:
    metadata:
      name: "{{repository}}"
    spec:
      project: apps
      source:
        repoURL: "{{url}}"
        targetRevision: "{{branch}}"
        path: "deploy/helm"
      destination:
        server: "https://kubernetes.default.svc"
        namespace: "{{repository}}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

#### 7. Pull Request Generator

Creates ephemeral preview environments for every open pull request.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: pr-previews
  namespace: argocd
spec:
  generators:
    - pullRequest:
        github:
          owner: Xeus-Territory
          repo: kubewekend
          tokenRef:
            secretName: github-token
            key: token
          labels:
            - preview                       # only PRs tagged with "preview"
        requeueAfterSeconds: 60
  template:
    metadata:
      name: "pr-{{number}}-todo-list"
    spec:
      project: apps
      source:
        repoURL: "https://github.com/Xeus-Territory/kubewekend"
        targetRevision: "{{head_sha}}"
        path: "examples/argocd-apps/manifests/apps/todo-list"
        helm:
          parameters:
            - name: common.ingress.host
              value: "pr-{{number}}.preview.example.com"
      destination:
        server: "https://kubernetes.default.svc"
        namespace: "pr-{{number}}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

### Pattern Comparison

| Strategy | Trigger | Use case |
|---|---|---|
| List | Manual YAML edit | Small fixed set of targets |
| Git Directory | New folder commit | Self-service app onboarding |
| Git Files | Config file commit | Parameter-rich deployments |
| Cluster | New cluster registered | Multi-cluster fleet rollout |
| Matrix | Combined generator events | Apps × environments cross-product |
| SCM Provider | New repo in org | Organization-wide platform |
| Pull Request | PR opened/closed | Ephemeral preview environments |

---

## App Projects (RBAC Isolation)

`AppProject` resources scope what each set of applications can access. Three projects are defined with progressively tighter RBAC:

| Project | Layer | Source Repos | Cluster Privileges | Namespace Access |
|---|---|---|---|---|
| `infrastructure` | Bootstrap | Any (`*`) | Full (`clusterResourceWhitelist: *`) | All namespaces |
| `platform` | Tooling | Pinned repos (kubewekend, jetstack, grafana, prometheus-community) | Selective (Namespace, CRD, RBAC, StorageClass, Webhook, ClusterIssuer) | All except `kube-system` |
| `apps` | Workloads | Pinned repo (kubewekend) | Blocked (`clusterResourceBlacklist: *`) | All except kube-system, argocd, monitoring, logging, cert-manager, traefik |

Each project also ships pre-defined **roles**:

- `infrastructure` → `infra-admin` (full provisioning access + exec)
- `platform` → `platform-engineer` (CRUD sync on platform apps)
- `apps` → `developer` (deploy/sync workloads), `viewer` (read-only)

---

## From Scratch — Practice Guide

### Prerequisites

| Tool | Required | Purpose |
|---|---|---|
| [vagrant](https://developer.hashicorp.com/vagrant/docs/installation) | Yes* | VM provisioning |
| [VirtualBox](https://www.virtualbox.org/wiki/Downloads) | Yes* | VM provider |
| [ansible](https://docs.ansible.com/ansible/latest/installation_guide/) | Yes | Cluster orchestration |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | Yes | Kubernetes CLI |
| [helm](https://helm.sh/docs/intro/install/) | Yes | Helm chart management |
| [docker](https://docs.docker.com/engine/install/) | For Kind | Required for Kind clusters |

> \* Vagrant + VirtualBox are only required for local VM workflows. Skip for remote VPS or localhost Kind.

See the full [Kubewekend CLI reference](../../scripts/README.md) for all available commands.

---

### Step 1 — Spin up a Kubernetes Cluster

Use the **Kubewekend CLI** (`./scripts/setup.sh`) to provision a local cluster. Pick the workflow that matches your environment:

**Kind on Vagrant (recommended for local play):**

```bash
# 1. Initialize environment
chmod +x ./scripts/setup.sh
./scripts/setup.sh env init          # creates .env from template.env
./scripts/setup.sh env check         # verify all tools are installed

# 2. Provision the VM
./scripts/setup.sh vagrant up k8s-master-machine

# 3. Generate inventory and verify SSH connectivity
./scripts/setup.sh inventory generate
./scripts/setup.sh inventory ping

# 4. Create the Kind cluster (installs CNI, kubeconfig)
./scripts/setup.sh kind setup
```

**K3s Standalone on Vagrant:**

```bash
./scripts/setup.sh vagrant up k8s-master-machine k8s-worker-machine-1
./scripts/setup.sh inventory generate
./scripts/setup.sh inventory ping
./scripts/setup.sh k3s setup

# Fetch kubeconfig
ssh vagrant@192.168.56.99 'sudo cat /etc/rancher/k3s/k3s.yaml' \
  | sed 's/127.0.0.1/192.168.56.99/' > ~/.kube/config
```

**Kind on localhost (no Vagrant):**

```bash
# Manually configure inventory for localhost
cat > ansible/inventories/hosts <<'EOF'
[standalone-masters]
localhost ansible_host=127.0.0.1 ansible_connection=local

[standalone-all:children]
standalone-masters
EOF

./scripts/setup.sh kind setup --host localhost
kubectl cluster-info --context kind-kubewekend
```

Verify the cluster is ready:

```bash
kubectl get nodes
```

---

### Step 2 — Initial ArgoCD Installation

ArgoCD must be running before we can apply Application manifests. This is a **one-time manual bootstrap** — after Step 4, ArgoCD will self-manage its own installation via GitOps.

**Option A — Stable manifest (quickstart):**

```bash
kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

**Option B — Helm chart from this repo (production-grade, matches `values.yaml`):**

```bash
cd examples/argocd-apps/manifests/infrastructure/argocd
helm dependency update
helm template argocd . -f values.yaml --namespace argocd \
  | kubectl apply -n argocd -f -
```

Wait for ArgoCD to be healthy:

```bash
kubectl wait --for=condition=available deployment/argocd-server \
  -n argocd --timeout=120s
```

**Option C - Deploy ArgoCD via Utilities of Kubewekend (Simple version with no advantage configuration):**

```bash
# For K3s
./scripts/setup.sh k3s utilities gitops --host k8s-master-machine

# For Kind
./scripts/setup.sh kind utilities gitops --host localhost
```
---

### Step 3 — Apply App Projects

Apply all three `AppProject` resources to create the RBAC boundaries before any Application is created:

```bash
kubectl apply -f examples/argocd-apps/app-projects/
```

Verify:

```bash
kubectl get appprojects -n argocd
# NAME             AGE
# apps             5s
# infrastructure   5s
# platform         5s
```

---

### Step 4 — Apply the argocd Application (App of Apps entry point)

This is the **single command that kicks off the entire GitOps loop**. Applying `app-of-apps/infrastructure/argocd.yaml` tells ArgoCD to reconcile the full ArgoCD Helm chart from `manifests/infrastructure/argocd/`. That chart bundles the `argocd-apps` sub-chart, which can then create and manage all remaining Applications declaratively.

>[!TIP]
>In the first time provision, you can change project of `argocd` to `default` for ignore conflict with highest permission when we sync ArgoCD in UI, but if you handle and trigger the step 3, you can set project to `infrastructure`

```
[You] kubectl apply -f app-of-apps/infrastructure/argocd.yaml
         │
         ▼
[ArgoCD] Reconciles manifests/infrastructure/argocd/  (Helm)
         ├── argo-cd        v9.1.3   → ArgoCD v3.2.0 (self-managed)
         ├── argocd-apps    v2.0.2   → manages remaining Application resources
         └── image-updater  v1.0.1   → auto-updates container image tags
         │
         ▼
[argocd-apps] Creates Application resources from values.yaml
              └── GitOps is now fully self-driving
```

```bash
kubectl apply -n argocd \
  -f examples/argocd-apps/app-of-apps/infrastructure/argocd.yaml
```

Watch the Application sync in real time:

```bash
kubectl get applications -n argocd -w
# NAME     SYNC STATUS   HEALTH STATUS
# argocd   Synced        Healthy
```

> [!NOTE]
> ArgoCD will now manage its own Helm release. Any future changes to `manifests/infrastructure/argocd/values.yaml` committed to Git will automatically be reconciled — no manual `helm upgrade` needed.

---

### Step 5 — Apply Remaining app-of-apps Manifests

With ArgoCD self-managing, apply the platform and app layer Applications:

```bash
# Platform layer (cert-manager)
kubectl apply -n argocd \
  -f examples/argocd-apps/app-of-apps/platform/cert-manager.yaml

# Apps layer (todo-list workload)
kubectl apply -n argocd \
  -f examples/argocd-apps/app-of-apps/apps/todo-list.yaml
```

Watch all applications converge:

```bash
kubectl get applications -n argocd
# NAME           SYNC STATUS   HEALTH STATUS
# argocd         Synced        Healthy
# cert-manager   Synced        Healthy
# todo-list      Synced        Healthy
```

Full end-to-end flow once all steps are complete:

```
Git Push
   │
   ▼
GitHub (examples/argocd-apps/)
   │
   ▼  ArgoCD polls every 180s (or webhook)
   │
   ├──▶ app-of-apps/infrastructure/argocd.yaml
   │       └──▶ manifests/infrastructure/argocd/   (ArgoCD Helm release)
   │
   ├──▶ app-of-apps/platform/cert-manager.yaml
   │       └──▶ manifests/platform/cert-manager/   (cert-manager + ClusterIssuers)
   │
   └──▶ app-of-apps/apps/todo-list.yaml
           └──▶ manifests/apps/todo-list/           (workload Deployment)
```

---

### Step 6 — Access the ArgoCD UI

```bash
# Port-forward the ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:80

# Retrieve the initial admin password (if not set in values.yaml)
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 --decode && echo
```

Open [http://localhost:8080](http://localhost:8080) and log in with `admin` / `<decoded password>`.

> [!TIP]
> The `values.yaml` in `manifests/infrastructure/argocd/` sets `configs.params.server.insecure: true`, so the UI is served over HTTP. Use port `8080:80`, not `8080:443`.

---

### Step 7 — Teardown

```bash
# Remove all Applications (cascading delete removes managed resources)
kubectl delete -n argocd \
  -f examples/argocd-apps/app-of-apps/apps/todo-list.yaml \
  -f examples/argocd-apps/app-of-apps/platform/cert-manager.yaml \
  -f examples/argocd-apps/app-of-apps/infrastructure/argocd.yaml

# Remove App Projects
kubectl delete -f examples/argocd-apps/app-projects/

# Destroy the cluster (Kind)
./scripts/setup.sh kind destroy

# Or for K3s
./scripts/setup.sh k3s destroy

# Destroy VMs (if using Vagrant)
./scripts/setup.sh vagrant destroy
```

---

## Helm Chart Structure (Manifests)

Each application under `manifests/` is a thin wrapper Helm chart that declares a dependency on the upstream chart. This pattern:

- Pins the upstream chart version in `Chart.yaml`
- Keeps all configuration in `values.yaml` (version-controlled)
- Allows ArgoCD to render and diff the final manifests

```
manifests/platform/cert-manager/
├── Chart.yaml          # pins cert-manager v1.19.2
├── values.yaml         # installCRDs: true, clusterIssuers list
└── templates/
    └── cluster-issuers.yaml   # generates ClusterIssuer resources (sync-wave: "1")
```

The `argocd` chart bundles three components under one Helm release:

| Sub-chart | Alias | Version | Purpose |
|---|---|---|---|
| `argo-cd` | `argocd` | `9.1.3` (ArgoCD `v3.2.0`) | Core ArgoCD |
| `argocd-apps` | `apps` | `2.0.2` | Manages Application/AppProject resources via values |
| `argocd-image-updater` | `image-updater` | `1.0.1` | Auto-updates image tags in Git |

Notable `values.yaml` settings in the `argocd` chart:

| Setting | Value | Effect |
|---|---|---|
| `argocd.configs.params.server.insecure` | `true` | HTTP mode (no TLS termination at ArgoCD) |
| `argocd.configs.cm.timeout.reconciliation` | `180s` | Polling interval for drift detection |
| `argocd.configs.cm.exec.enabled` | `true` | Enables `argocd exec` into pods from UI |
| `argocd.global.domain` | `argocd.local` | Ingress hostname |
| `argocd.global.image.tag` | `v3.2.0` | Pinned ArgoCD version |

---

## References

### ArgoCD Official Docs

- [Declarative Setup](https://argo-cd.readthedocs.io/en/latest/operator-manual/declarative-setup/)
- [App of Apps Pattern](https://argo-cd.readthedocs.io/en/latest/operator-manual/cluster-bootstrapping/#app-of-apps-pattern-alternative)
- [ApplicationSet Overview](https://argo-cd.readthedocs.io/en/latest/operator-manual/applicationset/)
- [ApplicationSet Generators](https://argo-cd.readthedocs.io/en/latest/operator-manual/applicationset/Generators/)
- [Helm Integration](https://argo-cd.readthedocs.io/en/latest/user-guide/helm/)
- [App Projects](https://argo-cd.readthedocs.io/en/stable/user-guide/projects/)
- [Sync Waves & Hooks](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)

### ApplicationSet Generator Docs

- [List Generator](https://argo-cd.readthedocs.io/en/latest/operator-manual/applicationset/Generators-List/)
- [Cluster Generator](https://argo-cd.readthedocs.io/en/latest/operator-manual/applicationset/Generators-Cluster/)
- [Git Generator](https://argo-cd.readthedocs.io/en/latest/operator-manual/applicationset/Generators-Git/)
- [Matrix Generator](https://argo-cd.readthedocs.io/en/latest/operator-manual/applicationset/Generators-Matrix/)
- [Merge Generator](https://argo-cd.readthedocs.io/en/latest/operator-manual/applicationset/Generators-Merge/)
- [SCM Provider Generator](https://argo-cd.readthedocs.io/en/latest/operator-manual/applicationset/Generators-SCM-Provider/)
- [Pull Request Generator](https://argo-cd.readthedocs.io/en/latest/operator-manual/applicationset/Generators-Pull-Request/)

### Examples

- [GitHub - argocd-helm-app-of-apps-example](https://github.com/stevesea/argocd-helm-app-of-apps-example)
- [GitHub - argocd-example-apps](https://github.com/argoproj/argocd-example-apps)
- [GitHub - ApplicationSet examples](https://github.com/argoproj/applicationset/tree/master/examples)