# cert-manager

![Version: 1.0.0](https://img.shields.io/badge/Version-1.0.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)

Cert Manager Infrastructure Chart

## Requirements

| Repository | Name | Version |
|------------|------|---------|
| https://charts.jetstack.io | cert-manager | v1.19.2 |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| cert-manager.installCRDs | bool | `true` |  |
| cert-manager.prometheus.enabled | bool | `false` |  |
| clusterIssuers | list | `[]` | List of ClusterIssuers to create |

