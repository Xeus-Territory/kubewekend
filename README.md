# Setup the fully kubernetes cluster inside the locally hosted

<h2>Table of Contents</h2>

- [Use `Vargrant` to configuration the VM with provider](#use-vargrant-to-configuration-the-vm-with-provider)
- [Ansible - To setup and run script and bring up kubernetes cluster on locally, Use `kind`]()
- [Use `kind` and `kubeadm` to expand, manage kubernetes nodes]()
- [Setup `etcd` in kubernetes]()
- [Use `cilium` to setup `ebpf` for observe, networking, service mesh in kubernetes]()
- [Use extend CSI for volume in kubernetes and define kubernetes storage class with `Ceph`]()
- [Cusmtomize default scheduled in kubernetes cluster with `kube-scheduler`]()
- [Setup the monitoring cluster inside the kubernetes with `node-exporter`, `cadvisor`, `prometheus` and `grafana`]()
- [Setup tracing, logging, profiling with `sidecar` or use `cilium-ebpf`]()

## Use `Vargrant` to configuration the VM with provider

### Requirements tools:

  - Install [virtualbox](https://www.virtualbox.org/wiki/Downloads)
  - Install [vagrant](https://developer.hashicorp.com/vagrant/docs/installation)

1. Location on the root of project
2. Set environment from file `.env` or manually configure

```bash
# Manually
export SSH_USER="vargrant-user"
export SSH_PRIV_KEY_PATH="~/.ssh/vmbox"

# Use .env file
cp -r .env.examples .env
set -o allexport && source .env && set +o allexport
```
3. Up your `vagrant` via `virtualbox` by

```bash
# Use can use another provider: https://developer.hashicorp.com/vagrant/docs/providers
# Provision 1 master and 1 worker
vagrant up k8s-master-machine k8s-worker-machine-1 --provider=virtualbox

# You can provision more worker with regex pattern
vagrant up "/k8s-worker-machine-[2-3]/" --provider=virtualbox
```

<h3>Result provisioning</h3>

![alt text](assets/images/session1/vagrant-provisioning.png)

> When you want to destroy, use `destroy` command with option to destroy vm

```bash
# Shutdown and destroy VM for all machines
vagrant destroy --graceful --force

# Specify the target with name
# (Use can regex to manipulate multiple machines)
vagrant destroy k8s-worker-machine-1 --graceful --force
```

> When you want to execute a `shell` script, you can use `provision` command

```bash
# Execute a shell script for all machines
vagrant provision

# Execute a shell script for specific machines
# (Use can regex to manipulate multiple machines)
vagrant provision k8s-worker-machine-1
```

> When you want to turn off the machine provisioning, use `halt` command

```bash
# Turn off all machines provision
vagrant halt

# Turn off the specific machine provision 
# (Use can regex to manipulate multiple machines)
vagrant halt k8s-worker-machine-1
```

> When you want to reload the machine provisioning when update Vargrantfile, use `reload` command

```bash
# Reload all machines provision
vagrant reload

# Reload the specific machine provision
# (Use can regex to manipulate multiple machines)
vagrant reload k8s-worker-machine-1
``` 

> When you want to add a new box to the machine, or cut off time for downloads machine. Use can use `box` command

```bash
# Check actually box we have in host
vagrant box list

# Install box to host
vagrant box add https://location/of/vagrant/box # (Can be local, Vagrant Registry or private storage)

# Example: vagrant box add https://app.vagrantup.com/ubuntu/boxes/focal64
```

When you want to connect to the machine, you have two ways to connect 

- Via `vargrant`, `ssh` command

```bash
# Connect to machine with specified machine name
vagrant ssh k8s-worker-machine-1

# When you want to pass command via ssh
vagrant ssh k8s-worker-machine-1 --command "echo "Hello World" > foo.txt"
```

- Via actions with manually configured `ssh-key`

```bash
# With this action you need to location where .vagrant in your project, usually in root directory
ls .vagrant/

# After that you need run `ssh-agent` to create new session for agent ssh
eval $(ssh-agent -s) # Set the new session agent

# Add the key to your host, and make a authentication
ssh-add ./vagrant/machines/k8s-master-machine/private_key

# And lastone make a connection to machine on custom port
# Befor that you can check again with `vagrant ssh-config` to understand your `ssh` work on port
vagrant ssh-config

# Make a ssh connection
ssh vagrant@127.0.0.1 -p 6996
```

<h3>Show SSH Configuration</h3>

![alt text](assets/images/session1/vagrant-ssh-config.png)

<h3>Make SSH connection</h3>

![alt text](assets/images/session1/vagrant-ssh-success.png)