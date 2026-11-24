# Lab 00: Platform

**Goal:** a one-node Kind cluster with an ingress controller, ready for labs 1 to 3.

Suggested time: 20 minutes.

## What you need

| Need | Why | How |
|------|-----|-----|
| Docker, Kind v0.33, kubectl, Helm 3 | The cluster and the tools | [Kind quick start](https://kind.sigs.k8s.io/docs/user/quick-start/) |
| Load balancer addresses | Traefik is a `LoadBalancer` Service | [cloud-provider-kind](https://github.com/kubernetes-sigs/cloud-provider-kind) (one process serves every Kind cluster) |
| An ingress controller | The hello apps are reached through Ingress | Traefik, installed below (Kubewekend clusters normally already have it) |
| Resources | One node, Argo CD and four small apps | About 2 CPUs and 4 GB of memory |

> [!NOTE]
>
> **Do not touch your own clusters.** The commands use a Kind cluster named `gitops`. Check `kubectl config
> current-context` before running anything, and use `--context kind-gitops` if you work with several clusters.

## Steps

**1. Create the cluster.**

All the labs use `$REPO`, the root of your clone of this repository, so every command works from any directory:

```bash
export REPO=$(git rev-parse --show-toplevel)
kind create cluster --config $REPO/examples/argocd-apps/labs/00-platform/kind-gitops.yaml
kubectl cluster-info --context kind-gitops
```

[`kind-gitops.yaml`](kind-gitops.yaml) is a single control-plane node on `kindest/node:v1.36.4`.

**2. Give Services of type LoadBalancer an address.**

Download cloud-provider-kind from its releases page, then run it in a separate terminal and leave it running:

```bash
cloud-provider-kind
```

**3. Install Traefik.**

Skip this step on a Kubewekend cluster that already has Traefik (check with `kubectl get ingressclass`).

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update traefik
helm upgrade --install traefik traefik/traefik --version 42.0.0 \
  --namespace traefik --create-namespace --wait
kubectl -n traefik get svc traefik
```

```text
NAME      TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)                      AGE
traefik   LoadBalancer   10.96.34.141   172.18.0.5    80:30346/TCP,443:32253/TCP   20s
```

The `EXTERNAL-IP` is the address of the ingress. Save it in a variable:

```bash
export INGRESS_IP=$(kubectl -n traefik get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo $INGRESS_IP
```

**4. Reach an app by host name without editing `/etc/hosts`.**

The apps use host names such as `hello-helm.kubewekend.local`. `curl --resolve` maps a name to the ingress address for one
command. This helper wraps it:

```bash
hello() { curl -s --resolve "$1.kubewekend.local:80:$INGRESS_IP" "http://$1.kubewekend.local/version"; echo; }
```

You will use it as `hello hello-helm`, `hello hello-dev` and `hello hello-prod`. (To use a browser instead, add the names
to `/etc/hosts`, pointing at `$INGRESS_IP`.)

## Using your own fork (needed for one step in lab 2)

Labs 1 and 2 work as they are: the Applications read this repository on GitHub. A few steps **push a commit** (adding an
overlay in lab 2 and, if you repeat it, lab 3). For those you need a fork, and every manifest has to point at it:

```bash
cd $REPO/examples/argocd-apps
FORK=https://github.com/<you>/kubewekend
grep -rlE --include='*.yaml' 'github.com/Xeus-Territory/kubewekend' app-of-apps.yaml app-of-apps manifests labs \
  | xargs sed -i "s|https://github.com/Xeus-Territory/kubewekend|$FORK|g"
git add -A && git commit -m "point the Argo CD labs at my fork" && git push
```

Argo CD reads the **pushed** copy, so push before you apply anything. Keep the repository public, so Argo CD needs no
credentials for it.

## Verify

```bash
kubectl get nodes
kubectl -n traefik get pods
hello hello-helm
```

There is no app yet, so Traefik answers `404 page not found`. That answer is what you want: it proves the ingress is
reachable through `$INGRESS_IP`.

## Cleanup

```bash
kind delete cluster --name gitops
```

Next: [Lab 01: Bootstrap and multi-tenancy](../01-bootstrap-multi-tenancy/README.md).
