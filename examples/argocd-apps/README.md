# GitOps with ArgoCD — App of Apps & ApplicationSet Patterns

- [GitOps with ArgoCD — App of Apps \& ApplicationSet Patterns](#gitops-with-argocd--app-of-apps--applicationset-patterns)
  - [Overview](#overview)
  - [Repository Structure](#repository-structure)
  - [Pattern 1 — App of Apps](#pattern-1--app-of-apps)
    - [How it works](#how-it-works)
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
  - [Bootstrap Guide](#bootstrap-guide)
    - [Prerequisites](#prerequisites)
    - [Step 1 — Install ArgoCD](#step-1--install-argocd)
    - [Step 2 — Apply App Projects](#step-2--apply-app-projects)
    - [Step 3 — Create the Root App (App of Apps bootstrap)](#step-3--create-the-root-app-app-of-apps-bootstrap)
    - [Step 4 — Access the ArgoCD UI](#step-4--access-the-argocd-ui)
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
│   └── infrastructure/
│       ├── argocd.yaml
│       └── cert-manager.yaml
├── app-projects/           # AppProject resources (RBAC isolation)
│   ├── apps.yaml
│   ├── infrastructure.yaml
│   └── platform.yaml
└── manifests/              # Helm charts for each application
    ├── apps/
    │   └── todo-list/
    ├── infrastructure/
    │   ├── argocd/
    │   ├── cert-manager/
    │   ├── argo-rollouts/
    │   └── argo-workflow/
    └── platform/
```

---

## Pattern 1 — App of Apps

### How it works

The App of Apps pattern uses a **root Application** that points ArgoCD at a directory of child `Application` manifests stored in Git. When the root app syncs, it discovers and creates all child applications — each of which then manages its own Helm chart or manifest directory.

```
Git Repository
└── app-of-apps/
    ├── apps/
    │   └── todo-list.yaml       ← ArgoCD Application → manifests/apps/todo-list
    └── infrastructure/
        ├── argocd.yaml          ← ArgoCD Application → manifests/infrastructure/argocd
        └── cert-manager.yaml    ← ArgoCD Application → manifests/infrastructure/cert-manager

                ↕  reconciled by ArgoCD

Kubernetes Cluster
└── argocd namespace
    ├── Application: root-app       (the bootstrap entry point)
    ├── Application: todo-list      (manages todo-list Helm release)
    ├── Application: argocd         (manages ArgoCD itself)
    └── Application: cert-manager   (manages cert-manager + ClusterIssuers)
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
    - resources-finalizer.argocd.argoproj.io   # cascading delete
spec:
  project: apps
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
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### Sync Waves

Use `argocd.argoproj.io/sync-wave` annotations to control the deployment order within a sync operation. Resources with lower wave numbers are applied first.

```yaml
# Deploy cert-manager CRDs before ClusterIssuers
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0"   # wave 0: cert-manager operator

# ClusterIssuer resources wait for wave 1
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"   # wave 1: ClusterIssuer resources
```

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

`AppProject` resources scope what each set of applications can access. Three projects are defined in this example:

| Project | Applications | Purpose |
|---|---|---|
| `apps` | todo-list, user-facing services | Deploy workloads to application namespaces |
| `infrastructure` | argocd, cert-manager, networking | Deploy cluster-level infrastructure |
| `platform` | monitoring, logging, observability | Deploy platform-layer components |

```yaml
# app-projects/infrastructure.yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: infrastructure
  namespace: argocd
spec:
  sourceRepos:
    - https://github.com/Xeus-Territory/kubewekend.git
  sourceNamespaces:
    - '*'
  destinations:
    # Allow apps to be installed in any namespace and any cluster.
    - server: '*'
      namespace: '*'
  clusterResourceWhitelist:
  - group: '*'
    kind: '*'
```

> [!TIP]
> Tighten `namespaceResourceBlacklist` and `clusterResourceWhitelist` in production to limit the blast radius of a misconfigured Application.

---

## Bootstrap Guide

### Prerequisites

- Kubernetes cluster (k3s, kind, or cloud-managed)
- `kubectl` configured against the cluster
- `helm` v3 installed

### Step 1 — Install ArgoCD

**Option A** — Stable manifest (quickstart):

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

**Option B** — Helm chart (recommended, production-grade):

```bash
cd examples/argocd-apps/manifests/infrastructure/argocd

helm dependency update
helm template argocd . -f values.yaml -n argocd | kubectl apply -n argocd -f -
```

Wait for ArgoCD to be ready:

```bash
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=120s
```

### Step 2 — Apply App Projects

```bash
kubectl apply -f examples/argocd-apps/app-projects/
```

### Step 3 — Create the Root App (App of Apps bootstrap)

Apply the root Application that points ArgoCD at the `app-of-apps/` directory:

```bash
kubectl apply -n argocd -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argocd-apps
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: "https://github.com/Xeus-Territory/kubewekend"
    targetRevision: HEAD
    path: "examples/argocd-apps/app-of-apps"
    directory:
      recurse: true
  destination:
    server: "https://kubernetes.default.svc"
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
```

ArgoCD will discover all `Application` YAML files under `app-of-apps/` and create them automatically.

### Step 4 — Access the ArgoCD UI

```bash
# Port-forward the ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Retrieve the initial admin password
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 --decode
```

Open `https://localhost:8080` and log in with `admin` / `<decoded password>`.

---

## Helm Chart Structure (Manifests)

Each application under `manifests/` is a thin wrapper Helm chart that declares a dependency on the upstream chart. This pattern:

- Pins the upstream chart version in `Chart.yaml`
- Keeps all configuration in `values.yaml` (version-controlled)
- Allows ArgoCD to render and diff the final manifests

```
manifests/infrastructure/cert-manager/
├── Chart.yaml          # pins cert-manager v1.19.2
├── values.yaml         # installCRDs, clusterIssuers list
└── templates/
    └── cluster-issuers.yaml   # custom template for ClusterIssuer resources
```

The `argocd` chart bundles three components under one release:

| Sub-chart | Alias | Version |
|---|---|---|
| `argo-cd` | `argocd` | `9.1.3` (ArgoCD `v3.2.0`) |
| `argocd-apps` | `apps` | `2.0.2` |
| `argocd-image-updater` | `image-updater` | `1.0.1` |

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