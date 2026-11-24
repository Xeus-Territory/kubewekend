# Lab 03: Traffic Management with Ingress and Egress Gateways

**Goal:** control traffic coming into the mesh, moving between services, and leaving it: routing, canaries, TLS,
resilience, and an egress door that is actually closed.

Suggested time: 2 to 3 days. Needs the cluster from [00 Platform](../00-platform/README.md).

## Concepts

- **Ingress gateway:** an Envoy at the edge. With the Kubernetes **Gateway API** you describe it with a `Gateway`
  and attach routes with `HTTPRoute`; Istio creates the Envoy and its `LoadBalancer` Service for you.
- **Routing inside the mesh** (service to service) is done by the caller's sidecar, configured with the Istio
  `VirtualService` (routes, retries, timeouts, faults, mirroring) and `DestinationRule` (subsets, circuit breaking).
- **Resilience is configuration, not code:** timeouts, retries, circuit breaking and fault injection are applied by
  the proxy.
- **Egress control:** by default sidecars let traffic to any external host through. `REGISTRY_ONLY` closes that,
  a `ServiceEntry` opens one host, and an **egress gateway** makes it the single, auditable exit.
- **Ingress and egress here use sidecar mode.** Routing features that need L7 are always available in sidecar
  namespaces; in ambient they need a waypoint (lab 01).

## Steps

```bash
cd examples/istio-case-studies/03-ingress-egress-traffic
source ../apps/helpers.sh
kubectl apply -f namespaces.yaml
../apps/deploy.sh lab-traffic curl httpbin helloworld-v1 helloworld-v2 fortio
```

`lab-traffic` and `lab-egress` are sidecar-injected. `helloworld-v1` and `helloworld-v2` are two Deployments and two
Services whose Pods share the label `app=helloworld`.

### Part 1: the ingress gateway

**1. Create the gateway.**

```bash
kubectl apply -f gateway.yaml
kubectl -n lab-traffic wait --for=condition=Programmed gateway/lab-gateway --timeout=180s
kubectl -n lab-traffic rollout status deploy/lab-gateway-istio
kubectl -n lab-traffic get gateway lab-gateway
kubectl -n lab-traffic get svc,pods -l gateway.networking.k8s.io/gateway-name=lab-gateway
GW=$(kubectl -n lab-traffic get gateway lab-gateway -o jsonpath='{.status.addresses[0].value}')
echo $GW
```

Istio created a Deployment and a `LoadBalancer` Service named `lab-gateway-istio`; cloud-provider-kind gave it an
address (`172.18.0.5` in the test run). On macOS or Windows use
`kubectl -n lab-traffic port-forward svc/lab-gateway-istio 8080:80` and replace `http://$GW` with `http://localhost:8080`.

**2. Weighted canary.** Send 90% to v1 and 10% to v2, then count 100 requests:

```bash
kubectl apply -f httproute-canary.yaml
sleep 6
for i in $(seq 1 100); do curl -s -m 5 -H 'Host: hello.lab.test' "http://$GW/hello"; done | grep -o 'version: v[12]' | sort | uniq -c
```

About `90 v1 / 10 v2` (94 and 6 in the test run: it is random).

**3. Header-based canary.** Replace the route: only requests with `x-canary: true` reach v2.

```bash
kubectl apply -f httproute-header.yaml
sleep 6
curl -s -H 'Host: hello.lab.test' "http://$GW/hello"
curl -s -H 'Host: hello.lab.test' -H 'x-canary: true' "http://$GW/hello"
```

The first answers `Hello version: v1`, the second `Hello version: v2`.

**4. TLS at the gateway.** Create a self-signed certificate, store it as a Secret and add an HTTPS listener:

```bash
D=$(mktemp -d)
openssl req -x509 -newkey rsa:2048 -nodes -days 30 -keyout "$D/lab.key" -out "$D/lab.crt" \
  -subj "/CN=hello.lab.test" -addext "subjectAltName=DNS:hello.lab.test"
kubectl -n lab-traffic create secret tls lab-tls --cert="$D/lab.crt" --key="$D/lab.key"
kubectl apply -f gateway-tls.yaml
sleep 8
curl -s --resolve "hello.lab.test:443:$GW" --cacert "$D/lab.crt" https://hello.lab.test/hello
curl -sv --resolve "hello.lab.test:443:$GW" --cacert "$D/lab.crt" https://hello.lab.test/hello 2>&1 | grep -E 'subject:|SSL connection'
```

You get the answer over TLS 1.3 with `subject: CN=hello.lab.test`. The gateway terminates TLS and speaks mTLS to the
Pods behind it.

**5. Let the app publish itself.** The `common` chart can attach its own HTTPRoute to the gateway, so a team does not
write route YAML:

```bash
helm upgrade --install httpbin ../../../kubernetes/charts/common -n lab-traffic \
  -f ../apps/httpbin.values.yaml -f httpbin-route.values.yaml --wait
kubectl -n lab-traffic get httproute
sleep 6
curl -s -H 'Host: httpbin.lab.test' "http://$GW/get"
```

### Part 2: traffic inside the mesh

These rules are applied by the caller's sidecar, here the `curl` and `fortio` Pods in `lab-traffic`. First one Service
in front of both versions, and names for the versions:

```bash
kubectl apply -f service-helloworld.yaml -f destinationrule-helloworld.yaml
sleep 10
versions lab-traffic 40                      # no routing rule: round robin, about 20 / 20
```

**6. Weighted routing between services.** The same idea as the ingress canary, for service-to-service calls:

```bash
kubectl apply -f vs-weighted.yaml
sleep 10
versions lab-traffic 100                     # about 80 v1 / 20 v2 (79 / 21 in the test run)
```

**7. Fault injection.** Delay half of the requests by 3 seconds, as a slow dependency would:

```bash
kubectl apply -f vs-fault-delay.yaml
sleep 10
kubectl -n lab-traffic exec deploy/curl -c common -- sh -c \
  'for i in $(seq 1 20); do curl -s -o /dev/null -w "%{time_total}\n" http://helloworld:5000/hello; done' \
  | awk '{ if ($1 >= 3) slow++; else fast++ } END { print "slow(>=3s): " slow+0 "  fast: " fast+0 }'
```

About half are slow (12 of 20 in the test run). The injected delay happens before the route's timeout starts counting,
so a `timeout` does not cut it short: test timeouts against a really slow upstream instead.

**8. Timeouts.** httpbin's `/delay/3` answers after 3 seconds. Without a rule the caller waits; with a 2-second
timeout the caller's sidecar gives up:

```bash
kubectl apply -f vs-timeout-httpbin.yaml
sleep 10
kubectl -n lab-traffic exec deploy/curl -c common -- curl -s -w '\nhttp=%{http_code} time=%{time_total}s\n' -m 8 http://httpbin:8080/delay/3
kubectl -n lab-traffic exec deploy/curl -c common -- curl -s -w '\nhttp=%{http_code} time=%{time_total}s\n' -m 8 http://httpbin:8080/delay/1 | tail -1
```

The first returns `upstream request timeout`, `http=504` after `time=2.00s`; the second `http=200` after 1.0 s.

**9. Retries.** `/status/200,503` returns 200 or 503 at random. Without a rule about half of the calls fail; with
retries the sidecar tries again:

```bash
kubectl delete -f vs-timeout-httpbin.yaml
sleep 5
codes lab-traffic 60 http://httpbin:8080/status/200,503        # before
kubectl apply -f vs-retry-httpbin.yaml
sleep 10
codes lab-traffic 60 http://httpbin:8080/status/200,503        # with retries
```

Test run: before `25 × 200` and `35 × 503`; with retries `56 × 200` and `4 × 503`.

**10. Circuit breaking.** Allow almost no concurrency to helloworld, then push 8 parallel clients at it with fortio:

```bash
kubectl delete -f vs-fault-delay.yaml
kubectl apply -f vs-weighted.yaml -f dr-circuit-breaker.yaml
sleep 10
kubectl -n lab-traffic exec deploy/fortio -c common -- fortio load -c 8 -qps 0 -n 200 -quiet http://helloworld:5000/hello | grep '^Code'
kubectl -n lab-traffic exec deploy/fortio -c istio-proxy -- pilot-agent request GET stats/prometheus \
  | grep '^istio_requests_total' | grep 'destination_service_name="helloworld"' \
  | grep -o 'response_code="[0-9]*"\|response_flags="[A-Z-]*"\|} [0-9]*$' | paste -sd' ' | sed 's/ response_code/\nresponse_code/g'
```

Most requests are refused immediately: `Code 503` for about 74% in the test run. The metrics label them with the Envoy
response flag `UO` (upstream overflow): the proxy shed load instead of queueing it. Real requests still succeed
(`Code 200`).

**11. Traffic mirroring.** Send every request to v1 and a copy to v2, whose answer is discarded:

```bash
kubectl apply -f destinationrule-helloworld.yaml -f vs-mirror.yaml
sleep 10
v2count() { kubectl -n lab-traffic exec deploy/helloworld-v2 -c istio-proxy -- pilot-agent request GET stats/prometheus \
  | grep '^istio_requests_total' | grep 'reporter="destination"' | awk '{s+=$NF} END{print s+0}'; }
v2count
versions lab-traffic 20                      # all 20 answers come from v1
sleep 3
v2count                                      # 20 higher: v2 received a copy of every request
```

(helloworld does not log requests, so the count comes from v2's sidecar metrics.)

### Part 3: egress

`lab-egress` has two clients, `curl` and `curl-other` (two identities). The external site is `example.com`.

```bash
../apps/deploy.sh lab-egress curl curl-other
ext() { kubectl -n lab-egress exec "$@" -- curl -s -o /dev/null -m 8 -w '%{http_code}\n' http://example.com; }
ext deploy/curl -c common                    # 200: by default the mesh lets traffic out
```

**12. Close the door (`REGISTRY_ONLY`).**

```bash
kubectl apply -f egress-registry-only.yaml
sleep 14
ext deploy/curl -c common                    # 502: example.com is not in the mesh registry
```

**13. Open one host (`ServiceEntry`).**

```bash
kubectl apply -f egress-serviceentry.yaml
sleep 14
ext deploy/curl -c common                    # 200
```

**14. Make the egress gateway the exit.** Install the gateway, turn on its access log, and route `example.com` through it:

```bash
istioctl install -f egress-gateway-install.yaml --skip-confirmation
kubectl -n istio-system rollout status deploy/istio-egressgateway
kubectl apply -f egress-access-log.yaml -f egress-gateway-routing.yaml
sleep 14
ext deploy/curl -c common                    # 200
kubectl -n istio-system logs deploy/istio-egressgateway | grep '^\[' | tail -2 | cut -c1-260
```

The path is now `app --HTTP--> sidecar --mTLS--> egress gateway --HTTPS--> example.com`. The gateway's access log
shows `GET / HTTP/2 200 … "172.66.147.243:443" outbound|443||example.com`: the application sent plain HTTP to port 80,
and the **gateway originated TLS** to port 443 (TLS origination). The gateway also requires mutual TLS from the
sidecars (`tls.mode: ISTIO_MUTUAL` in `egress-gateway-routing.yaml`), which is what lets it know who is calling.

**15. Authorize who may leave.** Only the `curl` ServiceAccount may reach `example.com`:

```bash
kubectl apply -f egress-authz.yaml
sleep 14
ext deploy/curl -c common                    # 200
ext deploy/curl-other -c common              # 403
kubectl -n istio-system logs deploy/istio-egressgateway | grep '^\[' | tail -1 | cut -c1-200
```

`curl-other` gets `403`, and the gateway's log says `rbac_access_denied_matched_policy[none]`.

## Verify

| Step | Check | Expected |
|------|-------|----------|
| 2 | 100 requests to the canary route | About 90 v1 / 10 v2 |
| 3 | With and without `x-canary: true` | v1 / v2 |
| 4 | HTTPS request with `--cacert` | TLS 1.3, `CN=hello.lab.test`, `Hello version` |
| 6 | 100 in-mesh calls with `vs-weighted.yaml` | About 80 / 20 |
| 7 | 20 calls with a 50% 3-second delay | About 10 slow |
| 8 | `/delay/3` with a 2-second timeout | `504` after 2.0 s |
| 9 | `/status/200,503` before and after retries | About 40% fail, then about 7% |
| 10 | 8 parallel clients | `Code 503` for most, metrics flag `UO` |
| 11 | v2's received requests while all answers come from v1 | Grows by 20 |
| 12 / 13 | `example.com` with `REGISTRY_ONLY`, then with the ServiceEntry | `502`, `200` |
| 14 | Gateway access log | Upstream cluster for `example.com` on port 443 (TLS origination) |
| 15 | `curl` / `curl-other` | `200` / `403` |

## Break it

**The egress gateway is not a wall.** Run a Pod that opts out of the mesh. It has no sidecar, so `REGISTRY_ONLY`,
the ServiceEntry, the gateway and its policy do not apply to it:

```bash
kubectl apply -f bypass-pod.yaml
kubectl -n lab-egress wait --for=condition=Ready pod/bypass --timeout=90s
ext pod/bypass -c curl                       # 200: straight to the internet
```

Close it with a NetworkPolicy that only allows traffic to `istio-system` and DNS:

```bash
kubectl apply -f netpol-egress-lockdown.yaml
sleep 14
ext pod/bypass -c curl                       # exit code 28: timeout, the Pod can no longer reach the internet
ext deploy/curl -c common                    # 200: still works through the gateway
ext deploy/curl-other -c common              # 403: and is still denied
kubectl delete -f bypass-pod.yaml -f netpol-egress-lockdown.yaml
```

The lesson: mesh controls are enforced by proxies the workload could avoid; a NetworkPolicy (the network layer) is
what makes the gateway the **only** way out.

## Self-check

- Why did the first fortio result show `503` with `UO` instead of slow responses?
- Why does a `timeout` not shorten an injected delay, and how do you test a timeout instead?
- What identity does the egress gateway see, and what breaks the AuthorizationPolicy if the sidecar-to-gateway hop
  is not mutual TLS? (Try it: in `egress-gateway-routing.yaml` make the Gateway server a plain `protocol: HTTP` one
  without its `tls` block and drop the `tls` setting of the first DestinationRule, then turn on
  `istioctl proxy-config log <gateway-pod> -n istio-system --level rbac:debug`. The gateway logs `ssl: none` and
  denies even the allowed client: with no certificate there is no identity to match.)
- What makes egress control a security boundary, and what does not?

## Cleanup

```bash
kubectl delete -f egress-authz.yaml -f egress-access-log.yaml
kubectl delete -f namespaces.yaml
istioctl install --set profile=ambient --skip-confirmation       # removes the egress gateway
```

Re-applying the profile prunes the egress gateway, which is no longer part of it.

Next: [04 Multi-cluster, multi-network](../04-multicluster-multinetwork/README.md).
