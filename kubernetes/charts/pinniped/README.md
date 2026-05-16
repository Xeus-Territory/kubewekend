# pinniped

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: v0.46.0](https://img.shields.io/badge/AppVersion-v0.46.0-informational?style=flat-square)

A Helm chart for Pinniped, a Kubernetes authentication via ImpersonationProxy with Supervisor and Concierge components.

>[!NOTE]
>This chart bootstraps the Pinniped Concierge and Supervisor server-side resources on Kubernetes. CRDs can be managed by this chart using `installCRDs=true`. Set `installCRDs=false` when CRDs are installed separately or managed outside Helm.

>[!INFO]
>The main customization surface lives in `values.yaml` under the `concierge` and `supervisor` sections.

## Networking requirements

Pinniped expects end-to-end TLS. When exposing the Supervisor or Concierge through an ingress controller, use TCP/TLS passthrough instead of regular Layer 7 HTTP termination.

This chart supports four exposure patterns per component:

- `traefik`: renders an `IngressRouteTCP` with `tls.passthrough=true`. This is the recommended option because it is a native Layer 4/TCP resource.
- `nginx`: renders a standard `Ingress` with `nginx.ingress.kubernetes.io/ssl-passthrough: "true"`. This requires the NGINX Ingress Controller to be started with `--enable-ssl-passthrough`.
- `loadBalancer`: uses the Kubernetes `Service` type `LoadBalancer`. This is useful on AWS or other clouds when you already run a load balancer controller and want to pass controller-specific annotations or `loadBalancerClass` values.
- `gateway-api`: renders a Gateway API route. The chart supports both `TLSRoute` and `TCPRoute` styles through `*.ingress.gatewayAPI.routeKind`.

The chart does not force any controller. Leave `concierge.ingress.enabled=false` and `supervisor.ingress.enabled=false` if you prefer to expose Pinniped only through a `LoadBalancer`, `NodePort`, or another TCP proxy.

### LoadBalancer notes

For cloud-native exposure, use the `service.*.loadBalancer.*` values.

- `supervisor.service.public.loadBalancer.annotations` lets you pass AWS Load Balancer Controller annotations such as `service.beta.kubernetes.io/aws-load-balancer-scheme`.
- `supervisor.service.public.loadBalancer.loadBalancerClass` can be used with implementations like AWS NLB.
- `concierge.service.proxy.*` provides the same controls when the Concierge impersonation proxy is exposed directly.

### Gateway API notes

To use Gateway API, set `*.ingress.provider=gateway-api` and `*.ingress.gatewayAPI.enabled=true`, then provide at least one `parentRef`.

- Use `routeKind: TLSRoute` when your Gateway implementation supports TLS passthrough with SNI matching.
- Use `routeKind: TCPRoute` when you want pure TCP forwarding and your Gateway implementation does not support `TLSRoute`.
- The backend service will be selected from the chart values, or you can force it with `*.ingress.service.name`.

## TLS certificate options

Pinniped still needs certificates even when TCP passthrough is used, because TLS terminates inside the Pinniped pods.

This chart provides optional cert-manager integration, but does not require cert-manager as a chart dependency.

- Set `supervisor.tls.certManager.enabled=true` to create a `Certificate` for the Supervisor `defaultTLSCertificateSecret`.
- Set `concierge.tls.certManager.enabled=true` to create a `Certificate` for the Concierge impersonation proxy TLS secret.
- Set `*.tls.certManager.createSelfSignedIssuer=true` to let the chart create a simple self-signed `Issuer` in the component namespace.

If you already have your own issuer, set `*.tls.certManager.issuerRef.*` and keep `createSelfSignedIssuer=false`.

## Example

```yaml
supervisor:
  ingress:
    enabled: true
    provider: traefik
    hostname: supervisor.example.com
  tls:
    certManager:
      enabled: true
      createSelfSignedIssuer: true

concierge:
  ingress:
    enabled: true
    provider: nginx
    className: nginx
    hostname: concierge.example.com
  tls:
    certManager:
      enabled: true
      createSelfSignedIssuer: true
```

## Authentication configuration

After deploying the Supervisor, configure it as an OIDC issuer by creating a `FederationDomain` and connecting one or more identity providers. Then create a `JWTAuthenticator` on each downstream Concierge to trust those tokens.

### FederationDomain

The `FederationDomain` is the public OIDC issuer URL published by the Supervisor. Its `issuer` field must be a fully qualified HTTPS URL reachable by end-users and by Concierge clusters.

```yaml
supervisor:
  federationDomain:
    create: true
    issuer: https://supervisor.example.com
    # tlsSecretName defaults to the cert-manager-managed secret when
    # supervisor.tls.certManager.enabled=true. Override only when needed.
    tlsSecretName: ""
```

### Identity providers

Enable exactly the IDPs your environment needs. Enabled IDPs are automatically registered in the FederationDomain's `identityProviders` list.

#### Dex (OIDC)

```yaml
supervisor:
  identityProviders:
    dex:
      create: true
      name: dex
      displayName: "Dex"
      issuer: https://dex.example.com
      # certificateAuthorityData: "<base64-pem>"  # omit if Dex uses a public CA
      additionalScopes: [offline_access, groups, email]
      allowPasswordGrant: false
      usernameClaim: email
      groupsClaim: groups
      createClientSecret: true
      clientID: pinniped
      clientSecret: "<dex-client-secret>"
```

#### GitHub

```yaml
supervisor:
  identityProviders:
    github:
      create: true
      name: github
      displayName: "GitHub"
      organizationPolicy: OnlyUsersFromAllowedOrganizations
      allowedOrganizations:
        - my-org
      usernameClaim: "login:id"
      groupsClaim: slug
      createClientSecret: true
      clientID: "<github-app-client-id>"
      clientSecret: "<github-app-client-secret>"
```

Set `host` and `certificateAuthorityData` when using GitHub Enterprise Server instead of `github.com`.

#### LDAP

```yaml
supervisor:
  identityProviders:
    ldap:
      create: true
      name: openldap
      displayName: "LDAP"
      host: "ldap.example.com:636"
      # certificateAuthorityData: "<base64-pem>"  # omit if using a public CA
      userSearch:
        base: "ou=users,dc=example,dc=com"
        filter: "&(objectClass=inetOrgPerson)(uid={})"
        usernameAttribute: uid
        uidAttribute: uidNumber
      groupSearch:
        base: "ou=groups,dc=example,dc=com"
        filter: "&(objectClass=groupOfNames)(member={})"
        groupNameAttribute: cn
      createBindSecret: true
      bindUsername: "cn=admin,dc=example,dc=com"
      bindPassword: "<bind-password>"
```

### JWTAuthenticator (Concierge)

Create one `JWTAuthenticator` per downstream Concierge cluster. Its `issuer` must exactly match `supervisor.federationDomain.issuer`.

```yaml
concierge:
  jwtAuthenticator:
    create: true
    name: supervisor-jwt-authenticator
    issuer: https://supervisor.example.com
    audience: my-cluster          # unique identifier for this cluster
    # certificateAuthorityData: "<base64-pem>"
    # Omit certificateAuthorityData when the Supervisor uses a publicly trusted CA.
    # For dynamic rotation, reference a Secret or ConfigMap instead:
    # certificateAuthorityDataSource:
    #   kind: Secret
    #   name: pinniped-supervisor-default-tls-certificate
    #   key: ca.crt
```

> **TLS trust note**: When `supervisor.tls.certManager.enabled=true` with a public CA issuer (e.g. Let's Encrypt), you can omit `certificateAuthorityData` entirely because the CA is already trusted by default. Only set it when using a private or self-signed CA.

Gateway API example:

```yaml
supervisor:
	ingress:
		enabled: true
		provider: gateway-api
		hostname: supervisor.example.com
		gatewayAPI:
			enabled: true
			routeKind: TLSRoute
			parentRefs:
				- name: main-gateway
					sectionName: https
```

AWS/NLB-style load balancer example:

```yaml
supervisor:
	service:
		public:
			loadBalancer:
				enabled: true
				loadBalancerClass: service.k8s.aws/nlb
				annotations:
					service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
```

## Pinniped Note

Explore more about Pinniped at https://pinniped.dev/ and the official architecture at https://pinniped.dev/docs/background/architecture/ to understand how the Concierge and Supervisor components work together to provide secure Kubernetes authentication.

Pinniped is a open-source project under the VMware and it has many installation options. This chart is customized base on my experience, so you can find the more options at
1. The official documentation: https://pinniped.dev/docs/howto/install-concierge/ and https://pinniped.dev/docs/howto/install-supervisor/
2. Bitnami's chart: https://artifacthub.io/packages/helm/bitnami/pinniped

By default, this chart will not create and expose services and ingress for both Concierge and Supervisor, and sometime it look noisy if you don't cover the documentation well, so that is why I share this chart to make it easier for you to get started with Pinniped and customize it for your needs. With more configuration options for

1. Setup Service and Ingress with different providers and patterns, such as Traefik, NGINX, Gateway API, and LoadBalancer at Layer 4/TCP with SSL Passthrough
2. Setup TLS certificates with cert-manager integration, including self-signed issuers for local development and testing. Because Pinniped requires end-to-end TLS, so you can use cert-manager to automate certificate management for both the Supervisor and Concierge components.
3. Support you modify configuration for both Supervisor and Concierge components seperately, it help you prevent errors for mismatch in configuration for couple of situations, such as

Your concierge is exposed through Impersonation Proxy, but with the default chart, it will support for type: LoadBalancer, it means you need another loadbalancer controller to help you create new load balancer, such as metalLB, AWS Load Balancer Controller, or other cloud load balancer controller. But when you read about [Pinniped API](https://github.com/vmware/pinniped/tree/main/generated/latest), it will show you more configuration instead of just `type: LoadBalancer`, it also support for `ClusterIP` and `None`, it means use can use `ClusterIP` and expose it through your own ingress controller with `externalEndpoint` add-on, by default this value will be set be served using the external name of the LoadBalancer service or the cluster service DNS name.

That why, you can change this one to expose the Concierge right way for support Impersonation Proxy, instead encounter problems with LoadBalancer for this one, and also ignore unsupport cluster which don't include any `kube-controller-manager` which not let pinniped interact when create new `kubeconfig` for your users.

```yaml
  # -- CredentialIssuer bootstrap resource for Concierge impersonation support.
  credentialIssuer:
    create: true
    impersonationProxy:
      mode: enabled
      externalEndpoint: "concierge-endpoint.example.com"
      service:
        type: ClusterIP
```

## Installing the Chart

To install the chart with the release name `pinniped`:

```bash
helm repo add kubewekend https://kubewekend.xeusnguyen.xyz
helm install pinniped kubewekend/pinniped
```

For local rendering/testing:

```bash
helm template pinniped . -f values.yaml
helm lint .
```

## Uninstalling the Chart

```bash
helm uninstall pinniped
```

## Also preference

- [Pinniped Documentation](https://pinniped.dev/docs/)
- [Using Pinniped for authentication against Talos-based Kubernetes clusters](https://dickingwithdocker.com/posts/pinniped-authentication-against-talos-clusters/)
- [OpenUnison - Deploying The Authentication Portal](https://openunison.github.io/deployauth/)
- [Pinniped: A Unified Framework for User Authentication to Kubernetes Cluster- Mo Khan & Anjali Telang](https://www.youtube.com/watch?v=2fI_XOGEoIU)
- [Pinniped - Concierge with Supervisor Locally](https://pinniped.dev/docs/tutorials/local-concierge-and-supervisor-demo/)

## Alternative solutions

- [Kubelogin](https://github.com/int128/kubelogin): kubectl plugin for Kubernetes OpenID Connect authentication (kubectl oidc-login)
- [kube-oidc-proxy](https://github.com/jetstack/kube-oidc-proxy/tree/master): Reverse proxy to authenticate to managed Kubernetes API servers via OIDC.
- [OpenUnison](https://openunison.github.io/): OpenUnison provides SSO and authentication for your Kubernetes clusters, no matter where they run or how your users need to authenticate.
- [gangway](https://github.com/vmware-archive/gangway): An application that can be used to easily enable authentication flows via OIDC for a kubernetes cluster.
- [paralus](https://github.com/paralus/paralus): All-in-one Kubernetes access manager. User-level credentials, RBAC, SSO, audit logs.
- [dex-k8s-authenticator](https://github.com/mintel/dex-k8s-authenticator): A Kubernetes Dex Client Authenticator

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Xeus Nguyen | <xeusnguyen@gmail.com> | <https://wiki.xeusnguyen.xyz> |

## Source Code

* <https://github.com/vmware/pinniped>

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| commonLabels | object | `{}` | Common labels applied to all rendered resources. |
| concierge | object | `{"config":{"allowedCiphersForTLSOneDotTwo":[],"apiGroupSuffix":"pinniped.dev","apiServingCertificateDurationSeconds":2592000,"apiServingCertificateRenewBeforeSeconds":2160000,"audit":{"logUsernamesAndGroups":"disabled"},"discoveryURL":"","httpsProxy":"","kubeCertAgentImage":"","kubeCertAgentPriorityClassName":"","logLevel":"","noProxy":"$(KUBERNETES_SERVICE_HOST),169.254.169.254,127.0.0.1,localhost,.svc,.cluster.local"},"containerSecurityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsNonRoot":true,"seccompProfile":{"type":"RuntimeDefault"}},"credentialIssuer":{"create":true,"impersonationProxy":{"externalEndpoint":"","mode":"auto","service":{"annotations":{"service.beta.kubernetes.io/aws-load-balancer-connection-idle-timeout":"4000"},"loadBalancerIP":"","type":"LoadBalancer"}}},"customLabels":{},"enabled":true,"image":{"digest":"","pullPolicy":"IfNotPresent","repository":"ghcr.io/vmware/pinniped/pinniped-server","tag":""},"imagePullSecret":{"create":false,"dockerconfigjson":"","name":"image-pull-secret"},"ingress":{"annotations":{},"enabled":false,"gatewayAPI":{"apiVersion":"gateway.networking.k8s.io/v1beta1","enabled":false,"hostnames":[],"parentRefs":[],"routeKind":"TLSRoute","routeName":"","sectionName":""},"hostname":"","hosts":[],"nginx":{"backendProtocol":"HTTPS","path":"/","pathType":"Prefix","sslPassthrough":"true","tlsSecretName":""},"provider":"traefik","service":{"name":"","port":443},"tls":[],"traefik":{"entryPoints":["websecure"],"match":"","tlsPassthrough":true,"tlsSecretName":""}},"jwtAuthenticator":{"audience":"","certificateAuthorityData":"","certificateAuthorityDataSource":{"key":"","kind":"","name":""},"create":false,"issuer":"","name":"supervisor-jwt-authenticator"},"nameOverride":"","podSecurityContext":{"runAsGroup":65532,"runAsUser":65532},"replicaCount":2,"resources":{"limits":{"cpu":"100m","memory":"128Mi"},"requests":{"cpu":"100m","memory":"128Mi"}},"service":{"api":{"port":443,"targetPort":10250},"proxy":{"annotations":{},"enabled":true,"externalTrafficPolicy":"","loadBalancerClass":"","loadBalancerIP":"","loadBalancerSourceRanges":[],"port":443,"targetPort":8444,"type":"ClusterIP"}},"tls":{"certManager":{"certificate":{"commonName":"","dnsNames":[],"duration":"","enabled":true,"privateKey":{"algorithm":"RSA","size":2048},"renewBefore":"","secretName":""},"createSelfSignedIssuer":false,"enabled":false,"issuerRef":{"group":"cert-manager.io","kind":"Issuer","name":""}},"secretNames":{"api":"","impersonationProxy":""}}}` | Pinniped Concierge component configuration. |
| concierge.config | object | `{"allowedCiphersForTLSOneDotTwo":[],"apiGroupSuffix":"pinniped.dev","apiServingCertificateDurationSeconds":2592000,"apiServingCertificateRenewBeforeSeconds":2160000,"audit":{"logUsernamesAndGroups":"disabled"},"discoveryURL":"","httpsProxy":"","kubeCertAgentImage":"","kubeCertAgentPriorityClassName":"","logLevel":"","noProxy":"$(KUBERNETES_SERVICE_HOST),169.254.169.254,127.0.0.1,localhost,.svc,.cluster.local"}` | Concierge static configuration rendered into the Pinniped config file. |
| concierge.config.allowedCiphersForTLSOneDotTwo | list | `[]` | Allowed TLS 1.2 cipher suites for Concierge. Empty uses Pinniped defaults. |
| concierge.config.apiGroupSuffix | string | `"pinniped.dev"` | API group suffix for Concierge APIs. |
| concierge.config.apiServingCertificateDurationSeconds | int | `2592000` | Lifetime of the Concierge API serving certificate in seconds. |
| concierge.config.apiServingCertificateRenewBeforeSeconds | int | `2160000` | Renew-before interval of the Concierge API serving certificate in seconds. |
| concierge.config.audit | object | `{"logUsernamesAndGroups":"disabled"}` | Concierge audit logging configuration. |
| concierge.config.audit.logUsernamesAndGroups | string | `"disabled"` | Include usernames and groups in Concierge audit logs. |
| concierge.config.discoveryURL | string | `""` | Override the Kubernetes discovery URL published by Concierge. |
| concierge.config.httpsProxy | string | `""` | HTTPS proxy used by Concierge for outbound requests. |
| concierge.config.kubeCertAgentImage | string | `""` | Override the kube-cert-agent image used by Concierge. |
| concierge.config.kubeCertAgentPriorityClassName | string | `""` | PriorityClass name assigned to kube-cert-agent pods. |
| concierge.config.logLevel | string | `""` | Concierge log level. Leave empty for Pinniped defaults. |
| concierge.config.noProxy | string | `"$(KUBERNETES_SERVICE_HOST),169.254.169.254,127.0.0.1,localhost,.svc,.cluster.local"` | NO_PROXY list used by Concierge for outbound requests. |
| concierge.containerSecurityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsNonRoot":true,"seccompProfile":{"type":"RuntimeDefault"}}` | Container-level security context for the Concierge container. |
| concierge.containerSecurityContext.allowPrivilegeEscalation | bool | `false` | Disable privilege escalation in the Concierge container. |
| concierge.containerSecurityContext.capabilities | object | `{"drop":["ALL"]}` | Linux capabilities configuration for the Concierge container. |
| concierge.containerSecurityContext.capabilities.drop | list | `["ALL"]` | Capabilities dropped from the Concierge container. |
| concierge.containerSecurityContext.readOnlyRootFilesystem | bool | `true` | Mount the root filesystem as read-only. |
| concierge.containerSecurityContext.runAsNonRoot | bool | `true` | Require the Concierge container to run as a non-root user. |
| concierge.containerSecurityContext.seccompProfile | object | `{"type":"RuntimeDefault"}` | Seccomp profile applied to the Concierge container. |
| concierge.containerSecurityContext.seccompProfile.type | string | `"RuntimeDefault"` | Seccomp profile type. |
| concierge.credentialIssuer | object | `{"create":true,"impersonationProxy":{"externalEndpoint":"","mode":"auto","service":{"annotations":{"service.beta.kubernetes.io/aws-load-balancer-connection-idle-timeout":"4000"},"loadBalancerIP":"","type":"LoadBalancer"}}}` | CredentialIssuer bootstrap resource for Concierge impersonation support. |
| concierge.credentialIssuer.create | bool | `true` | Create the default `CredentialIssuer` resource. |
| concierge.credentialIssuer.impersonationProxy | object | `{"externalEndpoint":"","mode":"auto","service":{"annotations":{"service.beta.kubernetes.io/aws-load-balancer-connection-idle-timeout":"4000"},"loadBalancerIP":"","type":"LoadBalancer"}}` | CredentialIssuer impersonation proxy configuration. |
| concierge.credentialIssuer.impersonationProxy.externalEndpoint | string | `""` | External endpoint advertised by the impersonation proxy. |
| concierge.credentialIssuer.impersonationProxy.mode | string | `"auto"` | Impersonation proxy mode (`auto`, `enabled`, or `disabled`). |
| concierge.credentialIssuer.impersonationProxy.service | object | `{"annotations":{"service.beta.kubernetes.io/aws-load-balancer-connection-idle-timeout":"4000"},"loadBalancerIP":"","type":"LoadBalancer"}` | Service settings published in the CredentialIssuer status. |
| concierge.credentialIssuer.impersonationProxy.service.annotations | object | `{"service.beta.kubernetes.io/aws-load-balancer-connection-idle-timeout":"4000"}` | Service annotations published for the impersonation proxy endpoint. |
| concierge.credentialIssuer.impersonationProxy.service.annotations."service.beta.kubernetes.io/aws-load-balancer-connection-idle-timeout" | string | `"4000"` | Default AWS idle timeout annotation used for the impersonation proxy endpoint. |
| concierge.credentialIssuer.impersonationProxy.service.loadBalancerIP | string | `""` | Static load balancer IP reported for the impersonation proxy endpoint. |
| concierge.credentialIssuer.impersonationProxy.service.type | string | `"LoadBalancer"` | Service type reported for the impersonation proxy endpoint. (`ClusterIP` or `LoadBalancer` or `None`). Ref: https://github.com/vmware/pinniped/tree/main/generated/latest#impersonationproxyservicetype-string |
| concierge.customLabels | object | `{}` | Additional labels applied only to Concierge resources. |
| concierge.enabled | bool | `true` | Enable Concierge resources. |
| concierge.image | object | `{"digest":"","pullPolicy":"IfNotPresent","repository":"ghcr.io/vmware/pinniped/pinniped-server","tag":""}` | Concierge container image settings. |
| concierge.image.digest | string | `""` | Concierge image digest. Takes precedence over `tag` when set. |
| concierge.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy for the Concierge container. |
| concierge.image.repository | string | `"ghcr.io/vmware/pinniped/pinniped-server"` | Concierge image repository. |
| concierge.image.tag | string | `""` | Concierge image tag. Defaults to the chart appVersion when empty. |
| concierge.imagePullSecret | object | `{"create":false,"dockerconfigjson":"","name":"image-pull-secret"}` | Optional image pull secret configuration for private registries. |
| concierge.imagePullSecret.create | bool | `false` | Create a dockerconfigjson secret for pulling the Pinniped image. |
| concierge.imagePullSecret.dockerconfigjson | string | `""` | Base64-encoded `.dockerconfigjson` payload used when `create=true`. |
| concierge.imagePullSecret.name | string | `"image-pull-secret"` | Name of the image pull secret. |
| concierge.ingress | object | `{"annotations":{},"enabled":false,"gatewayAPI":{"apiVersion":"gateway.networking.k8s.io/v1beta1","enabled":false,"hostnames":[],"parentRefs":[],"routeKind":"TLSRoute","routeName":"","sectionName":""},"hostname":"","hosts":[],"nginx":{"backendProtocol":"HTTPS","path":"/","pathType":"Prefix","sslPassthrough":"true","tlsSecretName":""},"provider":"traefik","service":{"name":"","port":443},"tls":[],"traefik":{"entryPoints":["websecure"],"match":"","tlsPassthrough":true,"tlsSecretName":""}}` | Concierge exposure settings for Traefik, NGINX passthrough, or Gateway API. |
| concierge.ingress.annotations | object | `{}` | Additional annotations applied to Concierge ingress or gateway resources. |
| concierge.ingress.enabled | bool | `false` | Enable ingress or gateway-based exposure for Concierge. |
| concierge.ingress.gatewayAPI | object | `{"apiVersion":"gateway.networking.k8s.io/v1beta1","enabled":false,"hostnames":[],"parentRefs":[],"routeKind":"TLSRoute","routeName":"","sectionName":""}` | Gateway API route settings for Concierge. |
| concierge.ingress.gatewayAPI.apiVersion | string | `"gateway.networking.k8s.io/v1beta1"` | API version used for the Gateway API route. |
| concierge.ingress.gatewayAPI.enabled | bool | `false` | Enable Gateway API route rendering for Concierge. |
| concierge.ingress.gatewayAPI.hostnames | list | `[]` | Hostnames attached to the Gateway API route. |
| concierge.ingress.gatewayAPI.parentRefs | list | `[]` | Parent references attached to the Gateway API route. |
| concierge.ingress.gatewayAPI.routeKind | string | `"TLSRoute"` | Gateway API route kind (`TLSRoute` or `TCPRoute`). |
| concierge.ingress.gatewayAPI.routeName | string | `""` | Override the generated Gateway API route name. |
| concierge.ingress.gatewayAPI.sectionName | string | `""` | Reserved field for future section name convenience helpers. |
| concierge.ingress.hostname | string | `""` | Primary hostname used by Concierge passthrough exposure. |
| concierge.ingress.hosts | list | `[]` | Legacy L7 ingress hosts list retained for backward compatibility. |
| concierge.ingress.nginx | object | `{"backendProtocol":"HTTPS","path":"/","pathType":"Prefix","sslPassthrough":"true","tlsSecretName":""}` | NGINX SSL passthrough ingress settings. |
| concierge.ingress.nginx.backendProtocol | string | `"HTTPS"` | Value for the `nginx.ingress.kubernetes.io/backend-protocol` annotation. |
| concierge.ingress.nginx.path | string | `"/"` | HTTP path used by the compatibility ingress resource. |
| concierge.ingress.nginx.pathType | string | `"Prefix"` | Path type used by the compatibility ingress resource. |
| concierge.ingress.nginx.sslPassthrough | string | `"true"` | Value for the `nginx.ingress.kubernetes.io/ssl-passthrough` annotation. |
| concierge.ingress.nginx.tlsSecretName | string | `""` | TLS secret name for SSL. Typically the cert-manager-managed secret name. |
| concierge.ingress.provider | string | `"traefik"` | Exposure provider (`traefik`, `nginx`, or `gateway-api`). |
| concierge.ingress.service | object | `{"name":"","port":443}` | Backend service override used by ingress or gateway routes. |
| concierge.ingress.service.name | string | `""` | Explicit service name used as the ingress or gateway backend. |
| concierge.ingress.service.port | int | `443` | Service port used as the ingress or gateway backend. |
| concierge.ingress.tls | list | `[]` | Legacy L7 ingress TLS list retained for backward compatibility. |
| concierge.ingress.traefik | object | `{"entryPoints":["websecure"],"match":"","tlsPassthrough":true,"tlsSecretName":""}` | Traefik `IngressRouteTCP` settings. |
| concierge.ingress.traefik.entryPoints | list | `["websecure"]` | EntryPoints attached to the Traefik TCP route. |
| concierge.ingress.traefik.match | string | `""` | Optional custom Traefik TCP match expression. Defaults to `HostSNI(hostname)`. |
| concierge.ingress.traefik.tlsPassthrough | bool | `true` | Enable TLS passthrough for Traefik TCP routing. |
| concierge.ingress.traefik.tlsSecretName | string | `""` | TLS secret name for SSL. Typically the cert-manager-managed secret name. |
| concierge.jwtAuthenticator | object | `{"audience":"","certificateAuthorityData":"","certificateAuthorityDataSource":{"key":"","kind":"","name":""},"create":false,"issuer":"","name":"supervisor-jwt-authenticator"}` | JWTAuthenticator that validates tokens issued by a Pinniped Supervisor FederationDomain. |
| concierge.jwtAuthenticator.audience | string | `""` | Unique audience identifier for this cluster. |
| concierge.jwtAuthenticator.certificateAuthorityData | string | `""` | Base64-encoded PEM CA bundle for validating the Supervisor TLS certificate. Leave empty when using a publicly trusted CA. |
| concierge.jwtAuthenticator.certificateAuthorityDataSource | object | `{"key":"","kind":"","name":""}` | Dynamic CA bundle source watched by Pinniped for rotation (alternative to `certificateAuthorityData`). |
| concierge.jwtAuthenticator.certificateAuthorityDataSource.key | string | `""` | Key within the resource that contains the PEM CA bundle. |
| concierge.jwtAuthenticator.certificateAuthorityDataSource.kind | string | `""` | Kind of the source resource: `Secret` or `ConfigMap`. |
| concierge.jwtAuthenticator.certificateAuthorityDataSource.name | string | `""` | Name of the Secret or ConfigMap containing the CA bundle. |
| concierge.jwtAuthenticator.create | bool | `false` | Create a JWTAuthenticator resource on this cluster's Concierge. |
| concierge.jwtAuthenticator.issuer | string | `""` | Issuer URL of the Supervisor FederationDomain. Must exactly match `supervisor.federationDomain.issuer`. |
| concierge.jwtAuthenticator.name | string | `"supervisor-jwt-authenticator"` | Name of the JWTAuthenticator resource. |
| concierge.nameOverride | string | `""` | Override the default Concierge resource name prefix. |
| concierge.podSecurityContext | object | `{"runAsGroup":65532,"runAsUser":65532}` | Pod-level security context for Concierge pods. |
| concierge.podSecurityContext.runAsGroup | int | `65532` | GID used to run the Concierge pod. |
| concierge.podSecurityContext.runAsUser | int | `65532` | UID used to run the Concierge pod. |
| concierge.replicaCount | int | `2` | Number of Concierge replicas. |
| concierge.resources | object | `{"limits":{"cpu":"100m","memory":"128Mi"},"requests":{"cpu":"100m","memory":"128Mi"}}` | Resource requests and limits for the Concierge container. |
| concierge.resources.limits | object | `{"cpu":"100m","memory":"128Mi"}` | Resource limits for the Concierge container. |
| concierge.resources.limits.cpu | string | `"100m"` | CPU limit for the Concierge container. |
| concierge.resources.limits.memory | string | `"128Mi"` | Memory limit for the Concierge container. |
| concierge.resources.requests | object | `{"cpu":"100m","memory":"128Mi"}` | Resource requests for the Concierge container. |
| concierge.resources.requests.cpu | string | `"100m"` | Requested CPU for the Concierge container. |
| concierge.resources.requests.memory | string | `"128Mi"` | Requested memory for the Concierge container. |
| concierge.service | object | `{"api":{"port":443,"targetPort":10250},"proxy":{"annotations":{},"enabled":true,"externalTrafficPolicy":"","loadBalancerClass":"","loadBalancerIP":"","loadBalancerSourceRanges":[],"port":443,"targetPort":8444,"type":"ClusterIP"}}` | Service settings for Concierge internal and impersonation proxy traffic. |
| concierge.service.api | object | `{"port":443,"targetPort":10250}` | Service exposing the aggregated Concierge API. |
| concierge.service.api.port | int | `443` | External service port for the Concierge API service. |
| concierge.service.api.targetPort | int | `10250` | Container target port for the Concierge API service. |
| concierge.service.proxy | object | `{"annotations":{},"enabled":true,"externalTrafficPolicy":"","loadBalancerClass":"","loadBalancerIP":"","loadBalancerSourceRanges":[],"port":443,"targetPort":8444,"type":"ClusterIP"}` | Service exposing the Concierge impersonation proxy. |
| concierge.service.proxy.annotations | object | `{}` | Additional annotations for the impersonation proxy service. |
| concierge.service.proxy.enabled | bool | `true` | Create the impersonation proxy service. |
| concierge.service.proxy.externalTrafficPolicy | string | `""` | Optional external traffic policy for the impersonation proxy service. |
| concierge.service.proxy.loadBalancerClass | string | `""` | Optional `loadBalancerClass` for the impersonation proxy service. |
| concierge.service.proxy.loadBalancerIP | string | `""` | Static load balancer IP for the impersonation proxy service. |
| concierge.service.proxy.loadBalancerSourceRanges | list | `[]` | Optional source ranges allowed to reach the impersonation proxy load balancer. |
| concierge.service.proxy.port | int | `443` | External service port for the impersonation proxy. |
| concierge.service.proxy.targetPort | int | `8444` | Container target port for the impersonation proxy. |
| concierge.service.proxy.type | string | `"ClusterIP"` | Kubernetes service type for the impersonation proxy. |
| concierge.tls | object | `{"certManager":{"certificate":{"commonName":"","dnsNames":[],"duration":"","enabled":true,"privateKey":{"algorithm":"RSA","size":2048},"renewBefore":"","secretName":""},"createSelfSignedIssuer":false,"enabled":false,"issuerRef":{"group":"cert-manager.io","kind":"Issuer","name":""}},"secretNames":{"api":"","impersonationProxy":""}}` | TLS secret and optional cert-manager configuration for Concierge. |
| concierge.tls.certManager | object | `{"certificate":{"commonName":"","dnsNames":[],"duration":"","enabled":true,"privateKey":{"algorithm":"RSA","size":2048},"renewBefore":"","secretName":""},"createSelfSignedIssuer":false,"enabled":false,"issuerRef":{"group":"cert-manager.io","kind":"Issuer","name":""}}` | Optional cert-manager integration for Concierge certificates. |
| concierge.tls.certManager.certificate | object | `{"commonName":"","dnsNames":[],"duration":"","enabled":true,"privateKey":{"algorithm":"RSA","size":2048},"renewBefore":"","secretName":""}` | cert-manager certificate options for Concierge. |
| concierge.tls.certManager.certificate.commonName | string | `""` | Optional common name used in the Concierge certificate. |
| concierge.tls.certManager.certificate.dnsNames | list | `[]` | DNS names included in the Concierge certificate. |
| concierge.tls.certManager.certificate.duration | string | `""` | Optional certificate duration passed to cert-manager. |
| concierge.tls.certManager.certificate.enabled | bool | `true` | Create a cert-manager `Certificate` for Concierge. |
| concierge.tls.certManager.certificate.privateKey | object | `{"algorithm":"RSA","size":2048}` | Private key settings used by cert-manager. |
| concierge.tls.certManager.certificate.privateKey.algorithm | string | `"RSA"` | Private key algorithm for the Concierge certificate. |
| concierge.tls.certManager.certificate.privateKey.size | int | `2048` | Private key size for the Concierge certificate. |
| concierge.tls.certManager.certificate.renewBefore | string | `""` | Optional renew-before duration passed to cert-manager. |
| concierge.tls.certManager.certificate.secretName | string | `""` | Override the secret name written by the cert-manager `Certificate`. |
| concierge.tls.certManager.createSelfSignedIssuer | bool | `false` | Create a simple self-signed `Issuer` in the Concierge namespace. |
| concierge.tls.certManager.enabled | bool | `false` | Enable cert-manager resources for Concierge. |
| concierge.tls.certManager.issuerRef | object | `{"group":"cert-manager.io","kind":"Issuer","name":""}` | cert-manager issuer reference used by the Concierge certificate. |
| concierge.tls.certManager.issuerRef.group | string | `"cert-manager.io"` | API group of the cert-manager issuer or clusterissuer resource. |
| concierge.tls.certManager.issuerRef.kind | string | `"Issuer"` | Kind of the cert-manager issuer or clusterissuer resource. |
| concierge.tls.certManager.issuerRef.name | string | `""` | Name of the cert-manager issuer. |
| concierge.tls.secretNames | object | `{"api":"","impersonationProxy":""}` | Explicit secret names used by Concierge. |
| concierge.tls.secretNames.api | string | `""` | Secret name for the Concierge aggregated API serving certificate. |
| concierge.tls.secretNames.impersonationProxy | string | `""` | Secret name for the Concierge impersonation proxy serving certificate. |
| installCRDs | bool | `false` | Install Pinniped CRDs as part of this chart render. |
| namespace | object | `{"create":true,"name":""}` | Global namespace settings for Pinniped components. |
| namespace.create | bool | `true` | Create the component namespaces (`<name>-concierge` and `<name>-supervisor`). |
| namespace.name | string | `""` | Base namespace prefix used to derive component namespaces. Empty defaults to `pinniped`. |
| supervisor | object | `{"config":{"allowedCiphersForTLSOneDotTwo":[],"apiGroupSuffix":"pinniped.dev","audit":{"logInternalPaths":"disabled","logUsernamesAndGroups":"disabled"},"endpoints":{},"httpsProxy":"","logLevel":"","noProxy":"$(KUBERNETES_SERVICE_HOST),169.254.169.254,127.0.0.1,localhost,.svc,.cluster.local"},"containerSecurityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsNonRoot":true,"seccompProfile":{"type":"RuntimeDefault"}},"customLabels":{},"enabled":true,"federationDomain":{"create":false,"identityProviders":[],"issuer":"","tlsSecretName":""},"identityProviders":{"dex":{"additionalScopes":["offline_access","groups","email"],"allowPasswordGrant":false,"certificateAuthorityData":"","clientID":"","clientSecret":"","clientSecretName":"","create":false,"createClientSecret":false,"displayName":"Dex","groupsClaim":"groups","issuer":"","name":"dex","usernameClaim":"email"},"github":{"allowedOrganizations":[],"certificateAuthorityData":"","clientID":"","clientSecret":"","clientSecretName":"","create":false,"createClientSecret":false,"displayName":"GitHub","groupsClaim":"slug","host":"","name":"github","organizationPolicy":"AllGitHubUsers","usernameClaim":"login:id"},"ldap":{"bindPassword":"","bindSecretName":"","bindUsername":"","certificateAuthorityData":"","create":false,"createBindSecret":false,"displayName":"LDAP","groupSearch":{"base":"","filter":"&(objectClass=groupOfNames)(member={})","groupNameAttribute":"cn"},"host":"","name":"openldap","userSearch":{"base":"","filter":"&(objectClass=inetOrgPerson)(uid={})","uidAttribute":"uidNumber","usernameAttribute":"uid"}}},"image":{"digest":"","pullPolicy":"IfNotPresent","repository":"ghcr.io/vmware/pinniped/pinniped-server","tag":""},"imagePullSecret":{"create":false,"dockerconfigjson":"","name":"image-pull-secret"},"ingress":{"annotations":{},"enabled":false,"gatewayAPI":{"apiVersion":"gateway.networking.k8s.io/v1beta1","enabled":false,"hostnames":[],"parentRefs":[],"routeKind":"TLSRoute","routeName":"","sectionName":""},"hostname":"","nginx":{"backendProtocol":"HTTPS","path":"/","pathType":"Prefix","sslPassthrough":"true","tlsSecretName":""},"provider":"traefik","service":{"name":"","port":443},"traefik":{"entryPoints":["websecure"],"match":"","tlsPassthrough":true,"tlsSecretName":""}},"nameOverride":"","podSecurityContext":{"runAsGroup":65532,"runAsUser":65532},"replicaCount":2,"resources":{"limits":{"cpu":"1000m","memory":"128Mi"},"requests":{"cpu":"100m","memory":"128Mi"}},"service":{"api":{"port":443,"targetPort":10250},"public":{"clusterIP":{"enabled":false,"port":443},"loadBalancer":{"annotations":{},"enabled":false,"externalTrafficPolicy":"","loadBalancerClass":"","loadBalancerIP":"","loadBalancerSourceRanges":[],"port":443},"nodePort":{"enabled":false,"nodePort":null,"port":443}}},"tls":{"certManager":{"certificate":{"commonName":"","dnsNames":[],"duration":"","enabled":true,"privateKey":{"algorithm":"RSA","size":2048},"renewBefore":"","secretName":""},"createSelfSignedIssuer":false,"enabled":false,"issuerRef":{"group":"cert-manager.io","kind":"Issuer","name":""}},"secretName":""}}` | Pinniped Supervisor component configuration. |
| supervisor.config | object | `{"allowedCiphersForTLSOneDotTwo":[],"apiGroupSuffix":"pinniped.dev","audit":{"logInternalPaths":"disabled","logUsernamesAndGroups":"disabled"},"endpoints":{},"httpsProxy":"","logLevel":"","noProxy":"$(KUBERNETES_SERVICE_HOST),169.254.169.254,127.0.0.1,localhost,.svc,.cluster.local"}` | Supervisor static configuration rendered into the Pinniped config file. |
| supervisor.config.allowedCiphersForTLSOneDotTwo | list | `[]` | Allowed TLS 1.2 cipher suites for Supervisor. Empty uses Pinniped defaults. |
| supervisor.config.apiGroupSuffix | string | `"pinniped.dev"` | API group suffix for Supervisor APIs. |
| supervisor.config.audit | object | `{"logInternalPaths":"disabled","logUsernamesAndGroups":"disabled"}` | Supervisor audit logging configuration. |
| supervisor.config.audit.logInternalPaths | string | `"disabled"` | Include internal endpoints such as `/healthz` in Supervisor audit logs. |
| supervisor.config.audit.logUsernamesAndGroups | string | `"disabled"` | Include usernames and groups in Supervisor audit logs. |
| supervisor.config.endpoints | object | `{}` | Raw Supervisor endpoint configuration merged into `pinniped.yaml`. |
| supervisor.config.httpsProxy | string | `""` | HTTPS proxy used by Supervisor for outbound requests. |
| supervisor.config.logLevel | string | `""` | Supervisor log level. Leave empty for Pinniped defaults. |
| supervisor.config.noProxy | string | `"$(KUBERNETES_SERVICE_HOST),169.254.169.254,127.0.0.1,localhost,.svc,.cluster.local"` | NO_PROXY list used by Supervisor for outbound requests. |
| supervisor.containerSecurityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsNonRoot":true,"seccompProfile":{"type":"RuntimeDefault"}}` | Container-level security context for the Supervisor container. |
| supervisor.containerSecurityContext.allowPrivilegeEscalation | bool | `false` | Disable privilege escalation in the Supervisor container. |
| supervisor.containerSecurityContext.capabilities | object | `{"drop":["ALL"]}` | Linux capabilities configuration for the Supervisor container. |
| supervisor.containerSecurityContext.capabilities.drop | list | `["ALL"]` | Capabilities dropped from the Supervisor container. |
| supervisor.containerSecurityContext.readOnlyRootFilesystem | bool | `true` | Mount the root filesystem as read-only. |
| supervisor.containerSecurityContext.runAsNonRoot | bool | `true` | Require the Supervisor container to run as a non-root user. |
| supervisor.containerSecurityContext.seccompProfile | object | `{"type":"RuntimeDefault"}` | Seccomp profile applied to the Supervisor container. |
| supervisor.containerSecurityContext.seccompProfile.type | string | `"RuntimeDefault"` | Seccomp profile type. |
| supervisor.customLabels | object | `{}` | Additional labels applied only to Supervisor resources. |
| supervisor.enabled | bool | `true` | Enable Supervisor resources. |
| supervisor.federationDomain | object | `{"create":false,"identityProviders":[],"issuer":"","tlsSecretName":""}` | FederationDomain configures the Supervisor as an OIDC issuer for downstream clusters. |
| supervisor.federationDomain.create | bool | `false` | Create a FederationDomain resource. |
| supervisor.federationDomain.identityProviders | list | `[]` | Each entry must have `displayName` and `objectRef.{apiGroup,kind,name}` fields. |
| supervisor.federationDomain.issuer | string | `""` | OIDC issuer URL. Must be a publicly reachable HTTPS URL and must exactly match `concierge.jwtAuthenticator.issuer`. |
| supervisor.federationDomain.tlsSecretName | string | `""` | Defaults to the cert-manager-managed secret when `supervisor.tls.certManager.enabled=true`. |
| supervisor.identityProviders | object | `{"dex":{"additionalScopes":["offline_access","groups","email"],"allowPasswordGrant":false,"certificateAuthorityData":"","clientID":"","clientSecret":"","clientSecretName":"","create":false,"createClientSecret":false,"displayName":"Dex","groupsClaim":"groups","issuer":"","name":"dex","usernameClaim":"email"},"github":{"allowedOrganizations":[],"certificateAuthorityData":"","clientID":"","clientSecret":"","clientSecretName":"","create":false,"createClientSecret":false,"displayName":"GitHub","groupsClaim":"slug","host":"","name":"github","organizationPolicy":"AllGitHubUsers","usernameClaim":"login:id"},"ldap":{"bindPassword":"","bindSecretName":"","bindUsername":"","certificateAuthorityData":"","create":false,"createBindSecret":false,"displayName":"LDAP","groupSearch":{"base":"","filter":"&(objectClass=groupOfNames)(member={})","groupNameAttribute":"cn"},"host":"","name":"openldap","userSearch":{"base":"","filter":"&(objectClass=inetOrgPerson)(uid={})","uidAttribute":"uidNumber","usernameAttribute":"uid"}}}` | Identity provider resources created in the Supervisor namespace. |
| supervisor.identityProviders.dex | object | `{"additionalScopes":["offline_access","groups","email"],"allowPasswordGrant":false,"certificateAuthorityData":"","clientID":"","clientSecret":"","clientSecretName":"","create":false,"createClientSecret":false,"displayName":"Dex","groupsClaim":"groups","issuer":"","name":"dex","usernameClaim":"email"}` | Dex OIDC identity provider configuration. |
| supervisor.identityProviders.dex.additionalScopes | list | `["offline_access","groups","email"]` | Additional OIDC scopes to request from Dex beyond `openid`. |
| supervisor.identityProviders.dex.allowPasswordGrant | bool | `false` | Allow the OIDC password grant flow. Requires Dex >= v2.31.0. |
| supervisor.identityProviders.dex.certificateAuthorityData | string | `""` | Base64-encoded PEM CA bundle for validating the Dex TLS certificate. Omit when Dex uses a publicly trusted CA. |
| supervisor.identityProviders.dex.clientID | string | `""` | Dex OAuth client ID. Required when `createClientSecret=true`. |
| supervisor.identityProviders.dex.clientSecret | string | `""` | Dex OAuth client secret. Required when `createClientSecret=true`. |
| supervisor.identityProviders.dex.clientSecretName | string | `""` | Name of the Secret containing the Dex client credentials. |
| supervisor.identityProviders.dex.create | bool | `false` | Create an OIDCIdentityProvider for Dex. |
| supervisor.identityProviders.dex.createClientSecret | bool | `false` | Create the Dex client credentials Secret from the values below. |
| supervisor.identityProviders.dex.displayName | string | `"Dex"` | Display name shown to users at the login-chooser screen. |
| supervisor.identityProviders.dex.groupsClaim | string | `"groups"` | OIDC claim mapped to Kubernetes group membership. |
| supervisor.identityProviders.dex.issuer | string | `""` | Dex OIDC issuer URL (e.g. `https://dex.example.com`). |
| supervisor.identityProviders.dex.name | string | `"dex"` | Name of the OIDCIdentityProvider resource. |
| supervisor.identityProviders.dex.usernameClaim | string | `"email"` | OIDC claim mapped to the Kubernetes username. |
| supervisor.identityProviders.github | object | `{"allowedOrganizations":[],"certificateAuthorityData":"","clientID":"","clientSecret":"","clientSecretName":"","create":false,"createClientSecret":false,"displayName":"GitHub","groupsClaim":"slug","host":"","name":"github","organizationPolicy":"AllGitHubUsers","usernameClaim":"login:id"}` | GitHub identity provider configuration. |
| supervisor.identityProviders.github.allowedOrganizations | list | `[]` | List of GitHub organizations to allow when `organizationPolicy=OnlyUsersFromAllowedOrganizations`. |
| supervisor.identityProviders.github.certificateAuthorityData | string | `""` | Base64-encoded PEM CA bundle for GitHub Enterprise TLS. Omit for `github.com`. |
| supervisor.identityProviders.github.clientID | string | `""` | GitHub OAuth App or GitHub App client ID. Required when `createClientSecret=true`. |
| supervisor.identityProviders.github.clientSecret | string | `""` | GitHub OAuth App or GitHub App client secret. Required when `createClientSecret=true`. |
| supervisor.identityProviders.github.clientSecretName | string | `""` | Name of the Secret containing the GitHub OAuth App client credentials. |
| supervisor.identityProviders.github.create | bool | `false` | Create a GitHubIdentityProvider resource. |
| supervisor.identityProviders.github.createClientSecret | bool | `false` | Create the GitHub client credentials Secret from the values below. |
| supervisor.identityProviders.github.displayName | string | `"GitHub"` | Display name shown to users at the login-chooser screen. |
| supervisor.identityProviders.github.groupsClaim | string | `"slug"` | How to map GitHub teams to Kubernetes groups: `name` or `slug`. |
| supervisor.identityProviders.github.host | string | `""` | GitHub API host. Leave empty for `github.com`; set for GitHub Enterprise Server. |
| supervisor.identityProviders.github.name | string | `"github"` | Name of the GitHubIdentityProvider resource. |
| supervisor.identityProviders.github.organizationPolicy | string | `"AllGitHubUsers"` | GitHub organization membership policy: `AllGitHubUsers` or `OnlyUsersFromAllowedOrganizations`. |
| supervisor.identityProviders.github.usernameClaim | string | `"login:id"` | How to map the GitHub identity to a Kubernetes username: `id`, `login`, or `login:id`. |
| supervisor.identityProviders.ldap | object | `{"bindPassword":"","bindSecretName":"","bindUsername":"","certificateAuthorityData":"","create":false,"createBindSecret":false,"displayName":"LDAP","groupSearch":{"base":"","filter":"&(objectClass=groupOfNames)(member={})","groupNameAttribute":"cn"},"host":"","name":"openldap","userSearch":{"base":"","filter":"&(objectClass=inetOrgPerson)(uid={})","uidAttribute":"uidNumber","usernameAttribute":"uid"}}` | LDAP identity provider configuration. |
| supervisor.identityProviders.ldap.bindPassword | string | `""` | LDAP bind account password. Required when `createBindSecret=true`. |
| supervisor.identityProviders.ldap.bindSecretName | string | `""` | Name of the Secret containing the LDAP bind account credentials. |
| supervisor.identityProviders.ldap.bindUsername | string | `""` | LDAP bind account distinguished name. Required when `createBindSecret=true`. |
| supervisor.identityProviders.ldap.certificateAuthorityData | string | `""` | Base64-encoded PEM CA bundle for the LDAP server TLS certificate. |
| supervisor.identityProviders.ldap.create | bool | `false` | Create an LDAPIdentityProvider resource. |
| supervisor.identityProviders.ldap.createBindSecret | bool | `false` | Create the LDAP bind account Secret from the values below. |
| supervisor.identityProviders.ldap.displayName | string | `"LDAP"` | Display name shown to users at the login-chooser screen. |
| supervisor.identityProviders.ldap.groupSearch | object | `{"base":"","filter":"&(objectClass=groupOfNames)(member={})","groupNameAttribute":"cn"}` | LDAP group search settings. |
| supervisor.identityProviders.ldap.groupSearch.base | string | `""` | Base DN for group searches. |
| supervisor.identityProviders.ldap.groupSearch.filter | string | `"&(objectClass=groupOfNames)(member={})"` | LDAP filter expression for group membership lookups. |
| supervisor.identityProviders.ldap.groupSearch.groupNameAttribute | string | `"cn"` | LDAP attribute used as the Kubernetes group name. |
| supervisor.identityProviders.ldap.host | string | `""` | LDAP server host and optional port (e.g. `ldap.example.com:636`). |
| supervisor.identityProviders.ldap.name | string | `"openldap"` | Name of the LDAPIdentityProvider resource. |
| supervisor.identityProviders.ldap.userSearch | object | `{"base":"","filter":"&(objectClass=inetOrgPerson)(uid={})","uidAttribute":"uidNumber","usernameAttribute":"uid"}` | LDAP user search settings. |
| supervisor.identityProviders.ldap.userSearch.base | string | `""` | Base DN for user searches. |
| supervisor.identityProviders.ldap.userSearch.filter | string | `"&(objectClass=inetOrgPerson)(uid={})"` | LDAP filter expression for user lookups. Use `{}` as a placeholder for the supplied username. |
| supervisor.identityProviders.ldap.userSearch.uidAttribute | string | `"uidNumber"` | LDAP attribute used as the stable unique user identifier. |
| supervisor.identityProviders.ldap.userSearch.usernameAttribute | string | `"uid"` | LDAP attribute used as the Kubernetes username. |
| supervisor.image | object | `{"digest":"","pullPolicy":"IfNotPresent","repository":"ghcr.io/vmware/pinniped/pinniped-server","tag":""}` | Supervisor container image settings. |
| supervisor.image.digest | string | `""` | Supervisor image digest. Takes precedence over `tag` when set. |
| supervisor.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy for the Supervisor container. |
| supervisor.image.repository | string | `"ghcr.io/vmware/pinniped/pinniped-server"` | Supervisor image repository. |
| supervisor.image.tag | string | `""` | Supervisor image tag. Defaults to the chart appVersion when empty. |
| supervisor.imagePullSecret | object | `{"create":false,"dockerconfigjson":"","name":"image-pull-secret"}` | Optional image pull secret configuration for private registries. |
| supervisor.imagePullSecret.create | bool | `false` | Create a dockerconfigjson secret for pulling the Pinniped image. |
| supervisor.imagePullSecret.dockerconfigjson | string | `""` | Base64-encoded `.dockerconfigjson` payload used when `create=true`. |
| supervisor.imagePullSecret.name | string | `"image-pull-secret"` | Name of the image pull secret. |
| supervisor.ingress | object | `{"annotations":{},"enabled":false,"gatewayAPI":{"apiVersion":"gateway.networking.k8s.io/v1beta1","enabled":false,"hostnames":[],"parentRefs":[],"routeKind":"TLSRoute","routeName":"","sectionName":""},"hostname":"","nginx":{"backendProtocol":"HTTPS","path":"/","pathType":"Prefix","sslPassthrough":"true","tlsSecretName":""},"provider":"traefik","service":{"name":"","port":443},"traefik":{"entryPoints":["websecure"],"match":"","tlsPassthrough":true,"tlsSecretName":""}}` | Supervisor exposure settings for Traefik, NGINX passthrough, or Gateway API. |
| supervisor.ingress.annotations | object | `{}` | Additional annotations applied to Supervisor ingress or gateway resources. |
| supervisor.ingress.enabled | bool | `false` | Enable ingress or gateway-based exposure for Supervisor. |
| supervisor.ingress.gatewayAPI | object | `{"apiVersion":"gateway.networking.k8s.io/v1beta1","enabled":false,"hostnames":[],"parentRefs":[],"routeKind":"TLSRoute","routeName":"","sectionName":""}` | Gateway API route settings for Supervisor. |
| supervisor.ingress.gatewayAPI.apiVersion | string | `"gateway.networking.k8s.io/v1beta1"` | API version used for the Gateway API route. |
| supervisor.ingress.gatewayAPI.enabled | bool | `false` | Enable Gateway API route rendering for Supervisor. |
| supervisor.ingress.gatewayAPI.hostnames | list | `[]` | Hostnames attached to the Gateway API route. |
| supervisor.ingress.gatewayAPI.parentRefs | list | `[]` | Parent references attached to the Gateway API route. |
| supervisor.ingress.gatewayAPI.routeKind | string | `"TLSRoute"` | Gateway API route kind (`TLSRoute` or `TCPRoute`). |
| supervisor.ingress.gatewayAPI.routeName | string | `""` | Override the generated Gateway API route name. |
| supervisor.ingress.gatewayAPI.sectionName | string | `""` | Reserved field for future section name convenience helpers. |
| supervisor.ingress.hostname | string | `""` | Primary hostname used by Supervisor passthrough exposure. |
| supervisor.ingress.nginx | object | `{"backendProtocol":"HTTPS","path":"/","pathType":"Prefix","sslPassthrough":"true","tlsSecretName":""}` | NGINX SSL passthrough ingress settings. |
| supervisor.ingress.nginx.backendProtocol | string | `"HTTPS"` | Value for the `nginx.ingress.kubernetes.io/backend-protocol` annotation. |
| supervisor.ingress.nginx.path | string | `"/"` | HTTP path used by the compatibility ingress resource. |
| supervisor.ingress.nginx.pathType | string | `"Prefix"` | Path type used by the compatibility ingress resource. |
| supervisor.ingress.nginx.sslPassthrough | string | `"true"` | Value for the `nginx.ingress.kubernetes.io/ssl-passthrough` annotation. |
| supervisor.ingress.nginx.tlsSecretName | string | `""` | TLS secret name for SSL. Typically the cert-manager-managed secret name. |
| supervisor.ingress.provider | string | `"traefik"` | Exposure provider (`traefik`, `nginx`, or `gateway-api`). |
| supervisor.ingress.service | object | `{"name":"","port":443}` | Backend service override used by ingress or gateway routes. |
| supervisor.ingress.service.name | string | `""` | Explicit service name used as the ingress or gateway backend. |
| supervisor.ingress.service.port | int | `443` | Service port used as the ingress or gateway backend. |
| supervisor.ingress.traefik | object | `{"entryPoints":["websecure"],"match":"","tlsPassthrough":true,"tlsSecretName":""}` | Traefik `IngressRouteTCP` settings. |
| supervisor.ingress.traefik.entryPoints | list | `["websecure"]` | EntryPoints attached to the Traefik TCP route. |
| supervisor.ingress.traefik.match | string | `""` | Optional custom Traefik TCP match expression. Defaults to `HostSNI(hostname)`. |
| supervisor.ingress.traefik.tlsPassthrough | bool | `true` | Enable TLS passthrough for Traefik TCP routing. |
| supervisor.ingress.traefik.tlsSecretName | string | `""` | TLS secret name for SSL. Typically the cert-manager-managed secret name. |
| supervisor.nameOverride | string | `""` | Override the default Supervisor resource name prefix. |
| supervisor.podSecurityContext | object | `{"runAsGroup":65532,"runAsUser":65532}` | Pod-level security context for Supervisor pods. |
| supervisor.podSecurityContext.runAsGroup | int | `65532` | GID used to run the Supervisor pod. |
| supervisor.podSecurityContext.runAsUser | int | `65532` | UID used to run the Supervisor pod. |
| supervisor.replicaCount | int | `2` | Number of Supervisor replicas. |
| supervisor.resources | object | `{"limits":{"cpu":"1000m","memory":"128Mi"},"requests":{"cpu":"100m","memory":"128Mi"}}` | Resource requests and limits for the Supervisor container. |
| supervisor.resources.limits | object | `{"cpu":"1000m","memory":"128Mi"}` | Resource limits for the Supervisor container. |
| supervisor.resources.limits.cpu | string | `"1000m"` | CPU limit for the Supervisor container. |
| supervisor.resources.limits.memory | string | `"128Mi"` | Memory limit for the Supervisor container. |
| supervisor.resources.requests | object | `{"cpu":"100m","memory":"128Mi"}` | Resource requests for the Supervisor container. |
| supervisor.resources.requests.cpu | string | `"100m"` | Requested CPU for the Supervisor container. |
| supervisor.resources.requests.memory | string | `"128Mi"` | Requested memory for the Supervisor container. |
| supervisor.service | object | `{"api":{"port":443,"targetPort":10250},"public":{"clusterIP":{"enabled":false,"port":443},"loadBalancer":{"annotations":{},"enabled":false,"externalTrafficPolicy":"","loadBalancerClass":"","loadBalancerIP":"","loadBalancerSourceRanges":[],"port":443},"nodePort":{"enabled":false,"nodePort":null,"port":443}}}` | Service settings for Supervisor API and public access. |
| supervisor.service.api | object | `{"port":443,"targetPort":10250}` | Service exposing the aggregated Supervisor API. |
| supervisor.service.api.port | int | `443` | External service port for the Supervisor API service. |
| supervisor.service.api.targetPort | int | `10250` | Container target port for the Supervisor API service. |
| supervisor.service.public | object | `{"clusterIP":{"enabled":false,"port":443},"loadBalancer":{"annotations":{},"enabled":false,"externalTrafficPolicy":"","loadBalancerClass":"","loadBalancerIP":"","loadBalancerSourceRanges":[],"port":443},"nodePort":{"enabled":false,"nodePort":null,"port":443}}` | Public exposure service settings for the Supervisor HTTPS endpoint. |
| supervisor.service.public.clusterIP | object | `{"enabled":false,"port":443}` | ClusterIP-based public exposure settings. |
| supervisor.service.public.clusterIP.enabled | bool | `false` | Create a dedicated ClusterIP service for Supervisor HTTPS traffic. |
| supervisor.service.public.clusterIP.port | int | `443` | External port exposed by the ClusterIP service. |
| supervisor.service.public.loadBalancer | object | `{"annotations":{},"enabled":false,"externalTrafficPolicy":"","loadBalancerClass":"","loadBalancerIP":"","loadBalancerSourceRanges":[],"port":443}` | LoadBalancer-based public exposure settings. |
| supervisor.service.public.loadBalancer.annotations | object | `{}` | Additional annotations for the Supervisor LoadBalancer service. |
| supervisor.service.public.loadBalancer.enabled | bool | `false` | Create a LoadBalancer service for Supervisor HTTPS traffic. |
| supervisor.service.public.loadBalancer.externalTrafficPolicy | string | `""` | Optional external traffic policy for the Supervisor LoadBalancer service. |
| supervisor.service.public.loadBalancer.loadBalancerClass | string | `""` | Optional `loadBalancerClass` for the Supervisor LoadBalancer service. |
| supervisor.service.public.loadBalancer.loadBalancerIP | string | `""` | Static load balancer IP for the Supervisor LoadBalancer service. |
| supervisor.service.public.loadBalancer.loadBalancerSourceRanges | list | `[]` | Optional source ranges allowed to reach the Supervisor LoadBalancer service. |
| supervisor.service.public.loadBalancer.port | int | `443` | External port exposed by the LoadBalancer service. |
| supervisor.service.public.nodePort | object | `{"enabled":false,"nodePort":null,"port":443}` | NodePort-based public exposure settings. |
| supervisor.service.public.nodePort.enabled | bool | `false` | Create a NodePort service for Supervisor HTTPS traffic. |
| supervisor.service.public.nodePort.nodePort | string | `nil` | Fixed nodePort value. Leave null to let Kubernetes allocate one. |
| supervisor.service.public.nodePort.port | int | `443` | External port exposed by the NodePort service. |
| supervisor.tls | object | `{"certManager":{"certificate":{"commonName":"","dnsNames":[],"duration":"","enabled":true,"privateKey":{"algorithm":"RSA","size":2048},"renewBefore":"","secretName":""},"createSelfSignedIssuer":false,"enabled":false,"issuerRef":{"group":"cert-manager.io","kind":"Issuer","name":""}},"secretName":""}` | TLS secret and optional cert-manager configuration for Supervisor. |
| supervisor.tls.certManager | object | `{"certificate":{"commonName":"","dnsNames":[],"duration":"","enabled":true,"privateKey":{"algorithm":"RSA","size":2048},"renewBefore":"","secretName":""},"createSelfSignedIssuer":false,"enabled":false,"issuerRef":{"group":"cert-manager.io","kind":"Issuer","name":""}}` | Optional cert-manager integration for Supervisor certificates. |
| supervisor.tls.certManager.certificate | object | `{"commonName":"","dnsNames":[],"duration":"","enabled":true,"privateKey":{"algorithm":"RSA","size":2048},"renewBefore":"","secretName":""}` | cert-manager certificate options for Supervisor. |
| supervisor.tls.certManager.certificate.commonName | string | `""` | Optional common name used in the Supervisor certificate. |
| supervisor.tls.certManager.certificate.dnsNames | list | `[]` | DNS names included in the Supervisor certificate. |
| supervisor.tls.certManager.certificate.duration | string | `""` | Optional certificate duration passed to cert-manager. |
| supervisor.tls.certManager.certificate.enabled | bool | `true` | Create a cert-manager `Certificate` for Supervisor. |
| supervisor.tls.certManager.certificate.privateKey | object | `{"algorithm":"RSA","size":2048}` | Private key settings used by cert-manager. |
| supervisor.tls.certManager.certificate.privateKey.algorithm | string | `"RSA"` | Private key algorithm for the Supervisor certificate. |
| supervisor.tls.certManager.certificate.privateKey.size | int | `2048` | Private key size for the Supervisor certificate. |
| supervisor.tls.certManager.certificate.renewBefore | string | `""` | Optional renew-before duration passed to cert-manager. |
| supervisor.tls.certManager.certificate.secretName | string | `""` | Override the secret name written by the cert-manager `Certificate`. |
| supervisor.tls.certManager.createSelfSignedIssuer | bool | `false` | Create a simple self-signed `Issuer` in the Supervisor namespace. |
| supervisor.tls.certManager.enabled | bool | `false` | Enable cert-manager resources for Supervisor. |
| supervisor.tls.certManager.issuerRef | object | `{"group":"cert-manager.io","kind":"Issuer","name":""}` | cert-manager issuer reference used by the Supervisor certificate. |
| supervisor.tls.certManager.issuerRef.group | string | `"cert-manager.io"` | API group of the cert-manager issuer or clusterissuer resource. |
| supervisor.tls.certManager.issuerRef.kind | string | `"Issuer"` | Kind of the cert-manager issuer or clusterissuer resource. |
| supervisor.tls.certManager.issuerRef.name | string | `""` | Name of the cert-manager issuer. |
| supervisor.tls.secretName | string | `""` | Secret name used by the Supervisor default TLS certificate. |

