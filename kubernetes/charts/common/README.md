# common

![Version: 0.1.3](https://img.shields.io/badge/Version-0.1.3-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.0.0](https://img.shields.io/badge/AppVersion-1.0.0-informational?style=flat-square)

A Helm chart for Kubewekend's application

## Installing the Chart

To install the chart with the release name `appwekend`:

```console
$ helm repo add kubewekend https://kubewekend.xeusnguyen.xyz
$ helm install appwekend kubewekend/common
```

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
| deploymentType | string | `"deployment"` | Definition what type of your application (e.g: deployment, statefulset or daemonset) |
| enabled | bool | `true` | This will define Chart enabled or not |
| env | object | `{}` | This sets the environment for your deployment For more information checkout: https://kubernetes.io/docs/tasks/inject-data-application/define-environment-variable-container/ |
| extraManifests | object | `{}` | To add your extra manifest into your applications |
| fullnameOverride | string | `""` |  |
| image | object | `{"pullPolicy":"IfNotPresent","repository":"nginx","tag":"latest"}` | This sets the container image more information can be found here: https://kubernetes.io/docs/concepts/containers/images/ |
| image.pullPolicy | string | `"IfNotPresent"` | This sets the pull policy for images. |
| image.tag | string | `"latest"` | Overrides the image tag whose default is the chart appVersion. |
| imagePullSecrets | list | `[]` | This is for the secretes for pulling an image from a private repository more information can be found here: https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/ |
| ingress | object | `{"annotations":{},"className":"","enabled":false,"hosts":[{"host":"chart-example.local","paths":[{"path":"/","pathType":"ImplementationSpecific"}]}],"tls":[]}` | This block is for setting up the ingress for more information can be found here: https://kubernetes.io/docs/concepts/services-networking/ingress/ |
| nameOverride | string | `""` | This is to override the chart name. |
| nodeSelector | object | `{}` | Choose your node to deloy application depend on `label`, for more information: https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#nodeselector |
| podAnnotations | object | `{}` | This is for setting Kubernetes Annotations to a Pod. For more information checkout: https://kubernetes.io/docs/concepts/overview/working-with-objects/annotations/  |
| podLabels | object | `{}` | This is for setting Kubernetes Labels to a Pod. For more information checkout: https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/ |
| podSecurityContext | object | `{}` | This holds pod-level security attributes and common container settings. |
| probes | object | `{"disableProbes":[],"livenessProbe":{"failureThreshold":30,"httpGet":{"path":"/","port":"http"},"initialDelaySeconds":15,"periodSeconds":15,"successThreshold":1,"timeoutSeconds":10},"readinessProbe":{"failureThreshold":30,"httpGet":{"path":"/","port":"http"},"initialDelaySeconds":15,"periodSeconds":15,"successThreshold":1,"timeoutSeconds":10},"startupProbe":{"failureThreshold":30,"httpGet":{"path":"/","port":"http"},"periodSeconds":10,"timeoutSeconds":5}}` | This is to setup the liveness,readiness and startupProbe probes  More information can be found here: https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/ |
| probes.disableProbes | list | `[]` | Probe list that you want to disable, accepted values: "livenessProbe", "readinessProbe", "startupProbe", "all" Ex: ["livenessProbe", "readinessProbe"] -> enable `startupProbe` only |
| probesOverride | object | `{}` | This set the override probes base on your decision |
| rbac | object | `{"create":false}` | To enable/disable the rbac for deployment |
| replicaCount | int | `1` | This will set the replicaset count more information can be found here: https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/ |
| resources | object | `{}` | This define resource for your application **(BE CAREFUL TO SET THIS VALUE)** Best practice: Not set **cpu limit** for preventing CPU Throttle,  set **memory request/limit** for bring up and preventing OOM. For more information checkout: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/ |
| runtimeArgs | list | `[]` | This will set the runtimeArgs for your application Let it null if you feel pleasure with cmd command in your application Add more if you want to override it |
| securityContext | object | `{}` | This defines the security options the ephemeral container should be run with.  If set, the fields of SecurityContext override the equivalent fields of PodSecurityContext. For more information checkout: https://kubernetes.io/docs/tasks/configure-pod-container/security-context/ |
| service | object | `{"port":80,"type":"ClusterIP"}` | This is for setting up a service more information can be found here: https://kubernetes.io/docs/concepts/services-networking/service/ |
| service.port | int | `80` | This sets the ports more information can be found here: https://kubernetes.io/docs/concepts/services-networking/service/#field-spec-ports |
| service.type | string | `"ClusterIP"` | This sets the service type more information can be found here: https://kubernetes.io/docs/concepts/services-networking/service/#publishing-services-service-types |
| serviceAccount | object | `{"annotations":{},"automount":true,"create":true,"name":""}` | This section builds out the service account more information can be found here: https://kubernetes.io/docs/concepts/security/service-accounts/ |
| serviceAccount.annotations | object | `{}` | Annotations to add to the service account |
| serviceAccount.automount | bool | `true` | Automatically mount a ServiceAccount's API credentials? |
| serviceAccount.create | bool | `true` | Specifies whether a service account should be created |
| serviceAccount.name | string | `""` | If not set and create is true, a name is generated using the fullname template |
| testConnection | bool | `false` | To enable/disable the testconnection for deployment |
| tolerations | list | `[]` | Set for deploy your application into `taint` node, for more information: https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/ |
| volumeMounts | list | `[]` | Additional volumeMounts on the output Deployment definition. |
| volumes | list | `[]` | Additional volumes on the output Deployment definition. |

