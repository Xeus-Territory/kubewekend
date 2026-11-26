# Common Chart TODO

This file tracks the next evolution of the `common` Helm chart after the `0.4.0` improvements: RBAC/PDB/image/probe fixes, Gateway API `HTTPRoute` support, rollout/scheduling controls, `initContainers` / `extraContainers`, existing-PVC `persistence`, `deploymentAnnotations`, `podAntiAffinityPreset`, `ServiceMonitor` / `PodMonitor`, and the stateless-application scope decision (on top of the `0.3.0` env rendering, Service port mapping, and RBAC flexibility work).

## Target Workloads

`common` targets **stateless applications** rendered as a single `Deployment`. Every new feature should keep that goal; anything that needs per-pod identity, per-pod storage or a different workload kind belongs in a dedicated chart.

In scope:

- simple applications (workers, internal tools, dashboards)
- web APIs / backends
- frontends (SPA, SSR, platform UIs)
- GPU workloads via device plugin (inference servers, GPU services)

Out of scope (use a dedicated chart):

- databases
- stateful applications (e.g. Kafka, Redis cluster, Elasticsearch)
- node agents (DaemonSet)
- operators / controllers

## Current Position

The chart is already a useful reusable base for these stateless workloads.

It currently supports:

- Deployment workloads only (`deploymentType` was removed; StatefulSet / DaemonSet are out of scope)
- Flexible `env` and `envFrom` rendering, referencing existing ConfigMaps / Secrets (the chart does not create them)
- Decoupled container ports and Service ports
- Multi-port Service mapping with explicit `targetPort`
- Ingress integration with selected primary Service port
- Gateway API `HTTPRoute` integration with selected primary Service port
- Configurable RBAC with Role, ClusterRole, RoleBinding, ClusterRoleBinding, and pre-existing role binding
- Scheduling controls: `nodeSelector`, `tolerations`, `affinity`, `podAntiAffinityPreset` (soft / hard), `topologySpreadConstraints`, `schedulerName`, `priorityClassName`, `runtimeClassName`
- Rollout controls: `strategy`, `revisionHistoryLimit`, `minReadySeconds`, `terminationGracePeriodSeconds`, and main-container `lifecycle` hooks
- Generic `volumes` and `volumeMounts`
- Existing PVC mounting via `persistence.existingClaim`, with access-mode safety checks
- `initContainers` (including native sidecars with `restartPolicy: Always`) and pass-through `extraContainers`
- Deployment-level `deploymentAnnotations` (e.g. Reloader restarts, Argo CD sync waves) next to `podAnnotations`
- Prometheus Operator `ServiceMonitor` / `PodMonitor` with scrape-port validation and cross-namespace `namespaceSelector`

>[!NOTE]
>
>It is intentionally not a general chart for all workload types: see [Target Workloads](#target-workloads).

## Recommended Feature Checklist

### Safe To Add Next

- [x] Add `schedulerName` support to Pod spec
- [x] Add `priorityClassName` support to Pod spec
- [x] Add `topologySpreadConstraints` support
- [x] Add `terminationGracePeriodSeconds`
- [x] Add deployment `strategy` configuration
- [x] Add `revisionHistoryLimit`
- [x] Add `minReadySeconds`
- [x] Add `lifecycle` hooks for the main container

### High-Value Production Features

- [x] ~~Add checksum annotations for ConfigMap/Secret-driven rollout restarts~~: out of scope, the chart renders no ConfigMaps/Secrets to hash; use Reloader via `deploymentAnnotations`
- [x] Add `deploymentAnnotations` for Deployment-level metadata (Reloader, Argo CD, image updaters, policy exceptions)
- [x] Add `podAntiAffinityPreset` or higher-level scheduling shortcuts if desired (`soft` / `hard`, `topologyKey`, `weight`; merged into `affinity`)
- [ ] Add `NetworkPolicy` support
- [x] Add `ServiceMonitor` / `PodMonitor` support
- [ ] Add optional `PrometheusRule` support
- [x] Add `runtimeClassName` support
- [ ] Add `dnsPolicy` and `dnsConfig` support

### GPU And Dynamic Resource Allocation (DRA)

GPU workloads via the device plugin already work (`runtimeClassName` + `resources.limits` + `tolerations` / `nodeSelector`, see `README.md`).
DRA needs pod-level `resourceClaims`, which the chart cannot render yet.

- [ ] Add pod-level `resourceClaims` (reference an existing `ResourceClaim` or a `ResourceClaimTemplate` by name)
- [ ] Optionally generate a `ResourceClaimTemplate` from values (`deviceClassName`, `count`, `selectors`)
- [ ] Document the container-level `resources.claims` wiring next to `resourceClaims` (already passes through `resources`)
- [ ] Gate DRA rendering on the `resource.k8s.io/v1` API (GA in Kubernetes 1.34) via `.Capabilities.APIVersions`
- [ ] Add a DRA GPU example to `values-test.yaml` and the README once rendering exists

### Persistence And Storage

- [x] Define a first-class `persistence` model (`persistence.existingClaim`, `mountPath`, `subPath`, `readOnly`, `volumeName`)
- [x] Decide whether to support only existing PVCs, generated PVCs, or both: **existing PVCs only**
- [x] ~~Add PVC template rendering when `persistence.enabled=true`~~: out of scope, a Deployment-owned PVC breaks RWO rollouts and is deleted on uninstall
- [x] ~~Support `storageClass`, `accessModes`, `size`, and `annotations`~~: not needed without PVC generation; `accessMode` is kept for safety checks
- [x] Support subPath-based mounts where needed
- [x] Document which workloads should use this chart versus a StatefulSet-specific chart (README "Persistence")

### Multi-Container Evolution

- [x] Add `initContainers` (also covers native sidecars with `restartPolicy: Always`)
- [x] Add `extraContainers` or `sidecars`
- [x] Revisit test hooks for multi-container pods: test hook keeps targeting the main container's Service port
- [x] Revisit `resourceFieldRef` design for multi-container targeting: `env` shortcuts stay main-container only; extra containers define their own `env`
- [x] Revisit NOTES and port-forward instructions for multi-container workloads: NOTES keep targeting the main container
- [x] Revisit probe defaults when a chart has multiple containers with different exposed ports: default probes only apply to the main container; extra containers bring their own

### Workload Expansion

- [x] ~~Add StatefulSet support if this chart should handle stateful apps~~: out of scope, use a dedicated chart
- [x] ~~Add DaemonSet support only if there is a real use case~~: out of scope, use a dedicated chart
- [x] Decide whether to keep this chart as Deployment-first or split workload kinds into separate charts: **Deployment only**, `deploymentType` removed

### Config And Secret Management

Decision: the chart **references** existing ConfigMaps / Secrets (`env` `secret:` / `configmap:` shortcuts, `envFrom`, `volumes`) and leaves their lifecycle to the tool that owns them (External Secrets Operator, Vault, Sealed Secrets, SOPS, another chart). Restarts on change are delegated to [Reloader](https://github.com/stakater/Reloader) through `deploymentAnnotations`. See README "Config, Secrets And Reloader".

- [x] ~~Add first-class ConfigMap generation support~~: out of scope, use `extraManifests` for a simple ConfigMap
- [x] ~~Add first-class Secret generation support~~: out of scope, secrets in values end up in plain text in the repository and the Helm release
- [x] ~~Add `existingSecret` / `existingConfigMap` convenience fields where useful~~: covered by `env` shortcuts, `envFrom` and `volumes`
- [x] ~~Add checksum-based pod restart behavior for generated config~~: replaced by Reloader (`deploymentAnnotations`)

### Library-Chart Direction

- [x] Decide whether this chart should remain a deployable application chart or evolve into a library chart: **stays a deployable application chart** (`helm install` / `helm template` with values only)
- [x] ~~If library direction is chosen, extract reusable partials for container, Service, ingress, and RBAC rendering~~: not applicable
- [x] ~~Standardize helper APIs for downstream charts~~: not applicable, downstream charts depend on `common` as a subchart (see `examples/argocd-apps`)
- [x] Minimize app-specific assumptions in templates and values layout: moved to Design Guardrails

## Suggested Release Sequencing

### Next Release

- [x] `schedulerName`
- [x] `priorityClassName`
- [x] `topologySpreadConstraints`
- [x] deployment strategy controls

### Following Release

- [x] `initContainers`
- [x] `extraContainers` / sidecars
- [x] persistence design decision

### Later Release

- [x] ~~PVC generation support~~: out of scope (existing PVCs only)
- [x] ~~config checksum rollouts~~: replaced by Reloader via `deploymentAnnotations`
- [x] monitoring integrations (`ServiceMonitor` / `PodMonitor`)
- [ ] network policy integration and optional `PrometheusRule`

## Design Guardrails

Keep these principles while evolving the chart:

- [ ] Preserve backward compatibility for the default single-container Deployment path
- [ ] Prefer explicit values over hidden template assumptions
- [ ] Add validations for invalid combinations where possible
- [x] Avoid turning the chart into a catch-all without a clear scope decision: scope is stateless applications, see [Target Workloads](#target-workloads)
- [ ] Document every new abstraction in `values.yaml`, `values-test.yaml`, and release notes
- [ ] Keep templates free of app-specific assumptions; reference external objects instead of generating them

## Decision To Revisit

- [x] Should this chart stay a reusable application chart? **Yes**, a reusable chart for stateless applications (see [Target Workloads](#target-workloads))
- [x] Should a separate Helm library chart be introduced for shared helpers across multiple dependent charts? **No**, `common` stays an application chart; reuse it as a subchart dependency
- [x] Should persistence/stateful workloads live here or in a separate specialized chart? **Separate chart**; this chart only mounts existing PVCs