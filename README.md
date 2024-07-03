<h1>Setup the fully kubernetes cluster inside the locally hosted</h1>

<h2>Table of Contents</h2>

- [Use `Vargrant` to configuration the VM with provider](#use-vargrant-to-configuration-the-vm-with-provider)
  - [Requirements tools](#requirements-tools)
  - [Step by step](#step-by-step)
  - [`Vargrant` note](#vargrant-note)
- [Ansible - To setup and run script and bring up kubernetes cluster on locally, Use `kind`](#ansible---to-setup-and-run-script-and-bring-up-kubernetes-cluster-on-locally-use-kind)
  - [Define host for ansible provisioning](#define-host-for-ansible-provisioning)

## Use `Vargrant` to configuration the VM with provider

### Requirements tools

  - Install [virtualbox](https://www.virtualbox.org/wiki/Downloads)
  - Install [vagrant](https://developer.hashicorp.com/vagrant/docs/installation)

### Step by step

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


### `Vargrant` note

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

## Ansible - To setup and run script and bring up kubernetes cluster on locally, Use `kind`

### Define host for ansible provisioning

On this step, you can use script which i create for purpose read and update hosts file for ansible

```bash
# If the file not executable, you can update permission for that
chmod +x ./script/operate-kind-cluster.kind

# Execute the bash script
./script/operate-kind-cluster.sh
```

After that your hosts file will update, like

```yaml
k8s-master-machine ansible_ssh_host=127.0.0.1 ansible_ssh_port=6996 ansible_ssh_user=vagrant
k8s-worker-machine-1 ansible_ssh_host=127.0.0.1 ansible_ssh_port=9669 ansible_ssh_user=vagrant
```

### Run ansible for provisioning k8s with kind

Before you doing this step, you need make sure

- Need to configure Ansible to run the project (Ansible runs only on Linux, so need WSL for window machine or Linux virtual machine)
- Ansible is a bunch of tools built from python3. Install python is obligated for setup ansible environment (Recommended: python_version >= 3.9). Installing ansible ansible-lint via command:

```bash
# Python < 3.12
pip3 install ansible ansible-lint

# With Python = 3.12 (That tough to install :>)
# NOTICE: You need follow the strategy of python
# Recommendation: install apt
sudo apt install python3-ansible-runner -y
# Use pipx instead pip3 to install non-debian package
sudo apt install pipx -y
pipx ensurepath
pipx install ansible-lint
```

After you install all things above, just feel free to update or change configuration inside `./ansible/inventories/host_vars` to update configuration on `master` or `worker`, and one more things ansible will use `template` to configuration `kind`, and you can follow that config and know what variable will map to `template` at `./ansible/templates/kind-config.yaml.j2`

When you confirm all, perform command `ansible-playbook` to help you build kind cluster inside machine. Ansible will include two tags

- **install_common**: Install dependencies and install kind tool, to help you setup kind cluster
- **setup_kind**: Set variables base on your host_name, and execution `kind` command to build cluster base on template

```bash
# Setup control-plane (master) machine
ansible-playbook -i ansible/inventories/hosts --extra-vars="host_name=k8s-master-machine" --tags "install_common,setup_kind" ansible/k8s-provisioning-playbook.yaml
# Setup worker machine
ansible-playbook -i ansible/inventories/hosts --extra-vars="host_name=k8s-worker-machine-1" --tags "install_common,setup_kind" ansible/k8s-provisioning-playbook.yaml
```

<h3>Control Plane when completely provisioning</h3>

![alt text](assets/images/session2/kind-master-cluster.png)

<h3>Worker when completely provisioning</h3>

![alt text](assets/images/session2/Kind-worker-cluster.png)

> 1. On this session, you will have meet the problem about `kind` need control-plane to operate cluster, It means you need at least one cluster to doing control stuff, not only worker node on host. So that cause some misconfiguration, to prevent fail in `ansible`, so I custom the template except `role` variables, now it will do same provisioning for master and worker.

> 2. Base on `kind` techlogies, it use `docker`, on the session we will learn about `docker` extend, use `kubeadm` to join node via `docker` and `socket` that will be tough content 😚😚