# argocd

![Version: 1.0.0](https://img.shields.io/badge/Version-1.0.0-informational?style=flat-square)

## Requirements

| Repository | Name | Version |
|------------|------|---------|
| https://argoproj.github.io/argo-helm | argocd(argo-cd) | 9.1.3 |
| https://argoproj.github.io/argo-helm | apps(argocd-apps) | 2.0.2 |
| https://argoproj.github.io/argo-helm | image-updater(argocd-image-updater) | 1.0.1 |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| apps.enabled | bool | `false` |  |
| argocd.configs.params."server.insecure" | bool | `true` |  |
| argocd.configs.params.annotations | object | `{}` |  |
| argocd.configs.params.create | bool | `true` |  |
| argocd.dex.enabled | bool | `false` |  |
| argocd.enabled | bool | `true` |  |
| argocd.server.ingress.annotations | object | `{}` |  |
| argocd.server.ingress.enabled | bool | `true` |  |
| argocd.server.ingress.hostname | string | `"argocd.local"` |  |
| argocd.server.ingress.ingressClassName | string | `"traefik"` |  |
| image-updater.enabled | bool | `false` |  |

