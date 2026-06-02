# common

![Version: 0.3.0](https://img.shields.io/badge/Version-0.3.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)

A Helm chart for Kubewekend's application

## Installing the Chart

To install the chart with the release name `appwekend`:

```console
$ helm repo add kubewekend https://kubewekend.xeusnguyen.xyz
$ helm install appwekend kubewekend/common
```

**Homepage:** <https://github.com/xeusnguyen/kubewekend>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Xeus Nguyen | <xeusnguyen@gmail.com> | <https://wiki.xeusnguyen.xyz> |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Functions like the nodeSelector field but is more expressive and allows you to specify soft rules, for more information: https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#affinity-and-anti-affinity |
| autoscaling | object | `{"enabled":false,"maxReplicas":100,"minReplicas":1,"targetCPUUtilizationPercentage":80}` | This section is for setting up autoscaling more information can be found here: https://kubernetes.io/docs/concepts/workloads/autoscaling/ |
| command | list | `[]` | This will set the command for your application Let it null if you already have entrypoint or cmd in your application For more information checkout: https://kubernetes.io/docs/tasks/inject-data-application/define-command-argument-container/ |
| containerPorts | list | `[]` | Additional container ports exposed by the main application container. If empty, the chart falls back to a single port derived from `service.port` when `service.enabled` is true. If you keep the default HTTP probes or Service targetPort behavior, include a port named `http`. |
| deploymentType | string | `"deployment"` | Workload type for this chart. Accepted values: `deployment`. `statefulset` and `daemonset` are not implemented in this chart yet. |
| enabled | bool | `true` | This will define Chart enabled or not |
| env | object | `{}` | This sets the environment for your deployment For more information checkout: https://kubernetes.io/docs/tasks/inject-data-application/define-environment-variable-container/ |
| envFrom | list | `[]` | This sets the envFrom for your deployment, but load entire configmap or secret as environment variables ref: https://kubernetes.io/docs/tasks/inject-data-application/define-environment-variable-container/ |
| extraManifests | object | `{}` | To add your extra manifest into your applications |
| fullnameOverride | string | `""` |  |
| image | object | `{"pullPolicy":"IfNotPresent","repository":"nginx","tag":"latest"}` | This sets the container image more information can be found here: https://kubernetes.io/docs/concepts/containers/images/ |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. Accepted values: `Always`, `IfNotPresent`, `Never`. |
| image.tag | string | `"latest"` | Overrides the image tag whose default is the chart appVersion. |
| imagePullSecrets | list | `[]` | This is for the secretes for pulling an image from a private repository more information can be found here: https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/ |
| ingress | object | `{"annotations":{},"className":"","enabled":false,"hosts":[{"host":"chart-example.local","paths":[{"path":"/","pathType":"ImplementationSpecific"}]}],"tls":[]}` | This block is for setting up the ingress for more information can be found here: https://kubernetes.io/docs/concepts/services-networking/ingress/ |
| nameOverride | string | `""` | This is to override the chart name. |
| nodeSelector | object | `{}` | Choose your node to deloy application depend on `label`, for more information: https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#nodeselector |
| pdb | object | `{"create":false,"maxUnavailable":0,"minAvailable":1}` | Setup Pod Disruption Budget for your application More information can be found here: https://kubernetes.io/docs/concepts/workloads/pods/disruptions/ |
| podAnnotations | object | `{}` | This is for setting Kubernetes Annotations to a Pod. For more information checkout: https://kubernetes.io/docs/concepts/overview/working-with-objects/annotations/  |
| podLabels | object | `{}` | This is for setting Kubernetes Labels to a Pod. For more information checkout: https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/ |
| podSecurityContext | object | `{}` | This holds pod-level security attributes and common container settings. |
| probes | object | `{"disableProbes":[],"livenessProbe":{"failureThreshold":30,"httpGet":{"path":"/","port":"http"},"initialDelaySeconds":15,"periodSeconds":15,"successThreshold":1,"timeoutSeconds":10},"port":"","readinessProbe":{"failureThreshold":30,"httpGet":{"path":"/","port":"http"},"initialDelaySeconds":15,"periodSeconds":15,"successThreshold":1,"timeoutSeconds":10},"startupProbe":{"failureThreshold":30,"httpGet":{"path":"/","port":"http"},"periodSeconds":10,"timeoutSeconds":5}}` | This is to setup the liveness,readiness and startupProbe probes  More information can be found here: https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/ |
| probes.disableProbes | list | `[]` | Probe list to disable. Accepted values: `livenessProbe`, `readinessProbe`, `startupProbe`, `all`. Ex: ["livenessProbe", "readinessProbe"] -> enable `startupProbe` only |
| probes.port | string | `""` | Leave empty to auto-select `http`, otherwise the first declared container port name, then the first container port number. |
| probesOverride | object | `{}` | This set the override probes base on your decision |
| rbac | object | `{"create":false,"role":{"annotations":{},"create":null,"kind":"Role","rules":[]},"roleBinding":{"annotations":{},"create":null,"kind":"","roleRef":{},"subjects":[]}}` | RBAC configuration for this workload. Common patterns: 1. Create both Role/ClusterRole and RoleBinding/ClusterRoleBinding: `rbac.create=true` 2. Create only a binding to a pre-existing role: `rbac.create=false`, `rbac.roleBinding.create=true` 3. Create only the role object: `rbac.create=false`, `rbac.role.create=true` |
| rbac.create | bool | `false` | This is used as the fallback for `rbac.role.create` and `rbac.roleBinding.create` when those values are `null`. |
| rbac.role.create | string | `nil` | Per-object override for role creation. Accepted values: `true`, `false`, `null`. |
| rbac.role.kind | string | `"Role"` | RBAC role kind. Accepted values: `Role`, `ClusterRole`. |
| rbac.roleBinding.create | string | `nil` | Per-object override for binding creation. Accepted values: `true`, `false`, `null`. |
| rbac.roleBinding.kind | string | `""` | `""` means auto-select: `RoleBinding` for `Role`, `ClusterRoleBinding` for `ClusterRole`. |
| replicaCount | int | `1` | This will set the replicaset count more information can be found here: https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/ |
| resources | object | `{}` | This define resource for your application **(BE CAREFUL TO SET THIS VALUE)** Best practice: Not set **cpu limit** for preventing CPU Throttle,  set **memory request/limit** for bring up and preventing OOM. For more information checkout: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/ |
| runtimeArgs | list | `[]` | This will set the runtimeArgs for your application Let it null if you feel pleasure with cmd command in your application Add more if you want to override it |
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
| testConnection | bool | `false` | To enable/disable the testconnection for deployment |
| tolerations | list | `[]` | Set for deploy your application into `taint` node, for more information: https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/ |
| vault | object | `{"config":{"authPath":"auth/kubernetes","namespace":"default","path":"secret/data/project","role":"vault-role","serviceServer":"https://vault.svc.cluster.local:8200"},"enabled":false,"template":{"content":"{{ with secret \"secret/data/project\" }}\n{{- range $key, $value := .Data.data }}\nexport {{ $key }}={{ $value }}\n{{- end }}\n{{- end }}","name":"config.env"}}` | Setup Vault Agent sidecar for injecting secrets into your application More information can be found here: https://developer.hashicorp.com/vault/docs/deploy/kubernetes/injector More annotation with Vault Injector Configuration here: https://developer.hashicorp.com/vault/docs/deploy/kubernetes/injector/annotations |
| volumeMounts | list | `[]` | Additional volumeMounts on the output Deployment definition. |
| volumes | list | `[]` | Additional volumes on the output Deployment definition. |

