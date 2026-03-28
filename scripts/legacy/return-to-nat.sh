#!/bin/bash

# Usage: Return the NatNetwork to NAT, and give vagrant can control
# Use When: Interrupt connection with NatNetwork, change back to vagrant can connect  

listProvisioningMachine=$(vagrant status | grep -i "poweroff\|running" | awk '{print $1}')

for vm in $listProvisioningMachine; do
    vagrant halt "$vm"
    VBoxManage modifyvm "$vm" --nic1 nat
    echo "🔙 Return $vm to NAT network 🔙"
done