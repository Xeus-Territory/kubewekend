---
title: Prepare hosts
description: "Prepare the hosts for a Kubewekend cluster: Vagrant VirtualBox VMs or a remote VPS, plus the Ansible inventory for standalone and HA clusters."
parent: Getting started
nav_order: 1
---

# Prepare hosts: Vagrant VMs or a remote VPS
{: .no_toc }

Create the machines the cluster runs on, then tell Ansible how to reach them.
{: .fs-5 .fw-300 }

1. TOC
{:toc}

## Option A: Vagrant VMs (VirtualBox)

> [!NOTE]
>
> Background: [Kubewekend Session 1: Build up your host with Vagrant](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-1)

```bash
# Kind, or a single-node K3s / RKE2
./scripts/setup.sh vagrant up k8s-master-machine

# K3s / RKE2 standalone with a worker
./scripts/setup.sh vagrant up k8s-master-machine k8s-worker-machine-1

# K3s / RKE2 with several workers
./scripts/setup.sh vagrant up k8s-master-machine k8s-worker-machine-1 k8s-worker-machine-2
```

Then generate the inventory from the running VMs and check that Ansible can reach them:

```bash
./scripts/setup.sh inventory generate
./scripts/setup.sh inventory ping
```

Other VM commands: `vagrant halt`, `vagrant destroy`, `vagrant ssh <name>` (see `./scripts/setup.sh vagrant help`). To reach services in the VMs through VirtualBox NAT, see `./scripts/setup.sh network help`.

## Option B: a remote VPS

Only Ansible and SSH are needed. The wizard asks for the VPS IP, SSH port, user, key path and number of workers:

```bash
./scripts/setup.sh inventory set-remote
./scripts/setup.sh inventory ping
```

> [!IMPORTANT]
>
> On a VPS, set `tlsSANs` (so the API certificate includes the public IP) and the load-balancer IP pool for your network in `master.yaml` before creating K3s or RKE2: `./scripts/setup.sh config edit`.

## The inventory file

[`ansible/inventories/hosts`]({{ site.repo_url }}/blob/main/ansible/inventories/hosts) has two sections. Fill the one that matches the setup you run:

| Section | Groups | Used by |
|---------|--------|---------|
| 1: Standalone | `standalone-masters`, `standalone-workers` | `kind setup`, `k3s setup`, `rke2 setup` |
| 2: High availability | `ha_master_init` (exactly one), `ha_master_join`, `ha_worker` | `k3s ha-setup`, `rke2 ha-setup` |

### Kind on your own machine (no Vagrant)

Point the master host at `127.0.0.1` with a local connection:

```ini
[standalone-masters]
k8s-master-machine ansible_host=127.0.0.1 ansible_connection=local

[standalone-all:children]
standalone-masters

[all:vars]
ansible_user=<your user>
```

## Next

Create your cluster: [Kind]({% link docs/getting-started/kind.md %}), [K3s]({% link docs/getting-started/k3s.md %}) or [RKE2]({% link docs/getting-started/rke2.md %}).
