# Note 05: Observability and Debugging (to extend)

Not a full lab: a map of what you already used in labs 01 to 04, and what to try next on your own LGTM stack
(Prometheus, Grafana, Loki, Tempo from the `monitoring` utility). Items marked **ran** were run in these labs; items
marked **idea** were not tested here.

## The three signals

| Signal | What you used | Try next |
|--------|---------------|----------|
| **Metrics** | `istio_requests_total` read straight from a sidecar (`pilot-agent request GET stats/prometheus`), from a waypoint (`:15020/stats/prometheus`) and from ztunnel (`:15020/metrics`, TCP series only) (**ran**, lab 01) | **Idea:** scrape istiod, sidecars, waypoints and ztunnel with the kube-prometheus-stack, then chart request rate, error rate and latency per service in Grafana. Compare ztunnel's L4 series with a waypoint's L7 series for the same call |
| **Access logs** | The egress gateway's log through a `Telemetry` resource (`03-ingress-egress-traffic/egress-access-log.yaml`, **ran**, lab 03) | **Idea:** turn on access logs for one namespace (`accessLogging` with the `envoy` provider), ship them to Loki with Alloy, and filter by response flag |
| **Traces** | Not used | **Idea:** a `Telemetry` tracing config with an OpenTelemetry provider pointing at Alloy (`alloy.monitoring.svc:4317`), so spans reach Tempo; propagate the trace headers in your app, then jump from a metric to a trace in Grafana |

## The debug toolkit

Everything below was **ran** in the labs.

| Question | Command |
|----------|---------|
| Is my configuration valid? | `istioctl analyze -n <ns>` (note: it did **not** flag the L7-without-waypoint policy of lab 02, so it is a first check, not proof) |
| Which proxies does istiod manage, are they in sync? | `istioctl proxy-status` |
| Which workloads and services does ztunnel know, and which waypoint serves them? | `istioctl ztunnel-config workloads` / `services` |
| What identity and certificate does a workload hold? | `istioctl proxy-config secret deploy/<name> -n <ns>` |
| Which endpoints does a client really send to? | `istioctl proxy-config endpoints deploy/<client>.<ns>`; narrow it with `--cluster` and the cluster name from `istioctl proxy-config cluster` (lab 04 shows the remote gateway as an endpoint) |
| What mTLS mode applies to a Pod? | `istioctl x describe pod <pod> -n <ns>` |
| Is the other cluster connected? | `istioctl remote-clusters` |
| Why was a call denied? | ztunnel: read `kubectl -n istio-system logs ds/ztunnel` and look for `policy rejection`. Gateway or sidecar: turn on `istioctl proxy-config log <pod> -n <ns> --level rbac:debug` and look for `enforced denied` |

## Envoy response flags

In `istio_requests_total` (the `response_flags` label) and in access logs, a flag says **why** a request ended:

| Flag | Meaning | Seen in |
|------|---------|---------|
| `-` | Nothing special: a normal response | every lab |
| `UO` | Upstream overflow: a circuit breaker refused the request | lab 03, step 10 (**ran**) |
| `UH` | No healthy upstream (all endpoints ejected or none) | **idea:** scale a service to 0 while calling it |
| `UF` | Upstream connection failure | **idea:** point a route at a closed port |
| `NR` | No route configured | **idea:** call a host the sidecar has no route for |

The full list is in the Envoy documentation (access log "response flags").

## Things to try

1. Build the Grafana dashboard for the labs 01 and 03 numbers: requests per version during the canary, `503 UO` during
   the fortio run.
2. Turn on access logs in `lab-traffic`, rerun the circuit-breaker test and find the `UO` lines in Loki.
3. Add a trace for one request from the ingress gateway through two services and read it in Tempo.
4. Optional: Kiali for the service graph.
