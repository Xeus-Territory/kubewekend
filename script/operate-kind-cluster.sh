#!/bin/bash

# Check machine name which running and be ready to add cluster
listRunningMachine=$(vagrant status | grep -e "running" | awk '{print $1}')
# Get the actually path of file you exection
rootProjectLocation=$(dirname -- "$(realpath -- "$(dirname -- "$0")")")
hostsfileLocation="$rootProjectLocation/ansible/inventories/hosts"

# Flush hosts file
echo "" >"$hostsfileLocation"

# Build hosts file
printf "🚀 In-progress to set up for your hosts file 🚀\n\n"
for vm in $listRunningMachine; do
    ssh_config=$(vagrant ssh-config "$vm")
    user=$(echo "$ssh_config" | grep User | head -n1 | awk '{print $2}')
    host=$(echo "$ssh_config" | grep HostName | awk '{print $2}')
    port=$(echo "$ssh_config" | grep Port | awk '{print $2}')
    key_path=$(echo "$ssh_config" | grep IdentityFile | awk '{print $2}')
    # Read about that kind in the article
    # https://medium.com/@megawan/provisioning-vagrant-multi-machines-with-ansible-32e1809816c5
    cat <<EOF | tee -a "$hostsfileLocation" >/dev/null
$vm ansible_ssh_host=$host ansible_ssh_port=$port ansible_ssh_user=$user
EOF
    ssh-add "$key_path" > /dev/null 2>&1
    echo "VM: $vm ✅"
done

printf "\n🤩 Your patience is incredible 🤩"
