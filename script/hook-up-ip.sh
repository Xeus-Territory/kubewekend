#!/bin/bash

# Purpose: Use vboxmanage to control and add new network, consume network rules
# Documentation: https://www.techbeatly.com/how-to-create-and-use-natnetwork-in-virtualbox/
# Doc Virtualbox: https://www.virtualbox.org/manual/ch08.html#vboxmanage-natnetwork

# Initialize variables to config network interface
# Use default variables - ISSUE
# https://stackoverflow.com/questions/2013547/assigning-default-values-to-shell-variables-with-a-single-command-in-bash
netName="${1:-"KubewekendNet"}"
netRange="${2:-"10.0.69.0/24"}"

# Clean rule or check existing network to make sure non overlapping
# Use: list and natnetwork
# list: https://www.virtualbox.org/manual/ch08.html#vboxmanage-list
# natnetwork: https://www.virtualbox.org/manual/ch08.html#vboxmanage-natnetwork

if [ "$(vboxmanage list natnetworks | grep -e "$netName")" == "" ]; then
    # Create a network interface
    VBoxManage natnetwork add --netname "$netName" --network "$netRange" --enable
    # Turn on DHCP
    VBoxManage natnetwork modify --netname "$netName" --dhcp on

    echo "💣 Successfully created the interface 💣"
fi

# Check machine name which running and be ready to add cluster
listRunningMachine=$(vagrant status | grep -e "running" | awk '{print $1}')
listPowerOffMachine=$(vagrant status | grep -e "poweroff" | awk '{print $1}')

printf "🚀 Hook-up new ip for kubewekend 🚀\n\n"

if [ "$listPowerOffMachine" != "" ]; then
    for vm in $listPowerOffMachine; do

        # Attach your machine with network interface
        VBoxManage modifyvm "$vm" --nic1 natnetwork --nat-network1 "$netName"
        VBoxManage startvm "$vm" --type headless

        # Loop to validate your machine alive or not
        while true
        do
            if [ "$(VBoxManage showvminfo "$vm" | grep -c "running (since")" == "1" ];then
                printf "☕ Wait a sec to machine alive and providing IP ☕\n"
                sleep 20
                break
            else
                printf "☕ Take a sip coffee and wait to machine alive ☕\n"
                sleep 2
            fi
        done

        # Retrieve the ssh configuration via Vagrant
        machineSSH=$(vagrant ssh-config "$vm")
        portSSH=$(echo "$machineSSH" | grep Port | awk '{print $2}')


        # Retrieve the ip of the machine
        # Issue: https://superuser.com/questions/634195/how-to-get-ip-address-assigned-to-vm-running-in-background
        machineIP=$(VBoxManage guestproperty get "$vm" "/VirtualBox/GuestInfo/Net/0/V4/IP" | cut -d ":" -f2 | xargs)

        ## TODO: Validate exist or not, if exist delete and add new, if not exist add new
        if [ "$(VBoxManage natnetwork list | grep -e "Rule $vm")" != "" ]; then
            VBoxManage natnetwork modify --netname "$netName" --port-forward-4 delete "Rule $vm"
            VBoxManage natnetwork modify --netname "$netName" --port-forward-4 "Rule $vm:tcp:[127.0.0.1]:$portSSH:[$machineIP]:22"
        else
            VBoxManage natnetwork modify --netname "$netName" --port-forward-4 "Rule $vm:tcp:[127.0.0.1]:$portSSH:[$machineIP]:22"
        fi
        echo "$vm is hook-up successfully with $netName"
    done
fi

if [ "$listRunningMachine" != "" ]; then
    for vm in $listRunningMachine; do

        # Retrieve the ssh configuration
        machineSSH=$(vagrant ssh-config "$vm")
        portSSH=$(echo "$machineSSH" | grep Port | awk '{print $2}')

        # Attach your machine with network interface
        VBoxManage startvm "$vm" --type emergencystop
        VBoxManage modifyvm "$vm" --nic1 natnetwork --nat-network1 "$netName"
        VBoxManage startvm "$vm" --type headless

        # Loop to validate your machine alive or not
        while true
        do
            if [ "$(VBoxManage showvminfo "$vm" | grep -c "running (since")" == "1" ];then
                printf "☕ Wait 30 sec to at least machine alive and providing IP ☕\n"
                sleep 30
                break
            else
                printf "☕ Take a sip coffee and wait to machine alive ☕\n"
                sleep 2
            fi
        done

        # Retrieve the ip of the machine
        # Issue: https://superuser.com/questions/634195/how-to-get-ip-address-assigned-to-vm-running-in-background
        machineIP=$(VBoxManage guestproperty get "$vm" "/VirtualBox/GuestInfo/Net/0/V4/IP" | cut -d ":" -f2 | xargs)

        ## TODO: Validate exist or not, if exist delete and add new, if not exist add new
        if [ "$(VBoxManage natnetwork list | grep -e "Rule $vm")" != "" ]; then
            VBoxManage natnetwork modify --netname "$netName" --port-forward-4 delete "Rule $vm"
            VBoxManage natnetwork modify --netname "$netName" --port-forward-4 "Rule $vm:tcp:[127.0.0.1]:$portSSH:[$machineIP]:22"
        else
            VBoxManage natnetwork modify --netname "$netName" --port-forward-4 "Rule $vm:tcp:[127.0.0.1]:$portSSH:[$machineIP]:22"
        fi
        echo "$vm is hook-up successfully with $netName"
    done
fi