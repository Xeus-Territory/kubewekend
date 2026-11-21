---
title: Secret management
description: "Run HashiCorp Vault or OpenBao on Kubernetes in dev or standalone mode, with automatic init and unseal and the optional agent injector."
parent: Utilities
nav_order: 2
---

# Secret management: Vault and OpenBao
{: .no_toc }

Run HashiCorp Vault or OpenBao in the cluster, in a quick dev mode or a persistent standalone mode.
{: .fs-5 .fw-300 }

1. TOC
{:toc}

## Configure

```yaml
utilities:
  secretManagement:
    enable: true
    type: "vault"                 # vault | openbao
    host: "vault.kubewekend.local"
    ingressClass: "traefik"
    config:
      mode: "dev"                 # dev | standalone
      injector: false             # Vault agent injector
```

| Mode | Storage | Init / unseal | Use it for |
|------|---------|---------------|------------|
| `dev` | In memory: data is lost when the Pod restarts | None: unsealed, root token `root` | Quick experiments |
| `standalone` | PVC: **needs a StorageClass** ([Storage]({% link docs/utilities/storage.md %})) | Automatic: one key share, saved for you | Labs that keep data |

| `type` | Namespace | Notes |
|--------|-----------|-------|
| `vault` | `vault` | HashiCorp Vault chart |
| `openbao` | `openbao` | OpenBao chart (UI enabled); recent charts need Kubernetes 1.30 or newer |

## Install

```bash
./scripts/setup.sh k3s utils secret_management
```

In `standalone` mode the playbook waits for the server Pod, initialises it, unseals it, and saves the init output (unseal key and root token) to `vault-init-output.json` on the master and in the project root on your machine.

> [!CAUTION]
>
> `vault-init-output.json` holds the unseal key and root token. It is git-ignored: keep it out of commits and delete it when you destroy the lab.

## Verify

```bash
# or -n openbao
kubectl -n vault get pods
# OpenBao: kubectl -n openbao exec openbao-0 -- bao status
kubectl -n vault exec vault-0 -- vault status
```

The UI is served by the ingress at `utilities.secretManagement.host`.

> [!TIP]
>
> Switching from `dev` to `standalone` is safe: the standalone install resets `server.dev.enabled`, which Helm would otherwise keep with `--reuse-values`.
