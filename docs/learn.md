---
title: Learn
description: "Learn Kubernetes step by step with the Kubewekend sessions: Vagrant, Ansible, Kind, eBPF and Cilium, high availability, storage and monitoring."
nav_order: 5
permalink: /docs/learn/
---

# Learn Kubernetes with the Kubewekend sessions
{: .no_toc }

Kubewekend grew out of a weekend learning series. Each session explains the *why* behind one part of the lab. Follow them in order as a course, or jump to the topic you are setting up.
{: .fs-5 .fw-300 }

## Main sessions

| # | Topic | You will learn | Article |
|---|-------|----------------|---------|
| 1 | Hosts with Vagrant | Provision VMs with a provider | [Session 1](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-1) |
| 2 | Ansible and Kind | Automate the host setup and bring up a Kind cluster | [Session 2](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-2) |
| 3 | Kubernetes architecture | Explore the components inside a Kind cluster | [Session 3](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-3) |
| 4 | Cilium and eBPF | The kernel networking behind the cluster, with Hubble | [Session 4](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-4) |
| 5 | High availability | Build and operate an HA cluster | [Session 5](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-5) |
| 6 | CSI and Ceph | Storage interfaces and distributed storage | [Session 6](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-6) |
| 7 | Deployments and traffic | Deploy an app and route traffic into the cluster | [Session 7](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-7) |
| 8 | Monitoring with LGTM | Prometheus, Grafana, Loki, Tempo and Alloy | [Session 8](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-8) |

## Extra sessions

| # | Topic | Article |
|---|-------|---------|
| Extra 1 | Longhorn and the story about NFS in Kubernetes | [Extra 1](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-Extra-1) |
| Extra 2 | Rebuild the cluster with RKE2 or K3s | [Extra 2](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-Extra-2) |
| Extra 3 | RKE2 and the nightmare with network and CoreDNS | [Extra 3](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-Extra-3) |
| Extra 4 | Kind as a sandbox environment for GitLab CI | [Extra 4](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-Extra-4) |
| Extra 5 | The security model in Kubernetes | [Extra 5](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-Extra-5) |

> [!NOTE]
>
> The articles describe the lab at the time they were written. When a command differs, the [Getting started]({% link docs/getting-started/index.md %}) pages and the [setup.sh CLI]({% link scripts/README.md %}) are the current reference.
