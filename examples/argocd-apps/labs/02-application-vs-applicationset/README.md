# Lab 02: Application vs ApplicationSet

**Goal:** understand why Argo CD has both an `Application` and an `ApplicationSet`, by deploying the same hello-world app
both ways and watching what each one does when you change things.

Suggested time: 1 hour. Needs the cluster from [Lab 01](../01-bootstrap-multi-tenancy/README.md). One step pushes a
commit, so it needs [your own fork](../00-platform/README.md#using-your-own-fork-needed-for-one-step-in-lab-2) or the
[local Gitea](../00-platform/README.md#practise-locally-with-gitea-and-a-registry-no-github) from lab 00.

## Concepts

| | `Application` | `ApplicationSet` |
|---|---------------|------------------|
| What it is | One deployment: one source, one destination, one sync policy | A **template** plus **generators** that produce many Applications |
| Who writes the Applications | You, one YAML per deployment | The ApplicationSet controller |
| Adding a deployment | Write a new file | Add a folder, a cluster or a list item the generator watches |
| Removing a deployment | Delete the file | Remove the folder, the cluster or the list item |
| Best for | One explicit thing: a platform component, a single service | The same thing many times: environments, clusters, teams, pull requests |

Both are plain Kubernetes objects stored in Git and created here by the root application from
[Lab 01](../01-bootstrap-multi-tenancy/README.md) (sync wave 2, project `apps`).

## Case study 1: an `Application` for the Helm app

[`app-of-apps/apps/hello-helm.yaml`](https://github.com/Xeus-Territory/kubewekend/blob/main/examples/argocd-apps/app-of-apps/apps/hello-helm.yaml) is the whole story of one deployment:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: hello-helm
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "2"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: apps
  source:
    repoURL: "https://github.com/Xeus-Territory/kubewekend"
    targetRevision: HEAD
    path: "examples/argocd-apps/workloads/hello-helm"
    helm:
      releaseName: hello-helm
      valueFiles:
        - values.yaml
  destination:
    server: "https://kubernetes.default.svc"
    namespace: hello-helm
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

- `source` is a Helm chart in Git: a wrapper around Kubewekend's `common` chart with `values.yaml` next to it.
- `automated` with `selfHeal: true` makes Argo CD undo changes made by hand. Try it:

```bash
kubectl -n hello-helm scale deploy/hello-helm --replicas=3
for i in 1 2 3 4 5 6; do
  echo "t+$((i*5))s replicas: $(kubectl -n hello-helm get deploy hello-helm -o jsonpath='{.spec.replicas}')"
  sleep 5
done
```

```text
t+5s replicas: 3
t+10s replicas: 1
t+15s replicas: 1
t+20s replicas: 1
t+25s replicas: 1
t+30s replicas: 1
```

Argo CD compared the live Deployment with Git, saw one replica wanted, and corrected it in about ten seconds.

## Case study 2: an `ApplicationSet` for the Kustomize app

[`app-of-apps/apps/hello-kustomize.yaml`](https://github.com/Xeus-Territory/kubewekend/blob/main/examples/argocd-apps/app-of-apps/apps/hello-kustomize.yaml) does not describe one
deployment. It describes how to make one deployment **per overlay folder**:

| Field | Value | Meaning |
|-------|-------|---------|
| generator | `git`, `directories: workloads/hello-kustomize/overlays/*` | One result for every folder under `overlays/` |
| template name | `hello-kustomize-` plus the folder name | `dev` gives `hello-kustomize-dev`, `prod` gives `hello-kustomize-prod` |
| template source | the folder's path | Each Application deploys its own overlay |
| template destination | namespace `hello-` plus the folder name | `hello-dev`, `hello-prod` |
| template project and sync policy | `apps`, automated with prune and self-heal | Same rules as the hand-written one |

Look at what it produced:

```bash
kubectl -n argocd get applicationset hello-kustomize
kubectl -n argocd get applications.argoproj.io | grep hello-kustomize
```

You wrote no Application for `dev` or `prod`. The controller made them.

### Add an environment by adding a folder

This step pushes to Git, so run it in your fork.

```bash
cd $REPO/examples/argocd-apps/workloads/hello-kustomize/overlays
cp -r dev staging
sed -i 's/hello-dev/hello-staging/g' staging/kustomization.yaml
git add -A && git commit -m "lab 2: add staging overlay" && git push
```

The controller polls Git every three minutes. To not wait, ask it to look now:

```bash
kubectl -n argocd annotate applicationset hello-kustomize argocd.argoproj.io/application-set-refresh=true --overwrite
kubectl -n argocd get applications.argoproj.io -w
```

```text
NAME                      SYNC STATUS   HEALTH STATUS
hello-kustomize-dev       Synced        Healthy
hello-kustomize-prod      Synced        Healthy
hello-kustomize-staging   Synced        Healthy
```

In the test run the new Application was `Synced` and `Healthy` about 15 seconds after the refresh. A third environment
now exists, and you only added a folder. Open it:

```bash
hello hello-staging
```

### Remove it by removing the folder

```bash
cd $REPO/examples/argocd-apps/workloads/hello-kustomize/overlays
git rm -r staging
git commit -m "lab 2: remove staging overlay" && git push
kubectl -n argocd annotate applicationset hello-kustomize argocd.argoproj.io/application-set-refresh=true --overwrite
kubectl -n argocd get applications.argoproj.io | grep hello-kustomize
```

`hello-kustomize-staging` disappears in about five seconds, and its Deployment, Service and Ingress go with it (the
Application has the `resources-finalizer`). The namespace does not:

```bash
kubectl get ns hello-staging       # still Active, now empty
kubectl delete ns hello-staging
```

> [!NOTE]
>
> A namespace created by `CreateNamespace=true` is not owned by the application, so removing the application leaves
> it behind. Clean it up yourself, or manage the Namespace as a resource in Git.

## Break it: edit a generated Application

An Application made by an ApplicationSet belongs to its template. Remove its sync policy by hand:

```bash
kubectl -n argocd patch application hello-kustomize-dev --type merge -p '{"spec":{"syncPolicy":null}}'
kubectl -n argocd get application hello-kustomize-dev -o jsonpath='{.spec.syncPolicy}{"\n"}'
```

```text
{"automated":{"prune":true,"selfHeal":true},"syncOptions":["CreateNamespace=true"]}
```

The ApplicationSet controller restored it within four seconds. To change every generated Application, change the
**template** in Git.

## Which one do I use?

| Situation | Use |
|-----------|-----|
| One service, one place | `Application` |
| A platform component such as cert-manager, installed once | `Application` |
| The same app in dev, staging and prod | `ApplicationSet` with a `git` directory generator |
| The same app on many clusters | `ApplicationSet` with a `cluster` generator |
| One preview environment per pull request | `ApplicationSet` with a `pullRequest` generator |
| Environment x cluster combinations | `ApplicationSet` with a `matrix` generator |

The old README (kept in [`archives/README-v1.md`](https://github.com/Xeus-Territory/kubewekend/blob/main/examples/argocd-apps/archives/README-v1.md)) has a worked example of every generator.

## Self-check

- Which object do you edit to give **every** environment a new label: the generated Application or the template?
- Why did removing the folder remove the Application, but not the namespace?
- You need `hello-helm` in three environments. What do you change in the Helm case, and how is that different from the
  Kustomize case?

## Cleanup

Nothing to remove if you keep the cluster for [Lab 03](../03-image-updater/README.md). If you added the `staging` folder
and did not remove it, remove it now (see above).

Next: [Lab 03: Image Updater](../03-image-updater/README.md).
