---
title: Kind
description: "Create a Kind (Kubernetes in Docker) cluster with Ansible and setup.sh: CNI, load balancer, Traefik ingress and Gateway API, then add utilities."
parent: Getting started
nav_order: 2
---

# Create a Kind cluster
{: .no_toc }

Kubernetes in Docker: the fastest cluster to create and throw away. Good for laptops, workshops and CI sandboxes.
{: .fs-5 .fw-300 }

1. TOC
{:toc}

## Review the options

Kind reads `kindCluster` in [`master.yaml`]({{ site.repo_url }}/blob/main/ansible/inventories/host_vars/master.yaml). List what is supported and the current values:

```bash
./scripts/setup.sh config --list kind
```

| Option | Values |
|--------|--------|
| `numberOfNodes`, `image` | Node count and `kindest/node` image |
| `networking` | CNI: default, Calico, Flannel, Cilium (with `disableDefaultCNI`); `kubeProxyMode` |
| `loadbalancer` | `cloud-provider-kind`, `metallb`, `cilium-ipam-lb` |
| `ingress` | Traefik: ports, `allowCrossNamespace`, dashboard |
| `apigateway` | Gateway API with Traefik |
| `networkForwarding` | Forward host ports 80/443 into the cluster (socat services) |

> [!NOTE]
>
> Traefik is the only supported ingress and Gateway API controller. NGINX, Kong and Cilium ingress/gateway are archived; `kind setup` warns if `master.yaml` selects one.

## Create the cluster

```bash
# common tools + Kind + CNI + load balancer + Traefik
./scripts/setup.sh kind setup
# preview the Ansible command first
./scripts/setup.sh kind setup --dry-run
```

## Verify

On the target host (`./scripts/setup.sh vagrant ssh k8s-master-machine` for a VM):

```bash
kubectl cluster-info --context kind-kubewekend
kubectl get nodes -o wide
kubectl get pods -A
```

## Add utilities

```bash
# tags, options and current values
./scripts/setup.sh kind utils --list
./scripts/setup.sh kind utils certmanager ingress_test dashboard
```

`ingress_test` and `apigateway_test` deploy a sample app behind Traefik so you can check routing. See [Utilities]({% link docs/utilities/index.md %}).

## Tear down

```bash
./scripts/setup.sh kind destroy
# when you used a VM
./scripts/setup.sh vagrant destroy k8s-master-machine
```

> [!WARNING]
>
> On your own machine, `kind destroy` also removes the `socat-netforward-port-80/443` services. If you skip it, disable them with `sudo systemctl disable --now socat-netforward-port-80 socat-netforward-port-443`.

## Learn more

- [Session 2: Setup Kind cluster with Ansible](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-2)
- [Session 4: eBPF with Hubble and Cilium](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-4)
- [Extra 4: Kind as a sandbox for GitLab CI](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-Extra-4)
