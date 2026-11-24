# Lab 02: mTLS and Policies

**Goal:** prove which traffic is encrypted, who is allowed to call whom, and **where each rule is enforced**:
in the sidecar, in ztunnel (L4) or in a waypoint (L7).

Suggested time: 1.5 to 2 days. Needs the cluster from [00 Platform](../00-platform/README.md).

## Concepts

- **Mutual TLS (mTLS):** both sides present a certificate, so traffic is encrypted and each side knows who the
  other is. Istio issues the certificates and rotates them (24 hours here).
- **Identity:** a workload's identity is a SPIFFE ID built from its Kubernetes ServiceAccount:
  `spiffe://cluster.local/ns/<namespace>/sa/<serviceaccount>`. In policies it is written `principals:
  ["cluster.local/ns/<namespace>/sa/<serviceaccount>"]`.
- **`PeerAuthentication`** decides whether a workload accepts plain text (`PERMISSIVE`, the default) or only mTLS
  (`STRICT`).
- **`AuthorizationPolicy`** decides who may do what. An `ALLOW` policy with no rules allows nothing (deny-all);
  once any `ALLOW` policy applies to a workload, anything not allowed is denied.
- **Where it is enforced:** sidecar mode, the sidecar. Ambient mode: **ztunnel enforces L4** (identity, port) and a
  **waypoint enforces L7** (HTTP method, path, headers).

## Steps

Define a small helper that prints the HTTP status and curl's exit code of one request (exit `0` ok, `56` connection
reset by a policy, `28` timeout):

```bash
cd examples/istio-case-studies/02-mtls-and-policies
source ../apps/helpers.sh
```

Prepare three namespaces: `lab-sidecar` (sidecars), `lab-ambient` (ambient) and `legacy`, which is **not** in the mesh
and stands for a workload nobody has onboarded yet:

```bash
kubectl apply -f namespaces.yaml
../apps/deploy.sh lab-sidecar curl curl-other httpbin
../apps/deploy.sh legacy curl
../apps/deploy.sh lab-ambient curl curl-other httpbin
```

> [!NOTE]
>
> Policy changes take a few seconds to reach the proxies. After each `kubectl apply` below, wait 10 to 15 seconds
> before judging the result (the commands include a `sleep`).

### Part A: sidecar mode

**A1. PERMISSIVE (the default): the legacy caller works.**

```bash
call legacy curl http://httpbin.lab-sidecar:8080/get
```

`http=200`. By default Istio accepts plain text next to mTLS, so you can onboard workloads one at a time.

**A2. STRICT: the legacy caller is refused.**

```bash
kubectl apply -f strict-lab-sidecar.yaml
sleep 10
call legacy curl http://httpbin.lab-sidecar:8080/get      # refused
call lab-sidecar curl http://httpbin:8080/get             # mesh caller still works
```

The legacy call ends with `exit=56` (connection reset); the mesh call is `http=200`.

**A3. Prove it is mTLS.** httpbin echoes the request headers. The sidecar adds `X-Forwarded-Client-Cert` (XFCC) with
the caller's certificate identity:

```bash
kubectl -n lab-sidecar exec deploy/curl -c common -- curl -s http://httpbin:8080/headers | grep -i -A1 'forwarded-client-cert'
istioctl x describe pod "$(kubectl -n lab-sidecar get pod -l app=httpbin -o jsonpath='{.items[0].metadata.name}')" -n lab-sidecar
```

The header contains `URI=spiffe://cluster.local/ns/lab-sidecar/sa/curl`, the caller's identity. `describe` reports
`Workload mTLS mode: STRICT`.

**A4. Look at the certificate.**

```bash
istioctl proxy-config secret deploy/httpbin -n lab-sidecar
istioctl proxy-config secret deploy/httpbin -n lab-sidecar -o json \
  | jq -r '.dynamicActiveSecrets[] | select(.name=="default") | .secret.tlsCertificate.certificateChain.inlineBytes' | base64 -d \
  | openssl x509 -noout -text | grep -E 'URI:|Not Before|Not After'
```

You see two certificates (`default`, the workload certificate, and `ROOTCA`), the SPIFFE ID as a URI alternative name
(`URI:spiffe://cluster.local/ns/lab-sidecar/sa/httpbin`), and a lifetime of about 24 hours: Istio rotates it for you.

**A5. Authorization: deny everything, then allow one call.**

```bash
kubectl apply -f authz-sidecar-deny-all.yaml
sleep 15
kubectl -n lab-sidecar exec deploy/curl -c common -- curl -s http://httpbin:8080/get       # RBAC: access denied
kubectl apply -f authz-sidecar-allow-curl-get.yaml
sleep 15
call lab-sidecar curl http://httpbin:8080/get                    # allowed
call lab-sidecar curl http://httpbin:8080/headers                # other path
call lab-sidecar curl -X POST http://httpbin:8080/post           # other method
call lab-sidecar curl-other http://httpbin:8080/get              # other caller
```

### Part B: ambient mode (ztunnel enforces L4)

**B1. The same STRICT rule, enforced by ztunnel.** There is no sidecar in these Pods:

```bash
call legacy curl http://httpbin.lab-ambient:8080/get           # before: 200
kubectl apply -f strict-lab-ambient.yaml
sleep 15
call legacy curl http://httpbin.lab-ambient:8080/get           # refused
call lab-ambient curl http://httpbin:8080/get                  # works
```

**B2. L4 authorization: deny everything, allow `curl` on port 8080.**

```bash
kubectl apply -f authz-ambient-deny-all.yaml
sleep 15
call lab-ambient curl http://httpbin:8080/get                  # denied
kubectl apply -f authz-ambient-allow-curl-l4.yaml
sleep 15
call lab-ambient curl http://httpbin:8080/get                  # allowed
call lab-ambient curl-other http://httpbin:8080/get            # denied
```

The rule uses only identity and port, so ztunnel can enforce it alone.

### Part C: two traps with ambient

**C1. NetworkPolicy and the HBONE port 15008.** Between Pods, ambient traffic travels on the HBONE tunnel to port
**15008**, not to the application port. A NetworkPolicy that only allows port 8080 looks right and breaks the mesh:

```bash
kubectl apply -f netpol-httpbin-app-port-only.yaml
sleep 15
call lab-ambient curl http://httpbin:8080/get                  # still works!
```

Surprise: it still works. ztunnel keeps long-lived HBONE connections open, and a NetworkPolicy only filters **new**
connections. Use a fresh client to see the effect:

```bash
kubectl -n lab-ambient rollout restart deploy/curl
kubectl -n lab-ambient rollout status deploy/curl
sleep 5
call lab-ambient curl http://httpbin:8080/get                  # now blocked: exit=28 (timeout)
kubectl apply -f netpol-httpbin-allow-hbone.yaml               # also allow 15008
sleep 15
call lab-ambient curl http://httpbin:8080/get                  # works again
kubectl delete -f netpol-httpbin-allow-hbone.yaml
```

> [!TIP]
>
> NetworkPolicy changes can look harmless until the next Pod restart or connection reset. Always test them with a
> fresh client Pod.

**C2. An L7 rule enforced by ztunnel.** Remove the L4 allow and add an HTTP rule (`GET /get`) attached to the
workload with `selector`. Predict the result first: ztunnel cannot read HTTP.

```bash
kubectl delete -f authz-ambient-allow-curl-l4.yaml
kubectl apply -f authz-ambient-l7-no-waypoint.yaml
sleep 15
call lab-ambient curl http://httpbin:8080/get                  # the very request the rule allows
call lab-ambient curl http://httpbin:8080/headers
istioctl analyze -n lab-ambient
kubectl -n istio-system logs ds/ztunnel --tail=200 | grep 'policy rejection' | tail -2
```

Both calls fail with `exit=56`, **including the `GET /get` the rule was written to allow**. ztunnel cannot evaluate
the HTTP attributes, so no allow rule matches and it fails closed. `istioctl analyze` reports no problem, and the
reason is only in ztunnel's log: `connection closed due to policy rejection: allow policies exist, but none allowed`.

**C3. The fix: a waypoint, and a policy attached to it.** Remove the deny-all and the selector policy, create the
waypoint, and attach the same rule with `targetRefs`:

```bash
kubectl delete -f authz-ambient-l7-no-waypoint.yaml -f authz-ambient-deny-all.yaml
istioctl waypoint apply -n lab-ambient --enroll-namespace --wait
kubectl apply -f authz-ambient-l7-waypoint.yaml
sleep 15
call lab-ambient curl http://httpbin:8080/get                  # allowed
call lab-ambient curl http://httpbin:8080/headers              # denied
call lab-ambient curl -X POST http://httpbin:8080/post         # denied
call lab-ambient curl-other http://httpbin:8080/get            # denied
```

The waypoint is Envoy, so it enforces method, path and caller. Because the ALLOW policy applies, everything it does not
allow is denied without a deny-all.

## Verify

| Step | Call | Expected |
|------|------|----------|
| A1 permissive | legacy to `lab-sidecar` httpbin | `200` |
| A2 strict | legacy to `lab-sidecar` httpbin | `exit=56` |
| A2 strict | `lab-sidecar/curl` | `200` |
| A5 allowed | `curl` `GET /get` | `200` |
| A5 denied | `curl` `GET /headers`, `POST /post`, `curl-other` `GET /get` | `403` (`RBAC: access denied`) |
| B1 strict (ztunnel) | legacy to `lab-ambient` httpbin | `exit=56` |
| B2 L4 | `curl` allowed, `curl-other` denied | `200`, `exit=56` |
| C1 NetworkPolicy | fresh client, port 8080 only / plus 15008 | `exit=28` / `200` |
| C2 L7 without waypoint | `GET /get` and `GET /headers` | both `exit=56` |
| C3 L7 with waypoint | `GET /get` / `GET /headers`, `POST`, `curl-other` | `200` / `403` |

## Break it

C1 and C2 are the exercises. In C2, the instructive moment is the `GET /get` that fails although the policy allows it.
Before applying the file, write down what you expect; afterwards find the reason **without** reading this README, using
only `istioctl analyze`, `kubectl get authorizationpolicy` and the ztunnel log.

## Self-check

- Why does `PERMISSIVE` exist, and what is the risk of leaving it on?
- Which component rejected each denied call: the sidecar, ztunnel or the waypoint? How can you tell from the error
  (`403 RBAC` vs a reset connection)?
- Where does a SPIFFE ID come from, and what happens to it when a Pod's ServiceAccount changes?
- Why can a NetworkPolicy "work" until a Pod restarts?

## Cleanup

```bash
kubectl delete -f namespaces.yaml
```

Next: [03 Ingress and Egress](../03-ingress-egress-traffic/README.md).
