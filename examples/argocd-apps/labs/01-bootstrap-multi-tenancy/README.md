# Lab 01: Bootstrap and multi-tenancy

**Goal:** build a whole cluster from **one manifest**, in a defined order, and fence each group of applications into an
`AppProject` so a team can only deploy what it is allowed to, where it is allowed to.

Suggested time: 1 to 1.5 hours. Needs the cluster from [00 Platform](../00-platform/README.md).

## Concepts

- **App of Apps.** One `Application` (the root) points at a folder of other `Application` manifests. Applying the root
  creates them all. You apply one file by hand; everything else comes from Git.
- **Sync waves.** The annotation `argocd.argoproj.io/sync-wave` orders the objects of one sync: lower numbers first,
  and Argo CD waits for a wave to be healthy before it starts the next. Here: projects `-1`, Argo CD itself `0`,
  platform `1`, apps `2`.
- **Self-management.** The `argocd` Application points at the same Helm chart you install by hand in step 1, so after
  the first sync Argo CD upgrades itself from Git.
- **`AppProject`.** A tenant boundary. It limits which Git repositories an Application may read, which clusters and
  namespaces it may deploy to, which kinds of objects it may create, and who may sync it.

## What the root app creates

```text
app-of-apps.yaml                  (project: default, applied by hand)
└── app-of-apps/                  (read recursively)
    ├── projects/        wave -1  AppProjects: infrastructure, platform, apps
    ├── infrastructure/  wave  0  Application: argocd          (project infrastructure)
    ├── platform/        wave  1  Application: cert-manager    (project platform)
    └── apps/            wave  2  Application: hello-helm, ApplicationSet: hello-kustomize   (project apps)
```

## Steps

**1. Install Argo CD once, by hand.**

The chart in [`manifests/infrastructure/argocd`](https://github.com/Xeus-Territory/kubewekend/tree/main/examples/argocd-apps/manifests/infrastructure/argocd) wraps `argo-cd` and
`argocd-image-updater`. Its values set a local admin and a read-only account, turn on Exec, and add a health check for
`Application` objects (explained in [Design notes](#design-notes-three-things-the-first-run-taught-me)).

```bash
cd $REPO/examples/argocd-apps/manifests/infrastructure/argocd
helm dependency update .
helm upgrade --install argocd . --namespace argocd --create-namespace --wait
kubectl -n argocd get pods
```

```text
NAME                                                READY   STATUS      RESTARTS   AGE
argocd-application-controller-0                     1/1     Running     0          47s
argocd-applicationset-controller-6cbf6486b4-dks7b   1/1     Running     0          47s
argocd-image-updater-controller-68f7f578cd-8gzpj    1/1     Running     0          47s
argocd-notifications-controller-6cd6f79b96-nw2k5    1/1     Running     0          47s
argocd-redis-b794c4777-2tshb                        1/1     Running     0          47s
argocd-redis-secret-init-9j9hl                      0/1     Completed   0          61s
argocd-repo-server-b445df69d-x7fr2                  1/1     Running     0          47s
argocd-server-5c7996c8d7-q7zdl                      1/1     Running     0          47s
```

> [!NOTE]
>
> The labs use `kubectl` and never need the web UI. If you want it: the Argo CD ingress host is
> `argocd.kubewekend.local` (point it at `$INGRESS_IP` in `/etc/hosts`), the user is `admin` and the password comes from
> `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`.

**2. Apply the root application.**

```bash
cd $REPO/examples/argocd-apps
kubectl apply -f app-of-apps.yaml
kubectl -n argocd get applications.argoproj.io -w
```

Press Ctrl-C when all six are `Synced` and `Healthy`. Because of the waves, the platform application appears and turns
healthy **before** the workload applications are created:

```text
NAME                   SYNC STATUS   HEALTH STATUS
app-of-apps            Synced        Healthy
argocd                 Synced        Healthy
cert-manager           Synced        Healthy
hello-helm             Synced        Healthy
hello-kustomize-dev    Synced        Healthy
hello-kustomize-prod   Synced        Healthy
```

**3. Check the workloads.**

```bash
kubectl get pods -A -l 'app.kubernetes.io/name in (common,hello-kustomize)'
hello hello-helm
hello hello-dev
hello hello-prod
```

```text
NAMESPACE    NAME                               READY   STATUS    RESTARTS   AGE
hello-dev    hello-kustomize-559b4649d9-tk6jj   1/1     Running   0          3m18s
hello-helm   hello-helm-75dc8959fd-8dn6x        1/1     Running   0          3m16s
hello-prod   hello-kustomize-559b4649d9-qzclj   1/1     Running   0          3m18s
hello-prod   hello-kustomize-559b4649d9-rq7tx   1/1     Running   0          3m18s

{"version":"v1.0.0","message":"Hello from Kubewekend","hostname":"hello-helm-75dc8959fd-8dn6x"}
{"version":"v1.0.0","message":"Hello from Kubewekend","hostname":"hello-kustomize-559b4649d9-tk6jj"}
{"version":"v1.0.0","message":"Hello from Kubewekend","hostname":"hello-kustomize-559b4649d9-qzclj"}
```

`prod` runs two replicas because its overlay patches the replica count. (`hello` is the helper from lab 00.)

## The three AppProjects

| | `infrastructure` | `platform` | `apps` |
|---|------------------|-----------|--------|
| Who | Whoever runs the cluster | Platform engineers | Application teams |
| Git sources | Any | This repository and the cert-manager, Grafana and Prometheus chart repositories | This repository only |
| Destinations | Any cluster, any namespace | Any namespace except `kube-system` | In-cluster, any namespace **except** `kube-system`, `argocd`, `monitoring`, `logging`, `cert-manager`, `traefik` |
| Cluster-wide objects | Anything | A short list: Namespace, PersistentVolume, ClusterRole and binding, CRD, StorageClass, IngressClass, webhooks, ClusterIssuer | **Namespace only** |
| Namespaced objects | Anything | Anything | An allow-list: Deployment, StatefulSet, DaemonSet, Service, ConfigMap, Secret, ServiceAccount, PVC, Ingress, NetworkPolicy, HPA, PDB, Job, CronJob, Pod, ReplicaSet |
| Roles | `infra-admin`, `viewer` | `platform-engineer`, `viewer` | `developer`, `viewer` |

The files are in [`app-of-apps/projects`](https://github.com/Xeus-Territory/kubewekend/tree/main/examples/argocd-apps/app-of-apps/projects).

## Break it

Each experiment is an `Application` in project `apps` that asks for something the project forbids. They live in
[`break-it/`](break-it), outside `app-of-apps/`, so the root application never creates them.

**1. Deploy into a forbidden namespace.**

```bash
cd $REPO/examples/argocd-apps/labs/01-bootstrap-multi-tenancy/break-it
kubectl apply -f deny-namespace.yaml
kubectl -n argocd get application break-namespace -o jsonpath='{range .status.conditions[*]}{.type}: {.message}{"\n"}{end}'
```

```text
InvalidSpecError: application destination server 'https://kubernetes.default.svc' and namespace 'kube-system' do not match any of the allowed destinations in project 'apps'
```

**2. Ship a cluster-wide object.**

```bash
kubectl apply -f deny-clusterrole.yaml
kubectl -n argocd get application break-clusterrole -o yaml | grep -o 'resource .* is not permitted in project apps' | sort -u
kubectl get clusterrole lab-break-it
```

```text
resource rbac.authorization.k8s.io:ClusterRole is not permitted in project apps
Error from server (NotFound): clusterroles.rbac.authorization.k8s.io "lab-break-it" not found
```

The sync fails and the ClusterRole never reaches the cluster. Clean up:

```bash
kubectl -n argocd delete application break-namespace break-clusterrole
```

**3. Who may sync?** The Argo CD values define two local accounts and map them to the built-in roles. Ask Argo CD what
each may do, without logging in:

```bash
for who in kubewekend-admin kubewekend-reader; do
  for action in get sync delete; do
    printf '%-18s %-7s ' "$who" "$action"
    argocd admin settings rbac can "$who" "$action" applications 'apps/hello-helm' --namespace argocd
  done
done
```

```text
kubewekend-admin   get     Yes
kubewekend-admin   sync    Yes
kubewekend-admin   delete  Yes
kubewekend-reader  get     Yes
kubewekend-reader  sync    No
kubewekend-reader  delete  No
```

The reader can also read logs but cannot open a shell (`create exec` is `No`).

## Design notes: three things the first run taught me

These are already fixed in the repository. They are here because they are what multi-tenancy looks like in practice.

1. **The `apps` project must allow `Namespace`.** The first version blocked every cluster-wide kind. Every workload
   application then failed with `resource :Namespace is not permitted in project apps`, because
   `CreateNamespace=true` creates a Namespace. The project now allows that one kind and nothing else.
2. **cert-manager wanted `kube-system`.** Its chart puts leader-election Roles there, and the `platform` project
   denies that namespace: `namespace kube-system is not permitted in project 'platform'`. The fix is in the chart
   values (`global.leaderElection.namespace: cert-manager`), not in the project: the guard rail stays.
3. **Waves ignore child Applications unless Argo CD can read their health.** Without a health check, an `Application`
   counts as healthy the moment it exists, so the workloads were created two seconds after cert-manager, while it was
   still failing. With the check in the Argo CD values, deleting `cert-manager` and `hello-helm` and letting the root
   app heal them gave:

   ```text
   t+6s   cert-manager created      (OutOfSync/Missing)
   t+13s  cert-manager Healthy
   t+13s  hello-helm created        (cert-manager was: Synced/Healthy)
   t+29s  both Synced/Healthy
   ```

> [!TIP]
>
> A failed sync keeps retrying **with the revision it started with**. After you fix Git, an app that is already
> retrying (`Retrying attempt #5`) picks the new revision only when its retries end, about a minute in this lab. To skip
> the wait: `argocd app terminate-op <name>`.

## Self-check

- Why does the root application use project `default`, while every child uses its own project?
- Which of the three projects would you give to a team that only deploys web apps, and what would they be unable to do?
- What happens to `hello-helm` if cert-manager is unhealthy? What happens without the health check?
- A developer needs a new `ClusterRole` for their app. Which project should own it, and who reviews that change?

## Cleanup

Keep the cluster for the next labs. To remove everything, delete it:

```bash
kind delete cluster --name gitops
```

> [!WARNING]
>
> Do not delete the root application to "undo" the lab. It cascades to the `argocd` application, which would try to
> delete Argo CD itself. Delete the cluster instead.

Next: [Lab 02: Application vs ApplicationSet](../02-application-vs-applicationset/README.md).
