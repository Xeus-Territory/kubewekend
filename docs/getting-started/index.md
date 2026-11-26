---
title: Getting started
description: "Get started with Kubewekend: requirements, node sizing and the setup.sh CLI to build Kind, K3s or RKE2 Kubernetes labs on Vagrant VMs or a VPS."
nav_order: 2
has_children: true
permalink: /docs/getting-started/
---

# Getting started with Kubewekend
{: .no_toc }

Kubewekend runs from an **Ansible controller** (your machine) and builds the cluster on **target hosts**: Vagrant VMs or a remote VPS over SSH. Every step goes through one CLI, `./scripts/setup.sh`, so you never call `ansible-playbook` or `vagrant` yourself.
{: .fs-5 .fw-300 }

1. TOC
{:toc}

## The flow

<ol class="kw-steps">
  <li><strong>Install the tools</strong> and create <code>.env</code>: <code>./scripts/setup.sh env init</code>, then <code>env check</code>. <code>./scripts/setup.sh doctor</code> also checks <code>master.yaml</code> and the inventory, and <code>plan kind</code> shows what a setup would do.</li>
  <li><strong>Prepare the hosts</strong>: Vagrant VMs or a VPS, plus the Ansible inventory. See <a href="{% link docs/getting-started/prepare-hosts.md %}">Prepare hosts</a>.</li>
  <li><strong>Review the configuration</strong> in <code>master.yaml</code>: <code>./scripts/setup.sh config show</code> and <code>config --list</code>.</li>
  <li><strong>Create the cluster</strong>: <a href="{% link docs/getting-started/kind.md %}">Kind</a>, <a href="{% link docs/getting-started/k3s.md %}">K3s</a> or <a href="{% link docs/getting-started/rke2.md %}">RKE2</a>.</li>
  <li><strong>Add utilities</strong> with tags, then verify with the built-in test deployments. See <a href="{% link docs/utilities/index.md %}">Utilities</a>.</li>
</ol>

## Where each distribution runs

| Distribution | Local | VM (Vagrant) | VPS (SSH) |
|---|---|---|---|
| Kind (Kubernetes in Docker) | ✅ | ✅ | ✅ |
| K3s standalone | ❌ | ✅ | ✅ |
| K3s high availability | ❌ | ✅ | ✅ |
| RKE2 standalone | ❌ | ✅ | ✅ |
| RKE2 high availability | ❌ | ✅ | ✅ |

> [!WARNING]
>
> Using your own machine as the target (**Local**) is only supported for **Kind**, and still not recommended: with `networkForwarding` enabled, Kind creates `socat-netforward-port-80/443` systemd services that bind host ports 80/443, so run `./scripts/setup.sh kind destroy` when you finish. K3s and RKE2 install system services, write `/etc/rancher` and change host networking.

Not sure which one to pick? Read [When to use K3s and RKE2 (SUSE)](https://www.suse.com/c/rancher_blog/when-to-use-k3s-and-rke2/) or [the lightweight Kubernetes guide (dev.to)](https://dev.to/pendelabhargavasai/the-definitive-guide-to-lightweight-kubernetes-kind-minikube-microk8s-k3s-vcluster-k0s-and-3be1).

## Requirements

| Tool | Required | Purpose |
|------|----------|---------|
| [VirtualBox](https://www.virtualbox.org/wiki/Downloads) | For VMs | VM provider |
| [Vagrant](https://developer.hashicorp.com/vagrant/docs/installation) | For VMs | VM provisioning |
| [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) | Yes | Cluster orchestration |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | Yes | Kubernetes CLI |
| [Helm](https://helm.sh/docs/intro/install/) | Yes | Chart management |
| [Docker](https://docs.docker.com/engine/install/) | Kind only | Runs the Kind nodes (also installed by the playbook on the target) |
| [jq](https://jqlang.github.io/jq/download/) | Optional | JSON processing |

For a remote VPS you only need Ansible and SSH access; VirtualBox and Vagrant are for local VMs.

```bash
chmod +x ./scripts/setup.sh
# creates .env from template.env: set SSH_USER and SSH_KEY
./scripts/setup.sh env init
# verifies the tools above
./scripts/setup.sh env check
# also checks .env, master.yaml and the inventory, and says what to fix (read-only)
./scripts/setup.sh doctor
# optional: bash or zsh completion for every command, utility tag and host
source <(./scripts/setup.sh completion bash)
```

## Node sizing

A node with too little memory fails during bootstrap or gets killed (`Error 137`).

| Node | Distribution | Minimum | Recommended |
|------|--------------|---------|-------------|
| Master (control plane) | RKE2 | 2 CPU, 2 GB RAM (**lower fails**) | 2 CPU, 3 GB RAM |
| Master (control plane) | K3s | 1 CPU, 1 GB RAM | 2 CPU, 2 GB RAM |
| Master (control plane) | Kind | 1 CPU, 1 GB RAM | 2 CPU, 2 GB RAM |
| Worker | K3s / RKE2 | 1 CPU, 1 GB RAM | 1 GB RAM or more |

The [`Vagrantfile`]({{ site.repo_url }}/blob/main/Vagrantfile) defaults to 2 CPU / 3 GB for masters and 1 CPU / 1 GB for workers. Utilities such as monitoring, GitOps and security need more: raise `config.memory` / `config.cpus` for those labs.

## CLI basics

```bash
# all commands
./scripts/setup.sh help
# help for one command
./scripts/setup.sh <command> help
# project-wide dashboard
./scripts/setup.sh status
# the current master.yaml as a table
./scripts/setup.sh config show
# supported / in-development options and current values
./scripts/setup.sh config --list kind
```

> [!TIP]
>
> Add `--dry-run` to any `setup`, `ha-setup`, `destroy` or `utils` command to print the exact `ansible-playbook` command without running it.

The full command reference is in [setup.sh CLI]({% link scripts/README.md %}).
