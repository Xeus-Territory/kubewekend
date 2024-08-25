Vagrant.configure("2") do |config|
  # # Handle multiple machine in one block of Vagrantfile
  # # https://developer.hashicorp.com/vagrant/docs/multi-machine
  config.vm.define "k8s-master-machine", primary: true do |config|
    config.vm.box = "ubuntu/focal64"
    config.vm.hostname = "k8s-master-machine"
    config.vm.communicator = "ssh"
    # Default enable 2222 for ssh communication (Add id: "ssh" to disable default)
    # https://realguess.net/2015/10/06/overriding-the-default-forwarded-ssh-port-in-vagrant/
    config.vm.network "forwarded_port", guest: 22, host: 6996, protocol: "tcp", id: "ssh", host_ip: "127.0.0.1"
    config.vm.box_check_update = false
    config.ssh.username = ENV["SSH_USER"]
    config.ssh.private_key_path = ENV["SSH_PRIV_KEY_PATH"]
    config.ssh.port = 6996
    config.ssh.guest_port = 22

    # # Disable to generate a key pair inside .vargrant directory, use insecure_private_keys
    # # instead of using private_key
    # config.ssh.insert_key = false

    config.ssh.forward_agent = true

    config.vm.provider "virtualbox" do |config|
      config.name = "k8s-master-machine"
      # Change here when you need more memory to prevent Errors: 137 in Kubernetes
      config.memory = 4092
      config.cpus = 2
    end

    # Add one more disk 10GB for master node, use for ceph prerequisites
    config.vm.disk :disk, size: "10GB", name: "extra_storage"
  end

  # # Use to loo[] over VM defination
  # # Documentation: https://developer.hashicorp.com/vagrant/docs/vagrantfile/tips#loop-over-vm-definitions
  # # Use can use `up` with regex to numberic the machines what you want to provisioning
  # # Example: vagrant up "/k8s-worker-machine-[1-2]/" --provider=virtualbox
  # (1..3).each do |i|
  #   config.vm.define "k8s-worker-machine-#{i}" do |config|
  #     config.vm.box = "ubuntu/focal64"
  #     config.vm.hostname = "k8s-worker-machine-#{i}"
  #     config.vm.communicator = "ssh"
  #     # Default enable 2222 for ssh communication (Add id: "ssh" to disable default)
  #     # https://realguess.net/2015/10/06/overriding-the-default-forwarded-ssh-port-in-vagrant/
  #     # For prevent collisions, use `auto_correct` and `unsable_port_parameter` to guide the port to new one
  #     config.vm.network "forwarded_port", guest: 22, host: 9669, protocol: "tcp", id: "ssh", host_ip: "127.0.0.1", auto_correct: true
  #     config.vm.usable_port_range = 9669..9671
  #     config.vm.box_check_update = false
  #     config.ssh.username = ENV["SSH_USER"]
  #     config.ssh.private_key_path = ENV["SSH_PRIV_KEY_PATH"]
  #     config.ssh.guest_port = 22

  #     # # Disable to generate a key pair inside .vargrant directory, use insecure_private_keys
  #     # # instead of using private_key
  #     # config.ssh.insert_key = false

  #     config.ssh.forward_agent = true

  #     config.vm.provider "virtualbox" do |config|
  #       config.name = "k8s-worker-machine-#{i}"
  #       config.memory = 1024
  #       config.cpus = 1
  #     end
  #   end
  # end

  config.vm.define "k8s-worker-machine-1" do |config|
  config.vm.box = "ubuntu/focal64"
  config.vm.hostname = "k8s-worker-machine-1"
  config.vm.communicator = "ssh"
  # Default enable 2222 for ssh communication (Add id: "ssh" to disable default)
  # https://realguess.net/2015/10/06/overriding-the-default-forwarded-ssh-port-in-vagrant/
  # For prevent collisions, use `auto_correct` and `unsable_port_parameter` to guide the port to new one
  config.vm.network "forwarded_port", guest: 22, host: 9669, protocol: "tcp", id: "ssh", host_ip: "127.0.0.1"
  config.vm.box_check_update = false
  config.ssh.username = ENV["SSH_USER"]
  config.ssh.private_key_path = ENV["SSH_PRIV_KEY_PATH"]
  config.ssh.guest_port = 22
  config.ssh.port = 9669

  # # Disable to generate a key pair inside .vargrant directory, use insecure_private_keys
  # # instead of using private_key
  # config.ssh.insert_key = false

  config.ssh.forward_agent = true

  config.vm.provider "virtualbox" do |config|
    config.name = "k8s-worker-machine-1"
    config.memory = 1024
    config.cpus = 1
  end
end


  # Initialize the shell command to configuration
  $configScript = <<-'SHELL'
  sudo -i
  sudo apt update && sudo apt install curl git -y
  sudo apt install docker.io docker-compose -y
  sudo usermod -aG docker vagrant
  SHELL

  # Reload profile of current user on machine
  $reloadProfile = <<-'SHELL'
  sudo -i
  shutdown -r now
  SHELL

  # Execution the shell script provide
  config.vm.provision "shell", inline: $configScript

  # Configuration auto trigger reload profile in machine after shell
  config.trigger.after :up, :provision do |trigger|
    trigger.info = "Running a after trigger!"
    trigger.run_remote = { inline: $reloadProfile }
    trigger.ignore = [:destroy, :halt]
  end
end
