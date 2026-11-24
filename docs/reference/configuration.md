---
title: Configuration
description: "Kubewekend configuration reference: master.yaml, worker.yaml, the Ansible inventory and .env, and how to inspect them with setup.sh."
parent: Reference
nav_order: 2
---

# Configuration reference
{: .no_toc }

Everything Kubewekend builds is driven by a few files. The comments in `master.yaml` document each option, with links to upstream docs.
{: .fs-5 .fw-300 }

1. TOC
{:toc}

## Files

| File | Purpose |
|------|---------|
| [`ansible/inventories/host_vars/master.yaml`]({{ site.repo_url }}/blob/main/ansible/inventories/host_vars/master.yaml) | **Main configuration**: `kindCluster`, `k3sCluster`, `rke2Cluster` and every `utilities` block |
| [`ansible/inventories/host_vars/worker.yaml`]({{ site.repo_url }}/blob/main/ansible/inventories/host_vars/worker.yaml) | K3s / RKE2 worker settings: `version`, `tlsSANs`, `nodeLabels`, `nodeTaints` |
| [`ansible/inventories/hosts`]({{ site.repo_url }}/blob/main/ansible/inventories/hosts) | Ansible inventory: standalone and HA groups ([details]({% link docs/getting-started/prepare-hosts.md %}#the-inventory-file)) |
| `.env` | SSH user and key, created from [`template.env`]({{ site.repo_url }}/blob/main/template.env) by `env init` |
| [`Vagrantfile`]({{ site.repo_url }}/blob/main/Vagrantfile) | VM definitions (VirtualBox) |

## Inspect and edit

```bash
# table summary of master.yaml (coloured ON / OFF)
./scripts/setup.sh config show
# the full YAML
./scripts/setup.sh config show --raw
# supported / in-development options per distribution, with current values
./scripts/setup.sh config --list
# the same for utilities
./scripts/setup.sh config --list utils
# open in $EDITOR (default: vim)
./scripts/setup.sh config edit
```

## Key settings

```yaml
# Kind
kindCluster.image: "kindest/node:v1.36.4"
kindCluster.ingress.class: "traefik"                   # Traefik only
kindCluster.loadbalancer.type: "cloud-provider-kind"   # or metallb, cilium-ipam-lb

# K3s
k3sCluster.version: "v1.36.5+k3s1"
k3sCluster.cni.type: "flannel"                         # or calico, cilium
k3sCluster.loadBalancer.type: "servicelb"              # or metallb
k3sCluster.highAvailability.dataStorage.type: "etcd"   # or postgres

# RKE2
rke2Cluster.version: "v1.36.5+rke2r1"
rke2Cluster.cni.type: "canal"                          # or calico, cilium, flannel
rke2Cluster.loadBalancer.type: "servicelb"             # or metallb
rke2Cluster.highAvailability.dataStorage.type: "etcd"  # or postgres

# Utilities: one block per tag, `enable` turns it on
utilities.storage.type: "longhorn"                     # or local-path
utilities.secretManagement.config.mode: "dev"          # or standalone
utilities.gitops.type: "argocd"                        # or flux
utilities.security.policy.type: "kyverno"              # or opa-gatekeeper
```

> [!TIP]
>
> Override a value for one run without editing the file: `./scripts/setup.sh kind setup --extra-vars "key=value"`.
