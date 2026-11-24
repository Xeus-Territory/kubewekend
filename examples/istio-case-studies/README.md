# Istio Case Studies

Hands-on labs for the main ideas of a service mesh, run on **Kind** with the tools Kubewekend already uses
(the `common` Helm chart for the sample apps, the Gateway API, cloud-provider-kind for load-balancer addresses).
Each lab is a short story you can run, break and explain: *what happens, why, and how do I prove it*.

> [!NOTE]
>
> Every lab step was run end to end on Kind v0.33.0 (Kubernetes v1.36.4), cloud-provider-kind v0.12.0 and Istio 1.32.0.
> The expected results in the labs are the real ones from that run. If a result differs in your environment, that is a
> finding worth writing down.

## The labs

| Lab | What you learn | Platform | Time |
|-----|----------------|----------|------|
| [00 Platform](00-platform/README.md) | Kind without ingress, LoadBalancer addresses, Istio in ambient profile, the sample apps | 1 cluster, 3 nodes | 0.5 day |
| [01 Sidecar vs Ambient](01-sidecar-vs-ambient/README.md) | How the two data planes work, what a waypoint adds, memory cost, migrating a namespace | `mesh` | 1 to 1.5 days |
| [02 mTLS and Policies](02-mtls-and-policies/README.md) | Strict mTLS, workload identity, authorization, **where each rule is enforced** (L4 vs L7), NetworkPolicy and ambient | `mesh` | 1.5 to 2 days |
| [03 Ingress and Egress](03-ingress-egress-traffic/README.md) | Gateway API ingress, canaries, TLS, timeouts, retries, circuit breaking, mirroring, a closed egress door | `mesh` | 2 to 3 days |
| [04 Multi-cluster, multi-network](04-multicluster-multinetwork/README.md) | One mesh over two clusters, east-west gateways, locality failover | `east` + `west` | 2 to 4 days |
| [05 Observability and debugging](05-observability-debug.md) | Note: metrics, logs, traces and the debug toolkit, to extend on your LGTM stack | any | to extend |
| [06 Operations](06-operations.md) | Note: upgrades, scale, lifecycle, extensions, to extend | any | to extend |

The times are for learning, not for running the commands: most of it is reading what you see and predicting the next
step. Do the labs in order; each one starts by creating what it needs and ends with a Cleanup.

## What the labs cover

A service mesh exists for five jobs. The labs touch all of them:

| Job of a mesh | Where |
|---------------|-------|
| **Security:** mutual TLS, workload identity, authorization | Lab 02; egress control in lab 03 |
| **Traffic management:** routing, canaries, ingress, egress | Lab 03 (and routing with the Gateway API in lab 01) |
| **Reliability:** timeouts, retries, circuit breaking, failover | Lab 03 and lab 04 |
| **Observability:** metrics, logs, traces, debugging | Evidence in every lab; note 05 |
| **Running it:** data plane choice, multi-cluster, upgrades | Labs 01 and 04; note 06 |

## Layout

```text
examples/istio-case-studies/
├── README.md                       this page
├── 00-platform/                    cluster config, install steps
├── 01-sidecar-vs-ambient/          manifests + README (the same shape in labs 02 to 04)
├── 02-mtls-and-policies/
├── 03-ingress-egress-traffic/
├── 04-multicluster-multinetwork/
├── 05-observability-debug.md       note
├── 06-operations.md                note
└── apps/                           sample apps as `common` chart values, deploy.sh, helpers.sh
```

Every lab README follows the same template: **Goal, Concepts, Steps, Verify, Break it, Self-check, Cleanup.** The
"Break it" part is where most of the learning happens: predict first, then run, then explain.

## Before you start

- A machine with Docker, `kind`, `kubectl`, `helm`, and about 4 CPU / 8 GB free (lab 04: 6 to 8 CPU / 12 to 16 GB).
- Internet access for images, the Istio release, and the `example.com` host used by the egress part of lab 03.
- Kubewekend's Kind cluster works for labs 01 to 03 once it runs **without an ingress controller**; the labs also bring
  their own Kind configs, so they work on their own.

Cleanup of everything at the end: `kind delete cluster --name mesh`, `kind delete cluster --name east`,
`kind delete cluster --name west`, and stop cloud-provider-kind.

---

## Concept ideas

Labs 01 to 04 stay on the core of a mesh. These are the next things to explore, in rough order of value. None of them
was tested in these labs; treat each as a starting point.

### Istio with Argo Rollouts (progressive delivery)

The integration worth trying next. In lab 03 you moved traffic between versions by hand (90/10, then a header
rule). **Argo Rollouts** automates exactly that: a `Rollout` resource with `trafficRouting.istio` shifts the weights of
a VirtualService (or an HTTPRoute, through the Gateway API plugin) step by step (10%, 50%, 100%), and an
`AnalysisTemplate` reads Istio's metrics from Prometheus (for example the success rate of `istio_requests_total`) to
decide to promote or roll back on its own. Kubewekend's [`examples/argocd-apps`](https://github.com/Xeus-Territory/kubewekend/tree/main/examples/argocd-apps) already carries an
Argo Rollouts chart (disabled today), and it is the natural home for a GitOps version of this: Argo CD installs the
mesh and the app, Argo Rollouts drives the canary.

### Policy guardrails

Admission policies (for example Kyverno, from Kubewekend's `security` utility) can enforce mesh rules at creation
time: require the injection or ambient label on application namespaces, forbid `PERMISSIVE` mTLS, or restrict who may
create routing resources. To be expanded later.

### More mesh features

| Idea | Why it matters |
|------|----------------|
| **VMs in the mesh** (`WorkloadEntry`, `WorkloadGroup`) | Bring non-Kubernetes workloads into mTLS and policy; Kubewekend already has Vagrant VMs to try it on |
| **JWT validation** (`RequestAuthentication`) at the ingress gateway | End-user authentication on top of workload identity |
| **External authorization** (`AuthorizationPolicy` with `action: CUSTOM`) with oauth2-proxy or OPA | Delegate decisions the mesh cannot express |
| **cert-manager as the mesh CA** (istio-csr) | Use your own certificate authority instead of istiod's |
| **Ingress TLS variants:** SNI passthrough, client certificates, HTTP to HTTPS redirect | Everyday gateway needs beyond the lab's single listener |
| **Session affinity and local rate limiting** | Stateful backends and protecting a service from bursts |
| **Header manipulation and URL rewrites** | Adapting requests between clients and services |
| **Global rate limiting** (Envoy rate limit service with Redis) | Limits that count across all proxies, unlike the per-proxy local limit |
| **gRPC, TCP and WebSocket traffic**, proxyless gRPC | Not every service speaks HTTP/1.1 |
| **Protocol detection:** `http-` / `grpc-` port names, server-speaks-first protocols such as MySQL | A frequent source of "it works without the mesh" bugs |
| **DNS proxying, `exportTo` and cluster-local services** in a multi-cluster mesh | Control which services cross clusters |
| **Primary-remote multi-cluster model**, and ambient multi-cluster | Compare with the multi-primary setup of lab 04 (check the release notes for ambient status) |
| **SPIRE and trust-domain federation** | Advanced identity across organisations |
| **Performance comparison** with fortio: no mesh, sidecar, ambient, ambient plus waypoint | Put numbers on the cost of each layer |

### Write-up ideas

- Istio vs Linkerd vs Cilium service mesh: what each trades away.
- "Where is this rule enforced?": the L4 / L7 split in ambient, with the failures from lab 02 as examples.
