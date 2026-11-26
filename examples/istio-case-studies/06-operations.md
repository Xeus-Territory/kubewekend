# Note 06: Operations (to extend)

Not a full lab: the day-two topics that come after the first four labs. **Nothing here was run in these labs**: treat
every item as an idea to test on a disposable cluster, and check the Istio documentation for the version you run.

## Upgrade the control plane without a big bang

- **Revisions:** install a second control plane next to the first with a revision name
  (`istioctl install --set revision=<name>`), then move namespaces over one at a time by replacing the
  `istio-injection=enabled` label with `istio.io/rev=<name>` and restarting their Pods. Roll back by flipping the
  label. Revision **tags** (`istioctl tag set`) give a stable name (for example `stable`) to point namespaces at.
- **Ambient:** ztunnel and the Istio CNI are node-level, so they are upgraded as DaemonSets; plan node-by-node rollout
  and check what happens to in-flight connections. Waypoints are Deployments and upgrade like any workload.
- **Try:** keep a namespace on the old revision while another moves, and confirm with `istioctl proxy-status`
  that both versions are connected.

## Keep the mesh small and fast as it grows

- **Scope what each proxy knows:** by default every sidecar receives configuration for every service in the mesh. The
  `Sidecar` resource (lab 03 used it only for `outboundTrafficPolicy`) can list the namespaces a workload talks to;
  `meshConfig.discoverySelectors` limits what istiod watches; `exportTo` on services and rules keeps them visible only
  where needed.
- **Try:** measure istiod and sidecar memory (`kubectl top`) in a namespace with many services before and after adding a
  `Sidecar` that limits egress to its own namespace.

## Pod lifecycle

- **Startup and shutdown:** lab 01 covered native sidecars and `holdApplicationUntilProxyStarts`. For shutdown, look at
  `terminationDrainDuration` and how long your app needs to finish requests.
- **Probes:** how Istio rewrites application health probes, and what breaks when strict mTLS meets a probe from the
  kubelet.
- **Resources:** proxy CPU and memory requests and limits per workload (annotations) or per mesh.

## Extending the proxy, and why to hold back

`EnvoyFilter` and `WasmPlugin` can change anything in Envoy. They are also tied to Envoy internals that change between
Istio versions, so they are the most common reason an upgrade breaks. Prefer a built-in resource, and keep an
`EnvoyFilter` only when nothing else expresses what you need, with a test for every upgrade.

## Mesh configuration as code

Mesh resources (`VirtualService`, `AuthorizationPolicy`, `Gateway`) are easy to break by hand and hard to review.
Keep them in Git and apply them through a GitOps tool (see "Concept ideas" in the [overview](README.md)).
