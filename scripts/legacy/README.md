# Kubewekend V1 (Kind Cluster) Scripts

> [!WARNING] **Legacy Notice: Kubewekend v1 (Kind Cluster)**
>
> These scripts are exclusively designed for **Kubewekend v1** using **Kind Clusters**. The project is currently being rebuilt to use **k3s**, so these scripts are not compatible with the new k3s-based architecture.

This directory contains utility scripts to manage the local Kubernetes environment setup using Vagrant and VirtualBox.

## `operate-kind-cluster.sh`

This script automates the generation of the Ansible inventory file required for provisioning.

### Functionality
1.  Identifies running Vagrant machines.
2.  Extracts SSH configuration (Host, Port, User, Key) for each machine.
3.  Populates the Ansible hosts file located at `../ansible/inventories/hosts`.
4.  Adds the SSH identity file to the local SSH agent.

### Usage
```bash
./operate-kind-cluster.sh
```

## `hook-up-ip.sh`

This script manages the networking layer for the VirtualBox VMs to ensure they can communicate and are accessible.

### Functionality
1.  Creates a NAT Network in VirtualBox (default name: `KubewekendNet`, CIDR: `10.0.69.0/24`) if it doesn't exist.
2.  Iterates through both powered-off and running Vagrant machines.
3.  Attaches the first network interface (NIC1) of the VMs to the NAT Network.
4.  Starts the VMs (if stopped) or restarts them (if running) to apply network changes.
5.  Configures port forwarding rules on the NAT Network to map local ports to the VM's SSH port (port 22).

### Usage
```bash
./hook-up-ip.sh [NetworkName] [NetworkCIDR]
```

**Arguments:**
*   `NetworkName` (Optional): Name of the NAT Network. Default: `KubewekendNet`.
*   `NetworkCIDR` (Optional): CIDR range for the network. Default: `10.0.69.0/24`.

### Prerequisites
*   VirtualBox installed with `VBoxManage` in the PATH.
*   Vagrant installed.

## `return-to-nat.sh`

This script reverts the network configuration of the VirtualBox VMs to the default NAT mode, effectively undoing the changes made by `hook-up-ip.sh`.

### Functionality
1.  Iterates through the Vagrant machines.
2.  Sets the first network interface (NIC1) back to standard NAT.
3.  Restarts the VMs to apply the network configuration.

### Usage
```bash
./return-to-nat.sh
```
