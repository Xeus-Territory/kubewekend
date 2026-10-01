# Common Chart TODO

This file tracks the next evolution of the `common` Helm chart after the current `0.3.0` improvements around env rendering, Service port mapping, RBAC flexibility, and release-note quality.

## Current Position

The chart is already a useful reusable base for stateless application workloads.

It currently supports:

- Deployment-based workloads
- Flexible `env` and `envFrom` rendering
- Decoupled container ports and Service ports
- Multi-port Service mapping with explicit `targetPort`
- Ingress integration with selected primary Service port
- Configurable RBAC with Role, ClusterRole, RoleBinding, ClusterRoleBinding, and pre-existing role binding
- Core scheduling controls: `nodeSelector`, `tolerations`, `affinity`
- Generic `volumes` and `volumeMounts`

>[!NOTE]
>
>It is not yet a fully general production chart for all workload types.

That means it is okay if this chart is excellent for:

- web apps
- APIs
- internal tools
- dashboards
- platform UIs

And not yet ideal for:

- databases
- stateful middleware
- operator-style components
- complex multi-container pods

## Recommended Feature Checklist

### Safe To Add Next

- [ ] Add `schedulerName` support to Pod spec
- [ ] Add `priorityClassName` support to Pod spec
- [ ] Add `topologySpreadConstraints` support
- [ ] Add `terminationGracePeriodSeconds`
- [ ] Add deployment `strategy` configuration
- [ ] Add `revisionHistoryLimit`
- [ ] Add `minReadySeconds`
- [ ] Add `lifecycle` hooks for the main container

### High-Value Production Features

- [ ] Add checksum annotations for ConfigMap/Secret-driven rollout restarts
- [ ] Add `podAntiAffinityPreset` or higher-level scheduling shortcuts if desired
- [ ] Add `NetworkPolicy` support
- [ ] Add `ServiceMonitor` / `PodMonitor` support
- [ ] Add optional `PrometheusRule` support
- [ ] Add `runtimeClassName` support
- [ ] Add `dnsPolicy` and `dnsConfig` support

### Persistence And Storage

- [ ] Define a first-class `persistence` model
- [ ] Decide whether to support only existing PVCs, generated PVCs, or both
- [ ] Add PVC template rendering when `persistence.enabled=true`
- [ ] Support `storageClass`, `accessModes`, `size`, and `annotations`
- [ ] Support subPath-based mounts where needed
- [ ] Document which workloads should use this chart versus a StatefulSet-specific chart

### Multi-Container Evolution

- [ ] Add `initContainers`
- [ ] Add `extraContainers` or `sidecars`
- [ ] Revisit test hooks for multi-container pods
- [ ] Revisit `resourceFieldRef` design for multi-container targeting
- [ ] Revisit NOTES and port-forward instructions for multi-container workloads
- [ ] Revisit probe defaults when a chart has multiple containers with different exposed ports

### Workload Expansion

- [ ] Add StatefulSet support if this chart should handle stateful apps
- [ ] Add DaemonSet support only if there is a real use case
- [ ] Decide whether to keep this chart as Deployment-first or split workload kinds into separate charts

### Config And Secret Management

- [ ] Add first-class ConfigMap generation support
- [ ] Add first-class Secret generation support
- [ ] Add `existingSecret` / `existingConfigMap` convenience fields where useful
- [ ] Add checksum-based pod restart behavior for generated config

### Library-Chart Direction

- [ ] Decide whether this chart should remain a deployable application chart or evolve into a library chart
- [ ] If library direction is chosen, extract reusable partials for container, Service, ingress, and RBAC rendering
- [ ] Standardize helper APIs for downstream charts
- [ ] Minimize app-specific assumptions in templates and values layout

## Suggested Release Sequencing

### Next Release

- [ ] `schedulerName`
- [ ] `priorityClassName`
- [ ] `topologySpreadConstraints`
- [ ] deployment strategy controls

### Following Release

- [ ] `initContainers`
- [ ] `extraContainers` / sidecars
- [ ] persistence design decision

### Later Release

- [ ] PVC generation support
- [ ] config checksum rollouts
- [ ] monitoring and network policy integrations

## Design Guardrails

Keep these principles while evolving the chart:

- [ ] Preserve backward compatibility for the default single-container Deployment path
- [ ] Prefer explicit values over hidden template assumptions
- [ ] Add validations for invalid combinations where possible
- [ ] Avoid turning the chart into a catch-all without a clear scope decision
- [ ] Document every new abstraction in `values.yaml`, `values-test.yaml`, and release notes

## Decision To Revisit

- [ ] Should this chart stay a reusable application chart?
- [ ] Should a separate Helm library chart be introduced for shared helpers across multiple dependent charts?
- [ ] Should persistence/stateful workloads live here or in a separate specialized chart?