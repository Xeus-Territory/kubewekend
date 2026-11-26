---
title: RKE2
description: "Create an RKE2 cluster with Ansible and setup.sh: standalone or high availability, Canal, Calico or Cilium CNI, ServiceLB or MetalLB and Traefik ingress."
parent: Getting started
nav_order: 4
---

# Create an RKE2 cluster (standalone or HA)
{: .no_toc }

Rancher's security-focused distribution. Good for bigger teams and production-like labs, with high availability on etcd or PostgreSQL.
{: .fs-5 .fw-300 }

1. TOC
{:toc}

## Review the options

RKE2 reads `rke2Cluster` in [`master.yaml`]({{ site.repo_url }}/blob/main/ansible/inventories/host_vars/master.yaml); workers read [`worker.yaml`]({{ site.repo_url }}/blob/main/ansible/inventories/host_vars/worker.yaml).

```bash
./scripts/setup.sh config --list rke2
```

| Option | Values |
|--------|--------|
| `version` | RKE2 release, for example `v1.36.5+rke2r1` |
| `cni` | Canal (default), Calico, Cilium, Flannel |
| `loadBalancer` | ServiceLB, MetalLB (IP pool) |
| `ingress` | Bundled Traefik, customised with `HelmChartConfig` values (`ingress-nginx` is archived) |
| `highAvailability.dataStorage` | `etcd` or `postgres` (external database) |
| `tlsSANs`, `nodeLabels`, `nodeTaints` | API certificate names, node labels and taints |

> [!IMPORTANT]
>
> An RKE2 master needs at least **2 CPU and 2 GB RAM**; with less, the bootstrap fails.

## Create the cluster

### Standalone

```bash
# master first (takes a few minutes)
./scripts/setup.sh rke2 setup --host k8s-master-machine
# then each worker
./scripts/setup.sh rke2 setup --host k8s-worker-machine-1
```

### High availability

Fill the HA section of the inventory (`ha_master_init`, `ha_master_join`, `ha_worker`), review `rke2Cluster.highAvailability` in `master.yaml`, then:

```bash
./scripts/setup.sh config edit
./scripts/setup.sh rke2 ha-setup
```

## Get the kubeconfig and verify

RKE2 writes its kubeconfig to `/etc/rancher/rke2/rke2.yaml` and copies it to `~/.kube/config` of the SSH user on the master.

```bash
ssh vagrant@192.168.56.99 'sudo cat /etc/rancher/rke2/rke2.yaml' > ~/.kube/config
sed -i "s/127.0.0.1/192.168.56.99/g" ~/.kube/config

kubectl get nodes -o wide
kubectl get pods -A
```

> [!NOTE]
>
> The Traefik hostPorts move to `8000` / `8443` by default, so they do not clash with ServiceLB.

## Add utilities

```bash
./scripts/setup.sh rke2 utils --list
./scripts/setup.sh rke2 utils certmanager gitops ingress_test
```

See [Utilities]({% link docs/utilities/index.md %}).

## Tear down

```bash
# runs rke2-uninstall.sh on every inventory node
./scripts/setup.sh rke2 destroy
```

## Learn more

- [Extra 2: Rebuild the cluster with RKE2 or K3s](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-Extra-2)
- [Extra 3: RKE2 and the nightmare with network and CoreDNS](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-Extra-3)
