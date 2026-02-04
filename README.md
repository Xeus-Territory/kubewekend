# Kubewekend 👨‍🚀🚀☁️🌕

> [!NOTE]
>
>Learn how to setup the fully kubernetes cluster inside your local environment

<div align="center">
	<img src="assets/images/kubewekend-thumbnail.jpeg">
</div>

---

<h2>Table of Contents</h2>

- [Kubewekend 👨‍🚀🚀☁️🌕](#kubewekend-️)
  - [Usage](#usage)
    - [Requirements tools](#requirements-tools)
    - [Step by step](#step-by-step)
      - [Setup Host with Vagrant](#setup-host-with-vagrant)
      - [Setup K8s Cluster and Utilities Features](#setup-k8s-cluster-and-utilities-features)
    - [Helm Chart](#helm-chart)
    - [Troubleshoot](#troubleshoot)
  - [Kubewekend Major Session 🚄🚄🚄](#kubewekend-major-session-)
    - [Kubewekend Session 1: Use `Vargrant` to configuration the VM with provider](#kubewekend-session-1-use-vargrant-to-configuration-the-vm-with-provider)
    - [Kubewekend Session 2: Ansible - To setup and run script and bring up kubernetes cluster on locally, Use `kind`](#kubewekend-session-2-ansible---to-setup-and-run-script-and-bring-up-kubernetes-cluster-on-locally-use-kind)
    - [Kubewekend Session 3: Exploring, understanding and provisioning require components inside the `kind` cluster](#kubewekend-session-3-exploring-understanding-and-provisioning-require-components-inside-the-kind-cluster)
    - [Kubewekend Session 4: `cilium` and `ebpf` - The powerful kernal service of kubewekend cluster](#kubewekend-session-4-cilium-and-ebpf---the-powerful-kernal-service-of-kubewekend-cluster)
    - [Kubewekend Session 5: Build and Operate High Availability (HA) `Kubewekend` Cluster](#kubewekend-session-5-build-and-operate-high-availability-ha-kubewekend-cluster)
    - [Kubewekend Session 6: CSI and Ceph with Kubewekend](#kubewekend-session-6-csi-and-ceph-with-kubewekend)
    - [Kubewekend Session 7: Setup new deployment and route traffic to kubewekend cluster](#kubewekend-session-7-setup-new-deployment-and-route-traffic-to-kubewekend-cluster)
  - [Kubewekend Extra Session 🚢🚢🚢](#kubewekend-extra-session-)
    - [Kubewekend Session Extra 1: Longhorn and the story about NFS in Kubernetes](#kubewekend-session-extra-1-longhorn-and-the-story-about-nfs-in-kubernetes)
    - [Kubewekend Session Extra 2: Rebuild Cluster with RKE2 or K3S](#kubewekend-session-extra-2-rebuild-cluster-with-rke2-or-k3s)
    - [Kubewekend Session Extra 3: RKE2 and The Nightmare with Network and CoreDNS](#kubewekend-session-extra-3-rke2-and-the-nightmare-with-network-and-coredns)
    - [Kubewekend Session Extra 4: Kind and Sandbox environment for GitLab CI](#kubewekend-session-extra-4-kind-and-sandbox-environment-for-gitlab-ci)

## Usage

> [!NOTE]
>
> Supported K8s Distribution with Kubewekend

| Kubewekend Cluster Distribution | Local | VM  | VPS Remote |
| ------------------------------- | ----- | --- | ---------- |
| Kind (K8s in Docker)            | ✅     | ✅   | ⏳          |
| K3s                             | 🚧    | 🚧  | 🚧         |
| RKE2                            | 🚧    | 🚧  | 🚧         |

### Requirements tools

  - Install [virtualbox](https://www.virtualbox.org/wiki/Downloads)
  - Install [vagrant](https://developer.hashicorp.com/vagrant/docs/installation)
  - Install [ansible](https://docs.ansible.com/projects/ansible/latest/installation_guide/intro_installation.html#pipx-install)

### Step by step

#### Setup Host with Vagrant

> [!NOTE]
>
> Read more at [Kubewekend Session 1: Build up your host with Vagrant](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-1)


1. Location on the root of project
2. Up your experiment with `vagrant` and `virtualbox` by

```bash
# Use can use another provider: https://developer.hashicorp.com/vagrant/docs/providers
# Provision only master
vagrant up k8s-master-machine --provider=virtualbox

# Provision 1 master and 1 worker
vagrant up k8s-master-machine k8s-worker-machine-1 --provider=virtualbox

# You can provision more worker with regex pattern
vagrant up "/k8s-worker-machine-[2-3]/" --provider=virtualbox
```

#### Setup K8s Cluster and Utilities Features

> [!NOTE]
>
> After the upgrade 12/2025 and 01/2026, Ansible Playbooks are already rebuilt for multiple concepts which allow you configure a lots of stuff
> with your Kind cluster to test and experiment K8s features
> 
> For more information, you can see what are implementing via table belows

|                            Name of Task                            | Description                                                                                                                                       |          Playbook           | Tags              | State |
| :----------------------------------------------------------------: | ------------------------------------------------------------------------------------------------------------------------------------------------- | :-------------------------: | ----------------- | ----- |
|                  Install Common Kubewekend Tools                   | Install common libraries,kind and dependencies for your host                                                                                      |     kind-playbook.yaml      | install_common    | ✅     |
|                         Setup Kind Cluster                         | Create Kind Cluster with mounting kind-config base on template to ansible host                                                                    |     kind-playbook.yaml      | setup_kind        | ✅     |
|                      Setup Kind Network (CNI)                      | Setup network for Kind Cluster in the situation disableDefaultCNI is true (Options: Calico, Flannel or Cilium)                                    |     kind-playbook.yaml      | setup_kind        | ✅     |
|                Setup Load Balancer for Kind cluster                | Setup Load Balancer for Kind Cluster for external accessing services as type LoadBalancer (Options: metallb, cloud-provider-kind, cilium-ipam-lb) |     kind-playbook.yaml      | setup_kind        | ✅     |
|             Setup Ingress Controller for Kind cluster              | Setup Ingress Controller for Kind Cluster (Options: NGINX, Traefik, Cilium or Kong)                                                               |     kind-playbook.yaml      | setup_kind        | ✅     |
|                 Setup GatewayAPI for Kind cluster                  | Setup GatewayAPI for Kind Cluster (Options: Kong, Cilium or Traefik)                                                                              |     kind-playbook.yaml      | setup_kind        | ✅     |
| Setup Network Forwarding for port 80/443 from home to Kind cluster | Setup Network Forwarding for Kind Cluster (from host to kind cluster) with forwarding rules by socat                                              |     kind-playbook.yaml      | setup_kind        | ✅     |
|                        Remove Kind cluster                         | Remove the Kind cluster and related component when you want to destroy the cluster                                                                |     kind-playbook.yaml      | setup_kind        | ✅     |
|            Ingress test deployment in side the cluster             | Ingress test deployment in side the cluster                                                                                                       | k8s-utilities-playbook.yaml | ingress_test      | ✅     |
|          API Gateway test deployment in side the cluster           | API Gateway test deployment in side the cluster                                                                                                   | k8s-utilities-playbook.yaml | apigateway_test   | ✅     |
|                 Setup cert-manager for the cluster                 | Setup cert-manager for the cluster                                                                                                                | k8s-utilities-playbook.yaml | certmanager       | ✅     |
|                  Setup Dashboard for the cluster                   | Setup Dashboard for the cluster                                                                                                                   | k8s-utilities-playbook.yaml | dashboard         | ✅     |
|              Setup Secret Management for the cluster               | Setup Secret Management for the cluster                                                                                                           | k8s-utilities-playbook.yaml | secret_management | ✅     |
|                Setup K8s Extensions for the cluster                | Setup K8s Extensions for the cluster                                                                                                              | k8s-utilities-playbook.yaml | k8s_extensions    | ✅     |
|                    Setup GitOps for the cluster                    | Setup GitOps for the cluster                                                                                                                      | k8s-utilities-playbook.yaml | gitops            | ✅     |

> [!IMPORTANT]
>
> To making ansible work as requirement when setup Kubewekend, you should refer to inventories with vars file at [master.yaml](./ansible/inventories/host_vars/master.yaml)


```bash
# Execution Directory: ./

# Setup SSH key for ansible
bash ./scripts/kind-clusters/operate-kind-cluster.sh
# Testing the host connection
ansible -i ./ansible/inventories/hosts all -m ping
# Execution configuration
ansible-playbook -i ./ansible/inventories/hosts --extra-vars="host_name=k8s-master-machine" --tags="tags_you_want" ansible/ansible-playbook-you-want.yaml
```

### Helm Chart

For install **helm-charts** from `kubewekend`, you can use **command** 

```bash
helm repo add kubewekend https://kubewekend.xeusnguyen.xyz
```

### Troubleshoot

1. [Error when setup virtualbox in Ubuntu](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Operation-System/Linux/Awesome-Linux-Troubleshoot#error-when-setup-virtualbox-in-ubuntu)
2. [VMSetError: VirtualBox can’t enable the AMD-V extension](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Operation-System/Linux/Awesome-Linux-Troubleshoot#vmseterror-virtualbox-cant-enable-the-amd-v-extension)
3. Specific `Vagrantfile`

   > [!IMPORTANT]
   > 
   > In repositories will be defined some `Vagrantfile` for two type K8s for base and ceph, for specific the Vagrantfile you should specific them via environment variables. Explore more at: [StackOverFlow - Specify Vagrantfile path explicity, if not plugin](https://stackoverflow.com/questions/17308629/specify-vagrantfile-path-explicity-if-not-plugin)

   ```bash
   # Run as usual for base version (Default: Vagrantfile)
   vagrant up name-of-your-machine

   # Run specific Vagrantfile for CEPH version (Example: Vagrantfile.ceph)
   VAGRANT_VAGRANTFILE=Vagrantfile.ceph vagrant up name-of-your-machine
   ```

## Kubewekend Major Session 🚄🚄🚄

### Kubewekend Session 1: Use `Vargrant` to configuration the VM with provider

> [!NOTE]
> 
> This lab is take the topic around play and practice with `vagrant` - the software can help you provide the virtual machine in your host. First step way to setup `kubernetes` cluster inside your machine, and play with on next session

Read full article about session at [Kubewekend Session 1: Build up your host with Vagrant](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-1)

### Kubewekend Session 2: Ansible - To setup and run script and bring up kubernetes cluster on locally, Use `kind`

> [!NOTE]
> 
> This lab is practice with ansible the configuration for setup `kind` cluster inside machine on the previous session

Read full article about session at [Kubewekend Session 2: Setup Kind cluster with Ansible](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-2)

### Kubewekend Session 3: Exploring, understanding and provisioning require components inside the `kind` cluster

> [!NOTE]
> 
> This session talk about basically architecture and learn more fundamental components inside kubernetes, and what the structure of them inside clusters

Read full article about session at [Kubewekend Session 3: Basically about Kubernetes architecture](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-3)

### Kubewekend Session 4: `cilium` and `ebpf` - The powerful kernal service of kubewekend cluster

> [!NOTE]
> 
> This session will talk and learn about eBPF and the especially representation of eBPF are cilium and hubble to become main CNI of Kubewekend and talk about Observability of them

Read full article about session at [Kubewekend Session 4: Learn about ebpf with hubble and cilium](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-4)

### Kubewekend Session 5: Build and Operate High Availability (HA) `Kubewekend` Cluster

> [!NOTE]
> 
> This session is really pleasant when we talk about how can create HA cluster with `kubewekend`, learn more the components inside `kubernetes` and try figure out about `network`, `security`, `configuration`, `container runtime` and `system` via this session

Read full article about session at [Kubewekend Session 5: Build HA Cluster](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-5)

### Kubewekend Session 6: CSI and Ceph with Kubewekend

> [!NOTE]
> 
> This session is covered about topic storage inside `Kubernetes` cluster, how can they work with `CSI` Architecture and why we need to `CSI Driver` for handle this stuff. Furthermore, I try to practice with `Ceph` - one of popular storage opensource for `Kubewekend` cluster

Read full article about session at [Kubewekend 6: CSI and Ceph with Kubewekend](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-6)


### Kubewekend Session 7: Setup new deployment and route traffic to kubewekend cluster

> [!NOTE]
>
> This session explores core networking concepts in Kubernetes, guiding you through the setup of new deployments and demonstrating how to expose services for external access using Ingress and the Gateway API. We also delve into External LoadBalancer concepts and the operational nuances of managing them via Cilium NodeIPAM. By the end of this session, you will understand how to bridge the gap between cluster-internal services and external clients using modern, eBPF-powered networking strategies.

## Kubewekend Extra Session 🚢🚢🚢

### Kubewekend Session Extra 1: Longhorn and the story about NFS in Kubernetes

> [!NOTE]
> 
> This lab is try to take you to journey to learn about new CSI for Kubernetes, `Longhorn` and deliver you to new method to handle transfer large file via network by NFS protocol. I also provide more information about `iSCSI`, `nfs-ganesha` and technique `rdma`

Read full article about session at [Kubewekend Session Extra 1: Longhorn and the story about NFS in Kubernetes](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-Extra-1)


### Kubewekend Session Extra 2: Rebuild Cluster with RKE2 or K3S

> [!NOTE]
> 
> This article aims to provide you with insights into alternatives for self-hosting a full Kubernetes cluster. Both K3s and RKE2 are strong contenders worth considering to guide your decision. Focusing on the self-hosted approach with RKE2, I want to share more about my experiences working with it over the past four months.

Read full article about session at [Kubewekend Session Extra 2: Rebuild Cluster with RKE2 or K3S](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-Extra-2)


### Kubewekend Session Extra 3: RKE2 and The Nightmare with Network and CoreDNS

> [!NOTE]
>
> This article is my story about wrestling with networking in Kubernetes. I'll cover the frustrating problems that arise when your pods can't communicate with services, CoreDNS fails to resolve domains, and the tough issues involving **CNI** and the **ChecksumTX** of network interfaces in Kubernetes.

Read full article about session at [Kubewekend Session Extra 3: RKE2 and The Nightmare with Network and CoreDNS](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-Extra-3)


### Kubewekend Session Extra 4: Kind and Sandbox environment for GitLab CI

> [!NOTE]
>
> This article shares my experience setting up a sandbox environment with Kind to adapt new Kubernetes environments within CI/CD pipelines. I'll provide several ideas for running both CPU and GPU applications, demonstrating their behavior specifically within GitLab CI.

Read full article about session at [Kubewekend Session Extra 4: Kind and Sandbox environment for GitLab CI](https://wiki.xeusnguyen.xyz/Tech-Second-Brain/Personal/Kubewekend/Kubewekend-Session-Extra-4)