# common

![Version: 0.4.0](https://img.shields.io/badge/Version-0.4.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)

A Helm chart for standard application, rendered as a Deployment powered by Kubewekend

**📢 STATUS: ACTIVE ✅**

## Installing the Chart

To install the chart with the release name `appwekend`:

```console
$ helm repo add kubewekend https://kubewekend.xeusnguyen.xyz
$ helm install appwekend kubewekend/common
```

**Homepage:** <https://github.com/Xeus-Territory/kubewekend>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Xeus Nguyen | <xeusnguyen@gmail.com> | <https://wiki.xeusnguyen.xyz> |

## Workload Scope

`common` is a chart for **stateless applications**. It always renders a single `Deployment` (plus optional Service, Ingress, HTTPRoute, HPA, PDB, RBAC and extra manifests), so any replica can be replaced, rescheduled or scaled without losing state.

### Good fit

| Workload | Examples |
| -------- | -------- |
| Simple applications | background workers, queue consumers, internal tools, dashboards |
| Web APIs / backends | REST / gRPC services, BFFs, webhooks |
| Frontends | SPA served by nginx, SSR apps (Next.js, Nuxt), platform UIs |
| GPU workloads | inference servers and GPU services via device plugin, see [GPU Workloads](#gpu-workloads) |

State lives outside the pod (database, cache, object storage). When pods need files on disk, mount a shared or existing claim with [`persistence`](#persistence), e.g. uploads or a model cache.

### Not a fit (use a dedicated chart)

| Workload | Why |
| -------- | --- |
| Databases | need stable identity and one volume per replica (StatefulSet + `volumeClaimTemplates`) |
| Stateful applications | e.g. Kafka, Redis cluster, Elasticsearch: ordered rollout, per-pod identity and storage |
| Node agents | log / metrics collectors, CNI or CSI node plugins run on every node (DaemonSet) |
| Operators / controllers | ship CRDs, webhooks, leader election and cluster-wide RBAC; use the operator's own chart |

The former `deploymentType` value was removed; setting it to anything other than `deployment` fails rendering.

## Init Containers And Sidecars

`initContainers` and `extraContainers` are rendered as written (templates are allowed). The chart's ports, probes, NOTES and test hook keep targeting the main container, so every additional container defines its own ports, probes and resources.

```yaml
initContainers:
  # Runs to completion before the app starts
  - name: migrate
    image: xeusnguyen/application:v0.0.1
    command: ["/bin/sh", "-c", "yarn run migrate"]
  # Native sidecar (Kubernetes >= 1.29): starts before and stops after the app
  - name: log-shipper
    image: fluent/fluent-bit:3.2
    restartPolicy: Always
    volumeMounts:
      - name: logs
        mountPath: /var/log/app
extraContainers:
  # Classic sidecar running next to the app
  - name: oauth2-proxy
    image: quay.io/oauth2-proxy/oauth2-proxy:v7.7.1
    args: ["--upstream=http://127.0.0.1:3000", "--http-address=0.0.0.0:4180"]
volumes:
  - name: logs
    emptyDir: {}
volumeMounts:
  - name: logs
    mountPath: /var/log/app
```

## Persistence

The chart mounts an **existing** PersistentVolumeClaim into the main container; it never creates PVCs, so data survives `helm uninstall` and a rollout cannot be blocked by a claim the chart owns.

```yaml
persistence:
  enabled: true
  existingClaim: todo-uploads
  accessMode: ReadWriteMany # access mode of the existing claim, used for safety checks
  mountPath: /app/uploads
  subPath: ""
  readOnly: false
```

Safety checks based on `persistence.accessMode`:

| Access mode | Behaviour |
| ----------- | --------- |
| `ReadWriteMany` / `ReadOnlyMany` | Any replica count and strategy. |
| `ReadWriteOnce` | Renders, but NOTES warns when more than one pod may run (`replicaCount` / autoscaling) or the strategy is `RollingUpdate`: pods on another node fail with `Multi-Attach error`. Prefer `strategy.type: Recreate` and a single replica. |
| `ReadWriteOncePod` | Fails rendering unless the Deployment runs a single pod and `strategy.type: Recreate`. |

`initContainers` and `extraContainers` can mount the same claim by referring to `persistence.volumeName` (default `data`).

## Config, Secrets And Reloader

The chart **references** existing ConfigMaps and Secrets; it does not create them. Manage them with the tool that owns them (External Secrets Operator, Vault, Sealed Secrets, SOPS, or another chart), or add a simple ConfigMap through `extraManifests`.

| Need | Values |
| ---- | ------ |
| One key as an env var | `env: { DB_PASSWORD: "secret:app-secret:password", APP_CONFIG: "configmap:app-config:config.yaml" }` |
| All keys as env vars | `envFrom: [{ secretRef: { name: app-secret } }, { configMapRef: { name: app-config } }]` |
| Files in the container | `volumes` with a `configMap` / `secret` source + `volumeMounts` |

Pods only read env vars at start, so changes need a restart. Instead of checksum annotations (which only work for objects the chart renders itself), use [Reloader](https://github.com/stakater/Reloader) through `deploymentAnnotations`:

```yaml
deploymentAnnotations:
  reloader.stakater.com/auto: "true"                   # restart when any referenced ConfigMap/Secret changes
  # secret.reloader.stakater.com/reload: "app-secret"  # or watch specific objects only
```

`deploymentAnnotations` lands on the Deployment's own metadata, so it also serves other tools, e.g. `argocd.argoproj.io/sync-wave`. Pod-level annotations stay in `podAnnotations`.

## High Availability Scheduling

Spread replicas so one node or zone failure does not take the whole application down. Both options target this release's own pods (selector labels) automatically:

```yaml
replicaCount: 3
# Anti-affinity shortcut, merged into `affinity` (cannot be combined with affinity.podAntiAffinity)
podAntiAffinityPreset:
  type: soft                          # soft = preferred, hard = required
  topologyKey: kubernetes.io/hostname # or topology.kubernetes.io/zone
  weight: 1                           # soft only, 1-100
# Finer-grained, even spreading (labelSelector is filled in when omitted)
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: ScheduleAnyway
pdb:
  create: true
  minAvailable: 1
```

With `type: hard`, a replica stays `Pending` when no free node / zone is left, which also blocks a RollingUpdate that surges an extra pod. Keep `replicaCount` at or below the eligible domains, or set `strategy.rollingUpdate.maxSurge: 0`.

## Monitoring

With the [Prometheus Operator](https://prometheus-operator.dev/) CRDs installed (e.g. kube-prometheus-stack), the chart can create a `ServiceMonitor` (scrapes through the Service) or a `PodMonitor` (scrapes the pods directly). Enable one of them for the same port, not both.

```yaml
containerPorts:
  - name: http
    containerPort: 3000
  - name: metrics
    containerPort: 9090
service:
  ports:
    - name: web
      port: 3000
      targetPort: http
    - name: metrics
      port: 9090
      targetPort: metrics
serviceMonitor:
  enabled: true
  port: metrics                     # Service port name
  path: /metrics
  interval: 30s
  labels:
    release: kube-prometheus-stack  # match your Prometheus serviceMonitorSelector
# podMonitor:
#   enabled: true
#   port: metrics                   # container port name
```

The chart fails rendering when the scrape port does not exist (`service.ports` for `serviceMonitor`, `containerPorts` for `podMonitor`). When `namespace` is set to a different namespace (e.g. `monitoring`), a `namespaceSelector` pointing at the release namespace is added.

## GPU Workloads

### Device plugin (supported)

Workloads that request GPUs through a device plugin (e.g. the NVIDIA GPU Operator or `nvidia-device-plugin`) can be scheduled with the existing values:

```yaml
runtimeClassName: nvidia # must exist in the cluster, check with `kubectl get runtimeclass`
resources:
  limits:
    nvidia.com/gpu: 1
tolerations:
  - key: nvidia.com/gpu
    operator: Exists
    effect: NoSchedule
nodeSelector:
  nvidia.com/gpu.present: "true"
```

Leave `runtimeClassName` empty for workloads that do not need a specific runtime handler.

### Dynamic Resource Allocation (not supported yet)

[DRA](https://kubernetes.io/docs/concepts/scheduling-eviction/dynamic-resource-allocation/) requests devices through `ResourceClaim` / `ResourceClaimTemplate` objects that the pod references in `spec.resourceClaims`. The chart does not render pod-level `resourceClaims` yet, so DRA workloads cannot be deployed with it today. Support is planned, see the DRA section in [TODO.md](./TODO.md).

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Functions like the nodeSelector field but is more expressive and allows you to specify soft rules, for more information: https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#affinity-and-anti-affinity |
| autoscaling | object | `{"enabled":false,"maxReplicas":100,"minReplicas":1,"targetCPUUtilizationPercentage":80}` | This section is for setting up autoscaling more information can be found here: https://kubernetes.io/docs/concepts/workloads/autoscaling/ |
| command | list | `[]` | This will set the command for your application Let it null if you already have entrypoint or cmd in your application For more information checkout: https://kubernetes.io/docs/tasks/inject-data-application/define-command-argument-container/ |
| containerPorts | list | `[]` | Additional container ports exposed by the main application container. If empty, the chart falls back to a single port derived from `service.port` when `service.enabled` is true. If you keep the default HTTP probes or Service targetPort behavior, include a port named `http`. |
| deploymentAnnotations | object | `{}` | Annotations on the Deployment object itself (not the pods, use `podAnnotations` for those). Templates are allowed. For tools that read Deployment metadata, e.g.: - Reloader, restart on ConfigMap/Secret change: `reloader.stakater.com/auto: "true"`,   or targeted `configmap.reloader.stakater.com/reload: "my-config"` / `secret.reloader.stakater.com/reload: "my-secret"` - Argo CD ordering: `argocd.argoproj.io/sync-wave: "1"` - Image updaters, policy exceptions, ownership / contact metadata |
| enabled | bool | `true` | This will define Chart enabled or not. The chart always renders a `Deployment`; StatefulSet and DaemonSet workloads are out of scope (use a dedicated chart). |
| env | object | `{}` | This sets the environment for your deployment For more information checkout: https://kubernetes.io/docs/tasks/inject-data-application/define-environment-variable-container/ |
| envFrom | list | `[]` | This sets the envFrom for your deployment, but load entire configmap or secret as environment variables ref: https://kubernetes.io/docs/tasks/inject-data-application/define-environment-variable-container/ |
| extraContainers | list | `[]` | Additional containers that run next to the main container for the whole pod lifetime (classic sidecars). Prefer a native sidecar in `initContainers` (with `restartPolicy: Always`) when it must start before the app. Rendered as-is (templates allowed); each extra container defines its own ports, probes and resources. |
| extraManifests | object | `{}` | To add your extra manifest into your applications |
| fullnameOverride | string | `""` |  |
| httpRoute | object | `{"annotations":{},"enabled":false,"hostnames":["chart-example.local"],"parentRefs":[{"name":"traefik-gateway","sectionName":"web"}],"rules":[{"matches":[{"path":{"type":"PathPrefix","value":"/"}}]}]}` | Expose the Service through the Gateway API with an `HTTPRoute`, more information can be found here: https://gateway-api.sigs.k8s.io/api-types/httproute/ Requires the Gateway API CRDs and a Gateway controller (e.g. Traefik with `providers.kubernetesGateway.enabled=true`). Each rule routes to the primary Service port (`service.primaryPortName`) unless it sets its own `backendRefs`. |
| httpRoute.annotations | object | `{}` | Annotations to add to the HTTPRoute |
| httpRoute.enabled | bool | `false` | Enable HTTPRoute creation. Requires `service.enabled=true`. |
| httpRoute.hostnames | list | `["chart-example.local"]` | Hostnames matched by this route |
| httpRoute.parentRefs | list | `[{"name":"traefik-gateway","sectionName":"web"}]` | Gateways this route attaches to. Defaults follow the Traefik Helm chart Gateway (`traefik-gateway`, listener `web`). |
| httpRoute.rules | list | `[{"matches":[{"path":{"type":"PathPrefix","value":"/"}}]}]` | Routing rules. Leave empty to route every request to the Service. |
| image | object | `{"pullPolicy":"IfNotPresent","repository":"nginx","tag":"latest"}` | This sets the container image more information can be found here: https://kubernetes.io/docs/concepts/containers/images/ |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. Accepted values: `Always`, `IfNotPresent`, `Never`. |
| image.tag | string | `"latest"` | Overrides the image tag whose default is the chart appVersion. |
| imagePullSecrets | list | `[]` | This is for the secretes for pulling an image from a private repository more information can be found here: https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/ |
| ingress | object | `{"annotations":{},"className":"","enabled":false,"hosts":[{"host":"chart-example.local","paths":[{"path":"/","pathType":"ImplementationSpecific"}]}],"tls":[]}` | This block is for setting up the ingress for more information can be found here: https://kubernetes.io/docs/concepts/services-networking/ingress/ |
| ingress.className | string | `""` | IngressClass name. Use `traefik` for the Traefik ingress controller (bundled with K3s, or installed via its Helm chart). |
| initContainers | list | `[]` | Init containers that run to completion before the main container starts, more information: https://kubernetes.io/docs/concepts/workloads/pods/init-containers/ Use for database migrations, waiting for dependencies, or preparing files in a shared volume. Native sidecars (Kubernetes >= 1.29): an init container with `restartPolicy: Always` keeps running alongside the main container and is started before / stopped after it, more information: https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/ Rendered as-is (templates allowed); ports, probes and NOTES of the chart keep targeting the main container. |
| lifecycle | object | `{}` | Lifecycle hooks for the main container, more information can be found here: https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/ A `preStop` sleep gives Service endpoints and ingress/gateway time to stop sending traffic before the container receives SIGTERM, which avoids failed requests during rollouts. Keep `terminationGracePeriodSeconds` larger than the preStop duration. |
| minReadySeconds | string | `nil` | Seconds a new pod must stay Ready (without crashing) before it counts as available during a rollout. Leave `null` to use the Kubernetes default (`0`). |
| nameOverride | string | `""` | This is to override the chart name. |
| nodeSelector | object | `{}` | Choose your node to deloy application depend on `label`, for more information: https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#nodeselector |
| pdb | object | `{"create":false,"maxUnavailable":0,"minAvailable":1}` | Setup Pod Disruption Budget for your application More information can be found here: https://kubernetes.io/docs/concepts/workloads/pods/disruptions/ |
| persistence | object | `{"accessMode":"ReadWriteOnce","enabled":false,"existingClaim":"","mountPath":"/data","readOnly":false,"subPath":"","volumeName":"data"}` | Mount an existing PersistentVolumeClaim into the main container, more information: https://kubernetes.io/docs/concepts/storage/persistent-volumes/ The chart does not create PVCs: create the claim first (or let another chart own it), then reference it here. For one volume per pod (databases, stateful middleware) use a StatefulSet-based chart instead. Other containers (`initContainers` / `extraContainers`) can mount the same volume by `persistence.volumeName`. |
| persistence.accessMode | string | `"ReadWriteOnce"` | Access mode of the existing claim, used for safety checks only. Accepted values: `ReadWriteOnce`, `ReadWriteOncePod`, `ReadWriteMany`, `ReadOnlyMany`. `ReadWriteOncePod` fails rendering unless the pod count is 1 and `strategy.type=Recreate`; `ReadWriteOnce` prints a NOTES warning when more than one pod may run or the strategy is RollingUpdate. |
| persistence.enabled | bool | `false` | Enable mounting the existing claim |
| persistence.existingClaim | string | `""` | Name of the existing PVC (supports templates, e.g. `"{{ .Release.Name }}-data"`). Required when enabled. |
| persistence.mountPath | string | `"/data"` | Path where the claim is mounted in the main container |
| persistence.readOnly | bool | `false` | Mount the claim read-only |
| persistence.subPath | string | `""` | Optional sub-path inside the volume to mount |
| persistence.volumeName | string | `"data"` | Pod volume name; must not clash with entries in `volumes` |
| podAnnotations | object | `{}` | This is for setting Kubernetes Annotations to a Pod. For more information checkout: https://kubernetes.io/docs/concepts/overview/working-with-objects/annotations/ |
| podAntiAffinityPreset | object | `{"topologyKey":"kubernetes.io/hostname","type":"","weight":1}` | Shortcut that spreads the replicas of this release apart with pod anti-affinity against its own pods. `soft`: preferred, the scheduler still co-locates replicas when it has no other choice. `hard`: required, a replica stays `Pending` when no domain is free, so keep `replicaCount` (plus RollingUpdate `maxSurge`) at or below the number of eligible nodes / zones, or use `strategy.rollingUpdate.maxSurge: 0`. Merged into `affinity` (works together with `affinity.nodeAffinity`); cannot be combined with `affinity.podAntiAffinity`. |
| podAntiAffinityPreset.topologyKey | string | `"kubernetes.io/hostname"` | Topology domain to spread across, e.g. `kubernetes.io/hostname` (nodes) or `topology.kubernetes.io/zone` (zones) |
| podAntiAffinityPreset.type | string | `""` | Accepted values: `""` (disabled), `soft`, `hard` |
| podAntiAffinityPreset.weight | int | `1` | Weight of the `soft` preference (1-100) |
| podLabels | object | `{}` | This is for setting Kubernetes Labels to a Pod. For more information checkout: https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/ |
| podMonitor | object | `{"annotations":{},"enabled":false,"honorLabels":false,"interval":"30s","labels":{},"metricRelabelings":[],"namespace":"","path":"/metrics","port":"metrics","relabelings":[],"scheme":"","scrapeTimeout":"","tlsConfig":{}}` | Prometheus Operator `PodMonitor` that scrapes the pods directly (no Service needed), more information: https://prometheus-operator.dev/docs/developer/getting-started/ Requires the Prometheus Operator CRDs (e.g. kube-prometheus-stack). |
| podMonitor.annotations | object | `{}` | Annotations to add to the PodMonitor |
| podMonitor.enabled | bool | `false` | Enable PodMonitor creation |
| podMonitor.honorLabels | bool | `false` | Keep the labels exposed by the target when they conflict with Prometheus target labels |
| podMonitor.interval | string | `"30s"` | Scrape interval. Empty uses the Prometheus default. |
| podMonitor.labels | object | `{}` | Extra labels, e.g. `release: kube-prometheus-stack` so that Prometheus' `podMonitorSelector` picks it up |
| podMonitor.metricRelabelings | list | `[]` | Relabelings applied to scraped samples before ingestion |
| podMonitor.namespace | string | `""` | Namespace for the PodMonitor. Empty means the release namespace; when set, `namespaceSelector` targets the release namespace. |
| podMonitor.path | string | `"/metrics"` | HTTP path of the metrics endpoint |
| podMonitor.port | string | `"metrics"` | Container port **name** of the main container to scrape. Must exist in `containerPorts` (or be `http` for the implicit Service-derived port). |
| podMonitor.relabelings | list | `[]` | Relabelings applied before scraping |
| podMonitor.scheme | string | `""` | Scrape scheme (`http` or `https`). Empty uses `http`. |
| podMonitor.scrapeTimeout | string | `""` | Scrape timeout, must be lower than `interval`. Empty uses the Prometheus default. |
| podMonitor.tlsConfig | object | `{}` | TLS settings for `https` scraping |
| podSecurityContext | object | `{}` | This holds pod-level security attributes and common container settings. |
| priorityClassName | string | `""` | PriorityClass for the pods; the PriorityClass must already exist in the cluster, for more information: https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/ |
| probes | object | `{"disableProbes":[],"livenessProbe":{"failureThreshold":30,"httpGet":{},"initialDelaySeconds":15,"periodSeconds":15,"successThreshold":1,"timeoutSeconds":10},"path":"/","port":"","readinessProbe":{"failureThreshold":30,"httpGet":{},"initialDelaySeconds":15,"periodSeconds":15,"successThreshold":1,"timeoutSeconds":10},"startupProbe":{"failureThreshold":30,"httpGet":{},"initialDelaySeconds":15,"periodSeconds":10,"timeoutSeconds":5}}` | This is to setup the liveness,readiness and startupProbe probes  More information can be found here: https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/ |
| probes.disableProbes | list | `[]` | Probe list to disable. Accepted values: `livenessProbe`, `readinessProbe`, `startupProbe`, `all`. Ex: ["livenessProbe", "readinessProbe"] -> enable `startupProbe` only |
| probes.livenessProbe.httpGet | object | `{}` | Leave `httpGet` empty to inherit `probes.path` and `probes.port` defaults. |
| probes.path | string | `"/"` | Default probe path used by all HTTP probes when a probe does not set `httpGet.path` explicitly. |
| probes.port | string | `""` | Leave empty to auto-select `http`, otherwise the first declared container port name, then the first container port number. |
| probes.readinessProbe.httpGet | object | `{}` | Leave `httpGet` empty to inherit `probes.path` and `probes.port` defaults. |
| probes.startupProbe.httpGet | object | `{}` | Leave `httpGet` empty to inherit `probes.path` and `probes.port` defaults. |
| probesOverride | object | `{}` | This set the override probes base on your decision |
| rbac | object | `{"create":false,"role":{"annotations":{},"create":null,"kind":"Role","name":"","namespace":"","rules":[]},"roleBinding":{"annotations":{},"create":null,"kind":"","name":"","namespace":"","roleRef":{},"subjects":[]}}` | RBAC configuration for this workload. Common patterns: 1. Create both Role/ClusterRole and RoleBinding/ClusterRoleBinding: `rbac.create=true` 2. Create only a binding to a pre-existing role: `rbac.create=false`, `rbac.roleBinding.create=true` 3. Create only the role object: `rbac.create=false`, `rbac.role.create=true` |
| rbac.create | bool | `false` | This is used as the fallback for `rbac.role.create` and `rbac.roleBinding.create` when those values are `null`. |
| rbac.role.create | string | `nil` | Per-object override for role creation. Accepted values: `true`, `false`, `null`. |
| rbac.role.kind | string | `"Role"` | RBAC role kind. Accepted values: `Role`, `ClusterRole`. |
| rbac.role.name | string | `""` | RBAC role name override. Defaults to the chart fullname. |
| rbac.role.namespace | string | `""` | RBAC role namespace override. Defaults to `common.namespace`. Ignored for `ClusterRole`. |
| rbac.roleBinding.create | string | `nil` | Per-object override for binding creation. Accepted values: `true`, `false`, `null`. |
| rbac.roleBinding.kind | string | `""` | `""` means auto-select: `RoleBinding` for `Role`, `ClusterRoleBinding` for `ClusterRole`. |
| rbac.roleBinding.name | string | `""` | RBAC binding name override. Defaults to the chart fullname. |
| rbac.roleBinding.namespace | string | `""` | RBAC binding namespace override. Defaults to `common.namespace`. Ignored for `ClusterRoleBinding`. |
| replicaCount | int | `1` | This will set the replicaset count more information can be found here: https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/ |
| resources | object | `{}` | This define resource for your application **(BE CAREFUL TO SET THIS VALUE)** Best practice: Not set **cpu limit** for preventing CPU Throttle,  set **memory request/limit** for bring up and preventing OOM. For more information checkout: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/ |
| revisionHistoryLimit | string | `nil` | Number of old ReplicaSets kept for `kubectl rollout undo`. Leave `null` to use the Kubernetes default (`10`). |
| runtimeArgs | list | `[]` | This will set the runtimeArgs for your application Let it null if you feel pleasure with cmd command in your application Add more if you want to override it |
| runtimeClassName | string | `""` | RuntimeClass for the pods, for more information: https://kubernetes.io/docs/concepts/containers/runtime-class/ Leave empty to use the node's default container runtime handler (the right choice for most workloads). Set it when the workload needs a specific runtime handler, and the RuntimeClass must already exist in the cluster: 1. GPU via device plugin: use the `nvidia` RuntimeClass (created by the NVIDIA GPU Operator; on K3s/RKE2 the bundled containerd    registers an `nvidia` handler when nvidia-container-runtime is installed, check with `kubectl get runtimeclass`).    Pair it with `resources.limits` (e.g. `nvidia.com/gpu: 1`) and GPU `tolerations` / `nodeSelector`. 2. Sandboxed runtimes such as `gvisor` or `kata`. A RuntimeClass with `scheduling.nodeSelector` / `tolerations` also steers pods onto nodes that have that runtime. |
| schedulerName | string | `""` | Scheduler that places the pods. Leave empty to use the cluster default (`default-scheduler`). |
| securityContext | object | `{}` | This defines the security options the ephemeral container should be run with.  If set, the fields of SecurityContext override the equivalent fields of PodSecurityContext. For more information checkout: https://kubernetes.io/docs/tasks/configure-pod-container/security-context/ |
| service | object | `{"enabled":true,"externalName":"","headless":false,"port":80,"ports":[],"primaryPortName":"","targetPort":"http","type":"ClusterIP"}` | This is for setting up a service more information can be found here: https://kubernetes.io/docs/concepts/services-networking/service/ |
| service.enabled | bool | `true` | Enable service creation |
| service.externalName | string | `""` | External DNS name used only when `service.type=ExternalName`. |
| service.headless | bool | `false` | Set this to true to create a headless service |
| service.port | int | `80` | Legacy single service port. When `service.ports` is empty, this port is exposed and targets `service.targetPort`. |
| service.ports | list | `[]` | Explicit service ports. Use this when you need multiple service ports or non-default targetPort mappings. |
| service.primaryPortName | string | `""` | Leave empty to use the first entry from `service.ports`. |
| service.targetPort | string | `"http"` | Legacy single service targetPort. Accepted values: a container port name such as `http` or a numeric port such as `3000`. Defaults to `http` when not set. |
| service.type | string | `"ClusterIP"` | Kubernetes Service type. Accepted values: `ClusterIP`, `NodePort`, `LoadBalancer`, `ExternalName`. |
| serviceAccount | object | `{"annotations":{},"automount":true,"create":true,"name":""}` | This section builds out the service account more information can be found here: https://kubernetes.io/docs/concepts/security/service-accounts/ |
| serviceAccount.annotations | object | `{}` | Annotations to add to the service account |
| serviceAccount.automount | bool | `true` | Automatically mount a ServiceAccount's API credentials? |
| serviceAccount.create | bool | `true` | Specifies whether a service account should be created |
| serviceAccount.name | string | `""` | If not set and create is true, a name is generated using the fullname template |
| serviceMonitor | object | `{"annotations":{},"enabled":false,"honorLabels":false,"interval":"30s","labels":{},"metricRelabelings":[],"namespace":"","path":"/metrics","port":"metrics","relabelings":[],"scheme":"","scrapeTimeout":"","tlsConfig":{}}` | Prometheus Operator `ServiceMonitor` that scrapes the Service, more information: https://prometheus-operator.dev/docs/developer/getting-started/ Requires the Prometheus Operator CRDs (e.g. kube-prometheus-stack) and `service.enabled=true`. Enable `serviceMonitor` or `podMonitor` for the same metrics port, not both, otherwise every target is scraped twice. |
| serviceMonitor.annotations | object | `{}` | Annotations to add to the ServiceMonitor |
| serviceMonitor.enabled | bool | `false` | Enable ServiceMonitor creation |
| serviceMonitor.honorLabels | bool | `false` | Keep the labels exposed by the target when they conflict with Prometheus target labels |
| serviceMonitor.interval | string | `"30s"` | Scrape interval. Empty uses the Prometheus default. |
| serviceMonitor.labels | object | `{}` | Extra labels, e.g. `release: kube-prometheus-stack` so that Prometheus' `serviceMonitorSelector` picks it up |
| serviceMonitor.metricRelabelings | list | `[]` | Relabelings applied to scraped samples before ingestion |
| serviceMonitor.namespace | string | `""` | Namespace for the ServiceMonitor. Empty means the release namespace; when set, `namespaceSelector` targets the release namespace. |
| serviceMonitor.path | string | `"/metrics"` | HTTP path of the metrics endpoint |
| serviceMonitor.port | string | `"metrics"` | Service port **name** to scrape. Must exist in `service.ports` (or be `http` for the legacy single `service.port`). |
| serviceMonitor.relabelings | list | `[]` | Relabelings applied before scraping |
| serviceMonitor.scheme | string | `""` | Scrape scheme (`http` or `https`). Empty uses `http`. |
| serviceMonitor.scrapeTimeout | string | `""` | Scrape timeout, must be lower than `interval`. Empty uses the Prometheus default. |
| serviceMonitor.tlsConfig | object | `{}` | TLS settings for `https` scraping |
| strategy | object | `{}` | Deployment update strategy, more information can be found here: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#strategy Accepted `type` values: `RollingUpdate` (Kubernetes default) or `Recreate`. `rollingUpdate` must be empty when `type` is `Recreate`. |
| terminationGracePeriodSeconds | string | `nil` | Seconds the pod gets to shut down after SIGTERM (the `lifecycle.preStop` hook counts against it) before it is killed. Leave `null` to use the Kubernetes default (`30`). |
| testConnection | bool | `false` | To enable/disable the testconnection for deployment |
| tolerations | list | `[]` | Set for deploy your application into `taint` node, for more information: https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/ |
| topologySpreadConstraints | list | `[]` | Spread pods across nodes or zones, for more information: https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/ When a constraint omits `labelSelector`, the chart's selector labels are used, so pods of this release spread against each other. |
| vault | object | `{"config":{"authPath":"auth/kubernetes","namespace":"default","path":"secret/data/project","role":"vault-role","serviceServer":"https://vault.svc.cluster.local:8200"},"enabled":false,"template":{"content":"{{ with secret \"secret/data/project\" }}\n{{- range $key, $value := .Data.data }}\nexport {{ $key }}={{ $value }}\n{{- end }}\n{{- end }}","name":"config.env"}}` | Setup Vault Agent sidecar for injecting secrets into your application More information can be found here: https://developer.hashicorp.com/vault/docs/deploy/kubernetes/injector More annotation with Vault Injector Configuration here: https://developer.hashicorp.com/vault/docs/deploy/kubernetes/injector/annotations |
| volumeMounts | list | `[]` | Additional volumeMounts on the output Deployment definition. |
| volumes | list | `[]` | Additional volumes on the output Deployment definition. |

