# Argo CD labs

Four hands-on labs that show the Argo CD ecosystem working together on Kind: bootstrap a whole cluster from Git with
the **App of Apps** pattern, isolate teams with **AppProjects**, deploy the same app with an `Application` and with an
`ApplicationSet`, let **Argo CD Image Updater** roll out a new image by committing to Git, and connect a second
cluster with **argocd-agent** without exposing its API server.

Every command and output in these pages comes from a real run (Kind v0.33, Kubernetes v1.36, Argo CD 3.2 for labs 1 to 3
and Argo CD 3.6 for lab 4).

## The labs

| Lab | What you build | What it proves | Needs |
|-----|----------------|----------------|-------|
| [00 Platform](00-platform/README.md) | A one-node Kind cluster with Traefik | The base for labs 1 to 3 | Docker, Kind, kubectl, Helm |
| [01 Bootstrap and multi-tenancy](01-bootstrap-multi-tenancy/README.md) | One manifest that builds the platform and the apps, in order, inside three AppProjects | App of Apps, sync waves, and tenant boundaries (what a team may deploy, where and who may sync) | Lab 00 |
| [02 Application vs ApplicationSet](02-application-vs-applicationset/README.md) | The same hello-world app deployed by a hand-written `Application` (Helm) and by an `ApplicationSet` (Kustomize overlays) | When to write one object and when to generate many | Lab 01 (a fork for one step) |
| [03 Image Updater](03-image-updater/README.md) | An `ImageUpdater` resource that tracks a registry and commits new tags to Git | A new image reaches the cluster with no human step, for Helm and for Kustomize | Lab 01 (captured output, optional to repeat) |
| [04 argocd-agent](04-argocd-agent/README.md) | Two Kind clusters: a hub that owns the desired state and a spoke that pulls it | A cluster managed over an **outbound-only** connection, and what happens when the hub is down | Docker, Kind, kubectl, `argocd-agentctl` |

Labs 1 to 3 share one cluster and build on each other. Lab 4 uses its own two clusters, so it can be done on its own.

## The example app

All workloads run one small todo list (Express + React + SQLite) built from [`app/`](https://github.com/Xeus-Territory/kubewekend/tree/main/examples/argocd-apps/app). It has a `/version`
endpoint and a banner at the top of the page, so every rollout is visible in the browser and with `curl`:

```text
{"version":"v1.0.0","message":"Hello from Kubewekend","hostname":"hello-helm-75dc8959fd-8dn6x"}
```

| Workload | Built with | Deployed by | Where |
|----------|------------|-------------|-------|
| `hello-helm` | The Kubewekend [`common`](https://github.com/Xeus-Territory/kubewekend/tree/main/kubernetes/charts/common) chart | One `Application` | [`workloads/hello-helm`](https://github.com/Xeus-Territory/kubewekend/tree/main/examples/argocd-apps/workloads/hello-helm) |
| `hello-kustomize` | Plain Kustomize: `base/` plus `overlays/dev` and `overlays/prod` | One `ApplicationSet` | [`workloads/hello-kustomize`](https://github.com/Xeus-Territory/kubewekend/tree/main/examples/argocd-apps/workloads/hello-kustomize) |

The image is `xeusnguyen/kubewekend-todo`. Build it yourself with the [`app/Dockerfile`](https://github.com/Xeus-Territory/kubewekend/blob/main/examples/argocd-apps/app/Dockerfile) if you want your
own tags (`--build-arg APP_VERSION=v1.1.0 --build-arg APP_MESSAGE="..."`).

## Layout

```text
examples/argocd-apps/
├── app-of-apps.yaml          # the ONE manifest you apply by hand (lab 1)
├── app-of-apps/
│   ├── projects/             # AppProjects: infrastructure, platform, apps      (sync wave -1)
│   ├── infrastructure/       # Argo CD manages itself                           (sync wave 0)
│   ├── platform/             # cert-manager                                     (sync wave 1)
│   └── apps/                 # hello-helm (Application), hello-kustomize (ApplicationSet)  (sync wave 2)
├── manifests/                # Helm wrapper charts for the infrastructure and platform layers
├── workloads/                # the demo apps (hello-helm, hello-kustomize)
├── app/                      # the todo app and its Dockerfile
└── labs/                     # these pages and their small manifests
```

## Versions

| Component | Version |
|-----------|---------|
| Kind / node image | v0.33.0 / `kindest/node:v1.36.4` |
| Argo CD (labs 1 to 3), Helm chart | v3.2.0, `argo-cd` 9.1.3 |
| Argo CD Image Updater, Helm chart | 1.0.x, `argocd-image-updater` 1.0.1 |
| cert-manager | v1.19.2 |
| Traefik chart | 42.0.0 |
| argocd-agent (lab 4) | v0.11.0, which installs the Argo CD 3.6 stream |
| Kubewekend `common` chart | 0.4.0 |

> [!NOTE]
>
> The labs run on any Kubernetes cluster, but the commands are written for Kind. Kubewekend's K3s, RKE2 and Kind
> clusters normally ship Traefik (unless you turned ingress off), so you can skip that part of [lab 00](00-platform/README.md).
