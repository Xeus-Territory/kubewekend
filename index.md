---
title: Kubewekend
layout: default
nav_order: 1
nav_exclude: false
search_exclude: false
description: "Build Kind, K3s and RKE2 Kubernetes labs on Vagrant VMs or a VPS with Ansible and one CLI, then add ingress, storage, secrets, GitOps and monitoring."
permalink: /
---

<div class="kw-hero">
  <img src="{{ '/assets/images/kubewekend-logo.png' | relative_url }}" alt="Kubewekend logo: an astronaut steering a ship's wheel">
  <div>
    <h1>Kubewekend</h1>
    <p class="kw-tagline">The Kubernetes playground on the weekend. Spin up <strong>Kind</strong>, <strong>K3s</strong> or <strong>RKE2</strong> on VMs or a VPS with one CLI, then add ingress, storage, secrets, GitOps, security, monitoring and service mesh, ready to test.</p>
    <a href="{% link docs/getting-started/index.md %}" class="btn btn-primary fs-5 mr-2">Get started</a>
    <a href="{% link scripts/README.md %}" class="btn fs-5 mr-2">setup.sh CLI</a>
    <a href="{{ site.repo_url }}" class="btn fs-5">GitHub</a>
  </div>
</div>

## Pick your path

<div class="kw-cards">
  <a class="kw-card" href="{% link docs/getting-started/kind.md %}">
    <strong>Kind</strong>
    <span>Kubernetes in Docker. Fastest to create and throw away: laptops, workshops, CI sandboxes.</span>
  </a>
  <a class="kw-card" href="{% link docs/getting-started/k3s.md %}">
    <strong>K3s</strong>
    <span>Lightweight, single binary. Small teams and edge labs, HA with embedded etcd or PostgreSQL.</span>
  </a>
  <a class="kw-card" href="{% link docs/getting-started/rke2.md %}">
    <strong>RKE2</strong>
    <span>Security-focused distribution. Bigger teams and production-like labs, HA with etcd or PostgreSQL.</span>
  </a>
</div>

| | Kind | K3s | RKE2 |
|---|---|---|---|
| **Best for** | Quick experiments, CI, workshops | Small teams, edge, light HA | Production-like and security labs |
| **Runs on** | Local, VM, VPS | VM, VPS | VM, VPS |
| **High availability** | No | Yes (`k3s ha-setup`) | Yes (`rke2 ha-setup`) |
| **Minimum master node** | 1 CPU, 1 GB RAM | 1 CPU, 1 GB RAM | 2 CPU, 2 GB RAM |
| **CNI options** | Calico, Flannel, Cilium | Flannel, Calico, Cilium | Canal, Calico, Cilium, Flannel |

> [!WARNING]
>
> K3s and RKE2 install system services and change host networking, so run them on a **VM or VPS**, never on your own machine.
> Kind can run locally (inside Docker), but a VM is still recommended.

## Quick start

From a fresh clone, with VirtualBox, Vagrant, Ansible, kubectl and Helm installed:

```bash
# 1. Create .env (SSH user / key) and check the tools
./scripts/setup.sh env init && ./scripts/setup.sh env check
# 2. One VM, and the Ansible inventory from the running VMs
./scripts/setup.sh vagrant up k8s-master-machine
./scripts/setup.sh inventory generate
# 3. A Kind cluster with Traefik ingress
./scripts/setup.sh kind setup
# 4. Utilities, added with tags
./scripts/setup.sh kind utils certmanager ingress_test
```

Prefer a guided tour? `./scripts/setup.sh quickstart kind-vagrant` (also `k3s-vagrant`, `k3s-remote`, `rke2-vagrant`, `rke2-remote`).

## What you can install

Every utility is one tag on `<distribution> utils`, configured in [`master.yaml`]({{ site.repo_url }}/blob/main/ansible/inventories/host_vars/master.yaml). See [Utilities]({% link docs/utilities/index.md %}) for options and status.

<div class="kw-cards">
  <div class="kw-card"><strong>Networking</strong><span>Traefik ingress and Gateway API, MetalLB, cloud-provider-kind, Cilium</span></div>
  <div class="kw-card"><strong>Storage</strong><span>Longhorn or local-path-provisioner, with a PVC test</span></div>
  <div class="kw-card"><strong>Secrets</strong><span>Vault or OpenBao (dev / standalone), External Secrets</span></div>
  <div class="kw-card"><strong>GitOps</strong><span>Argo CD (+ Image Updater) or Flux (+ Weave GitOps), Kargo</span></div>
  <div class="kw-card"><strong>Security</strong><span>Kyverno or OPA Gatekeeper, Dex identity provider</span></div>
  <div class="kw-card"><strong>Observability</strong><span>Prometheus, Grafana, Alloy, Loki, Tempo, Pyroscope</span></div>
  <div class="kw-card"><strong>Service mesh</strong><span>Istio (sidecar mode)</span></div>
  <div class="kw-card"><strong>Dashboards</strong><span>Headlamp, Kubernetes Dashboard, Rancher</span></div>
</div>

## Learn while you build

Kubewekend started as a weekend learning series. Each session explains the *why* behind a part of the lab, from Vagrant and Ansible to eBPF, HA, storage and monitoring: see [Learn]({% link docs/learn.md %}).
