# GitOps with Argo CD: App of Apps, ApplicationSet, Image Updater and argocd-agent

A hands-on example of the Argo CD ecosystem on Kind. One manifest builds a whole cluster from Git, the same app is
deployed with an `Application` and with an `ApplicationSet`, new images roll out by themselves, and a second cluster is
managed without exposing its API server.

- [What you will learn](#what-you-will-learn)
- [Quick start](#quick-start)
- [How it fits together](#how-it-fits-together)
- [Repository layout](#repository-layout)
- [AppProjects: the tenant boundaries](#appprojects-the-tenant-boundaries)
- [Reference: ApplicationSet generators](#reference-applicationset-generators)
- [Reference: sync waves](#reference-sync-waves)
- [Versions](#versions)
- [The previous README](#the-previous-readme)

## What you will learn

Four labs, each a page with commands, real outputs, an experiment that breaks something on purpose, and a self-check:

| Lab | Topic |
|-----|-------|
| [00 Platform](labs/00-platform/README.md) | A one-node Kind cluster with Traefik |
| [01 Bootstrap and multi-tenancy](labs/01-bootstrap-multi-tenancy/README.md) | The **App of Apps** pattern, sync waves, and **AppProject** boundaries per application group |
| [02 Application vs ApplicationSet](labs/02-application-vs-applicationset/README.md) | A hand-written `Application` (Helm) and a generated set of Applications (Kustomize overlays), side by side |
| [03 Image Updater](labs/03-image-updater/README.md) | **argocd-image-updater** commits new image tags to Git, for both Helm and Kustomize |
| [04 argocd-agent](labs/04-argocd-agent/README.md) | Two Kind clusters: a hub and a spoke that pulls its desired state over an **outbound-only** connection |

The [labs index](labs/README.md) explains the example app, the layout and the versions.

## Quick start

Needs Docker, Kind, kubectl and Helm. This is the short version of labs 00 and 01 (run it from the repository root).
Run `cloud-provider-kind` in another terminal first, so Traefik gets an address (see lab 00).

```bash
kind create cluster --config examples/argocd-apps/labs/00-platform/kind-gitops.yaml

helm repo add traefik https://traefik.github.io/charts && helm repo update traefik
helm upgrade --install traefik traefik/traefik --version 42.0.0 --namespace traefik --create-namespace --wait

cd examples/argocd-apps/manifests/infrastructure/argocd
helm dependency update .
helm upgrade --install argocd . --namespace argocd --create-namespace --wait
cd ../../..

kubectl apply -f app-of-apps.yaml
kubectl -n argocd get applications.argoproj.io -w      # Ctrl-C when all six are Synced and Healthy
```

Then reach the apps through the ingress address, for example
`curl --resolve hello-helm.kubewekend.local:80:<ingress-ip> http://hello-helm.kubewekend.local/version`.

## How it fits together

```text
app-of-apps.yaml                  the ONE manifest you apply by hand (Application, project: default)
└── app-of-apps/                  read recursively by the root application
    ├── projects/        wave -1  AppProjects: infrastructure, platform, apps
    ├── infrastructure/  wave  0  Argo CD manages itself from manifests/infrastructure/argocd
    ├── platform/        wave  1  cert-manager
    └── apps/            wave  2  hello-helm (Application) and hello-kustomize (ApplicationSet)
```

Argo CD creates the projects first, then itself, then the platform, then the workloads, waiting for each wave to be
healthy. `argocd` is the same Helm chart you installed by hand, so from then on Argo CD upgrades itself from Git.

## Repository layout

```text
examples/argocd-apps/
├── app-of-apps.yaml          the root Application
├── app-of-apps/              what the root application creates (projects, infrastructure, platform, apps)
├── manifests/                Helm wrapper charts: infrastructure/argocd, infrastructure/argo-rollouts,
│                             infrastructure/argo-workflow, platform/cert-manager
├── workloads/                the demo apps: hello-helm (Helm + common chart), hello-kustomize (base + dev and prod overlays)
├── app/                      the todo app (Express, React, SQLite) and its Dockerfile
├── labs/                     the lab pages and their small manifests
└── archives/                 the previous README
```

`manifests/infrastructure/argo-rollouts` and `argo-workflow` are Helm wrappers that no lab deploys yet. They are kept for
a future Argo Rollouts and Argo Workflows lab.

## AppProjects: the tenant boundaries

Three projects, tightening from the cluster operator to the application team (lab 01 explains and breaks each one):

| Project | Layer | Git sources | Destinations | Cluster-wide objects |
|---------|-------|-------------|--------------|----------------------|
| `infrastructure` | Bootstrap | Any | Any cluster, any namespace | Anything |
| `platform` | Tooling | This repo and the cert-manager, Grafana and Prometheus chart repos | Any namespace except `kube-system` | A short list (Namespace, PV, ClusterRole and binding, CRD, StorageClass, IngressClass, webhooks, ClusterIssuer) |
| `apps` | Workloads | This repo only | In-cluster, except `kube-system`, `argocd`, `monitoring`, `logging`, `cert-manager` and `traefik` | **Namespace only** |

Each project defines roles: `infra-admin`, `platform-engineer` and `developer`, each with a read-only `viewer`. The
manifests are in [`app-of-apps/projects`](app-of-apps/projects).

## Reference: ApplicationSet generators

[Lab 02](labs/02-application-vs-applicationset/README.md) uses the **git directory** generator. These are the
generators to know. Full field lists are in the [upstream documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators/).

| Generator | What it iterates over | Trigger | Typical use |
|-----------|-----------------------|---------|-------------|
| `list` | A fixed list of parameter sets written in the ApplicationSet | Editing the ApplicationSet | A small, known set of environments or clusters |
| `git` (directories) | Folders in a Git repository | A new folder is committed | Self-service onboarding: one folder per app or environment (lab 02) |
| `git` (files) | JSON or YAML files in a Git repository, whose fields become parameters | A config file is committed | Parameter-rich deployments, one config file each |
| `clusters` | Clusters registered in Argo CD, optionally filtered by label | A cluster is registered | Rolling an app out to a fleet |
| `matrix` | The cross-product of two generators | Either side changes | Apps x environments, or apps x clusters |
| `merge` | Several generators merged by a key | Any source changes | A base set with per-item overrides |
| `scmProvider` | Repositories in a GitHub, GitLab or Gitea organisation | A new repository | Organisation-wide onboarding |
| `pullRequest` | Open pull requests | A pull request is opened or closed | Preview environments |

The previous README has a worked example of each, written for the old layout: see
[`archives/README-v1.md`](archives/README-v1.md). The working example in this repository is
[`app-of-apps/apps/hello-kustomize.yaml`](app-of-apps/apps/hello-kustomize.yaml).

## Reference: sync waves

The annotation `argocd.argoproj.io/sync-wave` orders the objects of one sync. A lower number goes first, and Argo CD waits
for a wave to be healthy before starting the next. The default is wave 0. This example uses them in two places:

- **Between layers** (projects `-1`, Argo CD `0`, platform `1`, apps `2`), so a workload never starts before the platform
  it needs.
- **Inside a chart**: the ClusterIssuers of the cert-manager wrapper
  ([`cluster-issuers.yaml`](manifests/platform/cert-manager/templates/cluster-issuers.yaml)) are wave `1`, so they are
  applied only after cert-manager and its CRDs are up.

> [!IMPORTANT]
>
> Waves between **Applications** only work if Argo CD can read an Application's health. That check is in the Argo CD
> values ([`manifests/infrastructure/argocd/values.yaml`](manifests/infrastructure/argocd/values.yaml)); without it an
> Application counts as healthy the moment it is created. Lab 01 shows the difference.

## Versions

| Component | Version |
|-----------|---------|
| Argo CD (labs 1 to 3), Helm chart | v3.2.0, `argo-cd` 9.1.3 |
| Argo CD Image Updater, Helm chart | 1.0.x, `argocd-image-updater` 1.0.1 |
| argocd-agent (lab 4) | v0.11.0 (Argo CD 3.6 stream) |
| cert-manager | v1.19.2 |
| Traefik chart | 42.0.0 |
| Kind / node image | v0.33.0 / `kindest/node:v1.36.4` |
| Kubewekend `common` chart | 0.4.0 |

## The previous README

The earlier version of this page (a long practice guide built around a `todo-list` app, with a worked example of every
ApplicationSet generator) is kept in [`archives/README-v1.md`](archives/README-v1.md).
