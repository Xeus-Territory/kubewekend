# 00 Platform: Kind, load balancer and Istio

Prepare the cluster that labs 01 to 03 run on (lab 04 builds its own two clusters). The labs assume a plain
Kubernetes cluster: **no ingress controller**, because the Istio gateways need ports 80 and 443.

## What the labs need from Kind

| Need | Why | How it is met here |
|------|-----|--------------------|
| No ingress controller | The Istio gateways own ports 80 / 443 | Use a Kind cluster without Traefik or NGINX |
| LoadBalancer addresses | Istio gateways are `LoadBalancer` Services | [cloud-provider-kind](https://github.com/kubernetes-sigs/cloud-provider-kind) (one process serves every Kind cluster) |
| A CNI that enforces NetworkPolicy | Lab 02 (ambient and port 15008) and lab 03 (egress lockdown) | Kind's default `kindnet` enforces it (checked in the test run) |
| Gateway API CRDs | Gateways, waypoints and routes are Gateway API objects | Installed by cloud-provider-kind, or by the command below |
| Resources | 1 control plane + 2 workers, Istio, a few small apps | About 4 CPU and 8 GB RAM free on the host |

> [!NOTE]
>
> Everything in this folder was run end to end on Kind v0.33.0 (node image `kindest/node:v1.36.4`, the versions
> pinned in Kubewekend's [Versions](../../../docs/reference/versions.md) page), cloud-provider-kind v0.12.0 and
> Istio 1.32.0. Command outputs shown in the labs come from that run; names and IPs will differ in yours.

## 1. Create the cluster

`kind-mesh.yaml` creates a 3-node cluster named `mesh` (context `kind-mesh`). If you already have a Kind cluster
without an ingress controller, you can use it instead and skip this step.

```bash
kind create cluster --config kind-mesh.yaml
kubectl get nodes
```

Expected: `mesh-control-plane`, `mesh-worker` and `mesh-worker2`, all `Ready`. Add `--image kindest/node:v1.36.4` to
use the node image Kubewekend pins.

## 2. LoadBalancer addresses

Download cloud-provider-kind from its [releases page](https://github.com/kubernetes-sigs/cloud-provider-kind/releases)
(v0.12.0 was tested) and leave it running in its own terminal:

```bash
cloud-provider-kind
```

On Linux the addresses it hands out (for example `172.18.0.5`) live on the `kind` Docker network and are reachable
from the host. On macOS and Windows they are not: use `kubectl port-forward` to reach a gateway from your machine.

## 3. Gateway API CRDs

cloud-provider-kind installs the Gateway API CRDs when it starts (version `v1.6.1`, standard channel, in the test
run). Check, and install them only if they are missing:

```bash
kubectl get crd gateways.gateway.networking.k8s.io
# only if the command above reports "not found":
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.3/standard-install.yaml
```

cloud-provider-kind also registers a `GatewayClass` named `cloud-provider-kind`. It does not interfere: every Gateway in
these labs sets `gatewayClassName: istio` or `istio-waypoint`.

## 4. Install Istio (ambient profile)

Download the Istio release (it contains `istioctl`, plus the `samples/` and `tools/` folders lab 04 uses):

```bash
export ISTIO_VERSION=1.32.0
curl -L https://github.com/istio/istio/releases/download/$ISTIO_VERSION/istio-$ISTIO_VERSION-linux-amd64.tar.gz | tar xz -C ~
export ISTIO_DIR=~/istio-$ISTIO_VERSION
export PATH=$ISTIO_DIR/bin:$PATH
istioctl version --remote=false          # client version: 1.32.0
```

(For macOS or ARM, take the matching file from the [Istio releases](https://github.com/istio/istio/releases).)

The **ambient profile** installs istiod (the control plane), the Istio CNI plugin and ztunnel (the per-node
proxy). Sidecar injection still works in the same mesh, which is what labs 01 to 03 use side by side:

```bash
istioctl install --set profile=ambient --skip-confirmation
kubectl get pods -n istio-system -o wide
kubectl get gatewayclass
istioctl version
```

Expected:

```text
istio-cni-node-xxxxx     1/1   Running   (one per node)
istiod-xxxxxxxxxx-xxxxx  1/1   Running
ztunnel-xxxxx            1/1   Running   (one per node)

NAME                  CONTROLLER                            ACCEPTED
cloud-provider-kind   kind.sigs.k8s.io/gateway-controller   True
istio                 istio.io/gateway-controller           True
istio-remote          istio.io/unmanaged-gateway            True
istio-waypoint        istio.io/mesh-controller              True

client version: 1.32.0
control plane version: 1.32.0
data plane version: 1.32.0 (3 proxies)
```

## 5. Metrics for `kubectl top` (optional)

Lab 01 compares the memory of sidecars and ztunnel with `kubectl top`, which needs metrics-server. On Kind it must
accept the kubelets' self-signed certificates:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl -n kube-system patch deploy metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
kubectl -n kube-system rollout status deploy/metrics-server
```

## 6. Sample apps

The apps are the repository's [`common` Helm chart](https://github.com/Xeus-Territory/kubewekend/tree/main/kubernetes/charts/common) with the values files in
[`../apps`](../apps), installed with one script:

```bash
../apps/deploy.sh <namespace> <app> [<app> ...]       # creates the namespace if needed
```

| App | What it is | Used for |
|-----|-----------|----------|
| `curl`, `curl-other` | Client Pods that sleep (two identities: ServiceAccounts `curl` and `curl-other`) | Sending requests; showing that policies decide by caller |
| `httpbin` | HTTP echo server on 8080: `/get`, `/headers`, `/status/<code>`, `/delay/<s>` | Target of requests, mTLS and policy tests |
| `helloworld-v1`, `helloworld-v2` | Istio's sample app, answers `Hello version: vN` on 5000 | Canary routing, failover, multi-cluster |
| `fortio` | Load generator | Circuit breaking |

The labs also use a few small shell helpers (`call`, `codes`, `versions`). Load them from inside a lab folder:

```bash
source ../apps/helpers.sh
```

## Conventions used in every lab

- **Run commands from the lab's folder**, so `-f file.yaml` and `../apps/...` resolve.
- **The `common` chart names the app container `common`**, so `kubectl exec` in a sidecar namespace needs
  `-c common` (the helpers do this for you).
- **Policy changes take a few seconds to reach the proxies** (up to 10 to 15 seconds in the test run). If a result
  looks wrong, wait and repeat before debugging.
- **Each lab starts by creating what it needs and ends with a Cleanup step**, so labs can be run in any order.

## Cleanup

Remove the cluster when you are done with labs 01 to 03:

```bash
kind delete cluster --name mesh
```

Stop cloud-provider-kind (Ctrl+C in its terminal) when no Kind cluster needs LoadBalancer addresses.

Next: [01 Sidecar vs Ambient](../01-sidecar-vs-ambient/README.md).
