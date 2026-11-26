# Lab 01: Sidecar vs Ambient

**Goal:** see how Istio's two data planes work in practice, what each one gives you, and what changes when you
move an application from one to the other.

Suggested time: 1 to 1.5 days. Needs the cluster from [00 Platform](../00-platform/README.md).

## Concepts

| | Sidecar mode | Ambient mode |
|---|---|---|
| Where the proxy runs | An Envoy container **inside every Pod** (`istio-proxy`) | **ztunnel**, one per node, shared by all Pods on it |
| What it handles | L4 and L7: mTLS, routing, retries, HTTP metrics, L7 policy | **L4 only**: mTLS, L4 policy, TCP metrics |
| L7 features | Always available | Opt in per namespace or per Service with a **waypoint** (an Envoy Deployment) |
| Tunnel between nodes | mTLS | HBONE (HTTP/2 CONNECT over mTLS, port 15008) |
| Enrolling a namespace | Label `istio-injection=enabled`, restart Pods | Label `istio.io/dataplane-mode=ambient`, Pods are not touched |
| Cost | A proxy per Pod (CPU, memory, startup order) | One small proxy per node; Envoy only where you ask for L7 |

## Steps

### 1. Prepare two namespaces with the same app

```bash
cd examples/istio-case-studies/01-sidecar-vs-ambient
kubectl apply -f namespaces.yaml
../apps/deploy.sh lab-sidecar curl httpbin
../apps/deploy.sh lab-ambient curl httpbin
```

### 2. Compare the Pods

```bash
kubectl get pods -n lab-sidecar
kubectl get pods -n lab-ambient
```

Expected: `2/2` Running in `lab-sidecar` (app + `istio-proxy`) and `1/1` Running in `lab-ambient`.

Where is the sidecar? In Istio 1.32 on a recent Kubernetes it is a **native sidecar**: an init container that keeps
running, so it starts before the app and is stopped after it:

```bash
kubectl get pod -n lab-sidecar -l app=httpbin \
  -o jsonpath='{.items[0].spec.initContainers[*].name}{"\n"}{.items[0].spec.containers[*].name}{"\n"}'
```

```text
istio-validation istio-proxy
common
```

### 3. Compare what the control plane sees

```bash
istioctl proxy-status
istioctl ztunnel-config workloads | grep -E 'NAMESPACE|lab-'
```

- `proxy-status` lists **one proxy per sidecar Pod** (`curl-…lab-sidecar`, `httpbin-…lab-sidecar`) and the three
  ztunnels. The ambient Pods are not in it: they have no proxy of their own.
- `ztunnel-config workloads` lists every workload ztunnel knows about (here all four Pods, protocol `HBONE`).
  The `WAYPOINT` column is `None` until a waypoint serves them (step 6).

### 4. Send traffic, then compare the metrics

Calls work the same way in both namespaces:

```bash
kubectl -n lab-sidecar exec deploy/curl -c common -- curl -s http://httpbin:8080/get
kubectl -n lab-ambient exec deploy/curl -- curl -s http://httpbin:8080/get
for i in $(seq 1 30); do
  kubectl -n lab-sidecar exec deploy/curl -c common -- curl -s -o /dev/null http://httpbin:8080/get
  kubectl -n lab-ambient exec deploy/curl -- curl -s -o /dev/null http://httpbin:8080/get
done
```

**Sidecar: HTTP (L7) metrics from the Envoy in the httpbin Pod**:

```bash
kubectl -n lab-sidecar exec deploy/httpbin -c istio-proxy -- pilot-agent request GET stats/prometheus \
  | grep '^istio_requests_total' \
  | grep -o 'reporter="[a-z]*"\|response_code="[0-9]*"\|connection_security_policy="[a-z_]*"\|} [0-9]*$' | paste -sd' '
```

You get `istio_requests_total` with the HTTP `response_code` and `connection_security_policy="mutual_tls"`.

**Ambient: ztunnel only sees TCP**. Read its metrics from the ztunnel on the node that runs httpbin:

```bash
NODE=$(kubectl -n lab-ambient get pod -l app=httpbin -o jsonpath='{.items[0].spec.nodeName}')
ZT=$(kubectl -n istio-system get pod -l app=ztunnel --field-selector spec.nodeName=$NODE -o jsonpath='{.items[0].status.podIP}')
kubectl -n lab-ambient exec deploy/curl -- curl -s http://$ZT:15020/metrics > /tmp/ztunnel-metrics.txt
grep -c '^istio_requests_total' /tmp/ztunnel-metrics.txt                   # 0: no HTTP metrics at L4
grep -c '^istio_tcp_connections_opened_total' /tmp/ztunnel-metrics.txt     # more than 0: TCP connections are counted
```

The TCP series still carry `connection_security_policy="mutual_tls"` and the caller and callee identities: ambient
gives you encryption and identity without any proxy in the Pods, but no HTTP visibility.

### 5. Compare the memory

Needs metrics-server (see [00 Platform](../00-platform/README.md), step 5). Wait about a minute after the traffic,
then:

```bash
kubectl top pods -A --containers | grep -E 'NAMESPACE|lab-|ztunnel|istiod|istio-cni'
```

Memory in the test run:

| Container | Memory |
|-----------|--------|
| `istio-proxy` sidecar in `curl` (lab-sidecar) | 28 MiB |
| `istio-proxy` sidecar in `httpbin` (lab-sidecar) | 29 MiB |
| app containers (`common`), either namespace | 0 to 2 MiB |
| `ztunnel`, one per node, serves every ambient Pod on its node | 4 to 6 MiB |
| `istiod` | 48 MiB |

Two Pods cost about 57 MiB of sidecar memory; ambient costs a fixed few MiB per node no matter how many Pods. The
gap grows with the number of Pods.

### 6. Add a waypoint: L7 in ambient

An L7 rule cannot be applied in `lab-ambient` yet. Try one, an HTTPRoute that adds a request header on the way to
httpbin. It is attached to the Service (mesh routing with the Gateway API):

```bash
kubectl apply -f httproute-add-header.yaml
kubectl -n lab-ambient exec deploy/curl -- curl -s http://httpbin:8080/headers | grep -ci 'x-added-by'    # 0
kubectl delete -f httproute-add-header.yaml
```

The route exists, but nothing enforces it: ztunnel only handles L4. Now create a **waypoint** for the namespace and
enrol the namespace in it:

```bash
istioctl waypoint apply -n lab-ambient --enroll-namespace --wait
kubectl get gateway -n lab-ambient
kubectl get pods -n lab-ambient
kubectl get ns lab-ambient --show-labels
```

You get a `Gateway` named `waypoint` (class `istio-waypoint`), a new `waypoint-…` Pod (the Envoy), and the label
`istio.io/use-waypoint=waypoint` on the namespace. Apply the route again:

```bash
kubectl apply -f httproute-add-header.yaml
sleep 5
kubectl -n lab-ambient exec deploy/curl -- curl -s http://httpbin:8080/headers
```

The response now contains `"X-Added-By": ["waypoint"]`: the waypoint applied the L7 rule. It also reports HTTP metrics
(`reporter="waypoint"`):

```bash
for i in $(seq 1 10); do kubectl -n lab-ambient exec deploy/curl -- curl -s -o /dev/null http://httpbin:8080/get; done
WP=$(kubectl -n lab-ambient get pod -l gateway.networking.k8s.io/gateway-name=waypoint -o jsonpath='{.items[0].status.podIP}')
kubectl -n lab-ambient exec deploy/curl -- curl -s http://$WP:15020/stats/prometheus \
  | grep '^istio_requests_total' \
  | grep -o 'reporter="[a-z]*"\|response_code="[0-9]*"\|connection_security_policy="[a-z_]*"\|} [0-9]*$' | paste -sd' '
```

Expected: `reporter="waypoint" response_code="200" connection_security_policy="mutual_tls" } 11` (or more).

**Waypoint scope.** A waypoint can serve one Service instead of the whole namespace. A label on the Service wins
over the label on the namespace:

```bash
istioctl waypoint apply -n lab-ambient --name httpbin-waypoint --wait
kubectl label svc httpbin -n lab-ambient istio.io/use-waypoint=httpbin-waypoint
sleep 5
istioctl ztunnel-config services | grep -E 'NAMESPACE|lab-ambient'
```

The `WAYPOINT` column for `httpbin` now says `httpbin-waypoint`, and the header route (attached to the Service) is
applied by that waypoint. Undo it:

```bash
kubectl label svc httpbin -n lab-ambient istio.io/use-waypoint-
istioctl waypoint delete -n lab-ambient httpbin-waypoint
```

### 7. Pod lifecycle: Jobs and sidecars

Run the same one-shot Job in both namespaces:

```bash
kubectl -n lab-sidecar apply -f job-hello.yaml
kubectl -n lab-ambient apply -f job-hello.yaml
kubectl -n lab-sidecar wait --for=condition=complete job/hello-job --timeout=90s
kubectl -n lab-sidecar get job,pod -l job-name=hello-job
```

Both complete. In `lab-sidecar` the Pod shows `0/2 Completed`: the native sidecar is stopped when the app exits. That
is the 1.32 default. Now turn native sidecars **off** for one Pod to see what older Istio versions (or clusters without
sidecar containers) did:

```bash
kubectl -n lab-sidecar apply -f job-hello-legacy.yaml
sleep 40
kubectl -n lab-sidecar get job,pod -l job-name=hello-job-legacy
```

The Pod stays `NotReady` at `1/2` and the Job keeps `Running`: `istio-proxy` is a regular container that never exits.
Two ways out:

```bash
# manual: tell the proxy to quit
kubectl -n lab-sidecar exec job/hello-job-legacy -c istio-proxy -- pilot-agent request POST quitquitquit
# in the Job's own command: finish with  curl -X POST localhost:15020/quitquitquit
```

Startup order has the mirror-image problem: with a regular sidecar the app can start before the proxy is ready and
fail its first calls. The fix there is the annotation `proxy.istio.io/config: '{"holdApplicationUntilProxyStarts": true}'`;
native sidecars make it unnecessary.

```bash
kubectl -n lab-sidecar delete job hello-job hello-job-legacy
kubectl -n lab-ambient delete job hello-job
```

## Verify

| Check | Command | Expected |
|-------|---------|----------|
| Sidecar vs ambient Pods | `kubectl get pods -n lab-sidecar` / `-n lab-ambient` | `2/2` / `1/1` |
| Ambient has no proxy per Pod | `istioctl proxy-status` | Only sidecar Pods, waypoints and ztunnels are listed |
| ztunnel has no HTTP metrics | `grep -c '^istio_requests_total'` on ztunnel metrics | `0` |
| Waypoint adds L7 | `curl …/headers` before and after the waypoint | `X-Added-By` absent, then present |
| Service-level waypoint wins | `istioctl ztunnel-config services` | `httpbin` shows `httpbin-waypoint` |
| Native sidecar Job completes | `kubectl get job hello-job -n lab-sidecar` | `Complete 1/1`, Pod `0/2 Completed` |
| Legacy sidecar Job hangs | `kubectl get pod -l job-name=hello-job-legacy` | `NotReady 1/2` until `quitquitquit` |

## Break it

**Migrate `lab-sidecar` to ambient**, the way a team would move an application over:

```bash
kubectl label ns lab-sidecar istio-injection- istio.io/dataplane-mode=ambient
kubectl -n lab-sidecar rollout restart deploy
kubectl -n lab-sidecar rollout status deploy/httpbin deploy/curl
kubectl get pods -n lab-sidecar
istioctl proxy-status | grep -E 'NAME|lab-'
kubectl -n lab-sidecar exec deploy/curl -- curl -s -o /dev/null -w 'status=%{http_code}\n' http://httpbin:8080/get
```

Expected: the new Pods are `1/1`, the old sidecar Pods disappear from `proxy-status`, and calls still return
`status=200` (mTLS now comes from ztunnel). Before you run it, predict what you lose. Answer: everything that needed
an L7 proxy next to the Pod, that is HTTP metrics from the Pod's proxy, VirtualService rules, retries, L7
authorization. In ambient you get those back only by enrolling a waypoint, as in step 6. The call keeps working, and
that is the danger: a migration can silently drop L7 behaviour.

## Self-check

- What does ztunnel do on its own, and what can it not do?
- When do you need a waypoint, and what is the difference between a namespace waypoint and a Service waypoint?
- Why did the legacy Job never finish, and why does the native-sidecar one?
- What would you check before moving a production namespace from sidecar to ambient?

## Cleanup

```bash
kubectl delete -f namespaces.yaml
```

Deleting the namespaces also removes the waypoints and apps in them.

Next: [02 mTLS and Policies](../02-mtls-and-policies/README.md).
