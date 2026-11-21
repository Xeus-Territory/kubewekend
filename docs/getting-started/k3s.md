---
title: K3s
description: "Create a K3s cluster with Ansible and setup.sh: standalone or high availability with etcd or PostgreSQL, Flannel, Calico or Cilium, MetalLB and Traefik."
parent: Getting started
nav_order: 3
---

# Create a K3s cluster (standalone or HA)
{: .no_toc }

A lightweight, single-binary Kubernetes. Good for small teams and edge labs, with high availability on embedded etcd or PostgreSQL.
{: .fs-5 .fw-300 }

1. TOC
{:toc}

## Review the options

K3s reads `k3sCluster` in [`master.yaml`]({{ site.repo_url }}/blob/main/ansible/inventories/host_vars/master.yaml); workers read [`worker.yaml`]({{ site.repo_url }}/blob/main/ansible/inventories/host_vars/worker.yaml) (`version`, `tlsSANs`, `nodeLabels`, `nodeTaints`).

```bash
./scripts/setup.sh config --list k3s
```

| Option | Values |
|--------|--------|
| `version` | K3s release, for example `v1.36.5+k3s1` |
| `cni` | Flannel (default), Calico, Cilium |
| `loadBalancer` | ServiceLB, MetalLB (IP pool) |
| `ingress` | Traefik installed with Helm (the bundled K3s Traefik is disabled): ports, dashboard, Gateway API |
| `highAvailability.dataStorage` | `etcd` or `postgres` (external database) |
| `tlsSANs`, `nodeLabels`, `nodeTaints` | API certificate names, node labels and taints |

## Create the cluster

### Standalone (one master, optional workers)

```bash
# master first
./scripts/setup.sh k3s setup --host k8s-master-machine
# then each worker
./scripts/setup.sh k3s setup --host k8s-worker-machine-1
```

### High availability

Fill the HA section of the inventory (`ha_master_init`, `ha_master_join`, `ha_worker`), review `k3sCluster.highAvailability` in `master.yaml`, then bootstrap every node at once:

```bash
./scripts/setup.sh config edit
./scripts/setup.sh k3s ha-setup
```

## Get the kubeconfig and verify

```bash
ssh vagrant@192.168.56.99 'sudo cat /etc/rancher/k3s/k3s.yaml' > ~/.kube/config
# use the master IP (your VPS IP on a VPS)
sed -i "s/127.0.0.1/192.168.56.99/g" ~/.kube/config

kubectl get nodes -o wide
kubectl get pods -A
```

## Add utilities

```bash
./scripts/setup.sh k3s utils --list
./scripts/setup.sh k3s utils certmanager gitops ingress_test
```

See [Utilities]({% link docs/utilities/index.md %}).

## Tear down

```bash
# uninstalls K3s from every inventory node
./scripts/setup.sh k3s destroy
./scripts/setup.sh vagrant destroy # when you used VMs
```

## Learn more

- [Session 5: Build an HA cluster](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-5)
- [Extra 2: Rebuild the cluster with RKE2 or K3s](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-Extra-2)
