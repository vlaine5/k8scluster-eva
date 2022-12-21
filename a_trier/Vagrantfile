# Vagrant file made for deploy a complete K8S cluster with Ansible and Vagrant
# AUTHOR : vLaine
# https://github.com/vlaine5

IMAGE_NAME = "bento/ubuntu-20.04"   # Image to use - Change the repo in common/defaults/main.yml if you change the box
MEM = 2048                          # Amount of RAM
CPU = 2                             # Number of processors (Minimum value of 2 otherwise it will not work)
MASTER_NAME="master"                # Master node name
WORKER_NBR = 3                      # Number of workers node
#WORKER_NAME="worker-#{WORKER_NBR}"
NODE_NETWORK_BASE = "192.168.10"    # First three octets of the IP address that will be assign to all type of nodes
POD_NETWORK = "10.244.0.0/16"    # Private network for inter-pod communication
POD_SUBNET = "10.244.0"    # Private network for inter-pod communication
ESXI_IP = "192.168.1.161" #Provide IP of your ESXI
ESXI_PASS = "password" #Provide password (for root here)
nodes = [
  { hostname: MASTER_NAME, box:'bento/ubuntu-20.04', mac:'00:50:56:19:01:95', numvcpus:'2', ip:"#{NODE_NETWORK_BASE}.26" },
  { hostname: 'worker-1', box:'bento/ubuntu-20.04', mac:'00:50:56:06:11:98', numvcpus:'2', ip:"#{NODE_NETWORK_BASE}.27"  },
  { hostname: 'worker-2', box:'bento/ubuntu-20.04', mac:'00:50:56:06:11:99', numvcpus:'2', ip:"#{NODE_NETWORK_BASE}.28"  },
  { hostname: 'worker-3', box:'bento/ubuntu-20.04', mac:'00:50:56:06:11:80', numvcpus:'2', ip:"#{NODE_NETWORK_BASE}.29"  }
  
]
Vagrant.configure("2") do |config|
  
  nodes.each do |node|

  config.vm.define node[:hostname] do |config|
    config.vm.synced_folder('.', '/Vagrantfiles', type: 'rsync')
    config.vm.box = node[:box]
    config.vm.hostname= node[:hostname]
    config.vm.boot_timeout = 100
    config.vm.graceful_halt_timeout = 100
    config.vm.provision :reload
    #config.vm.network "private_network", ip: "192.168.10.50" #Set up this if you need additionnal interface, don't forget to setup esxi.esxi_virtual_network if you activate this
    config.ssh.insert_key = false
    config.ssh.private_key_path = [
      '~/.ssh/id_rsa',
      '~/.vagrant.d/insecure_private_key'
    ]
    config.vm.provision 'file', 
      source: '~/.ssh/id_rsa.pub', 
      destination: '~/.ssh/authorized_keys'

       # Ansible role setting
       config.vm.provision :ansible do |ansible|
        ansible.playbook = "roles/main.yml"
        # Groups in Ansible inventory
        ansible.groups = {
            "masters" => ["#{MASTER_NAME}"],
            "workers" => ["worker-[1:#{WORKER_NBR}]"]
        }

        # Overload Anqible variables
        ansible.extra_vars = {
            node_ip: "#{NODE_NETWORK_BASE}.26",
            node_name: "master",
            pod_network: "#{POD_NETWORK}",
            pod_subnet: "#{POD_SUBNET}",
            srv_ip: node[:ip]
        }

        
  config.vm.provider :vmware_esxi do |esxi|
    esxi.esxi_hostname = ESXI_IP
    esxi.esxi_username = "root"
    esxi.esxi_password = ESXI_PASS
    esxi.esxi_virtual_network = ['LAN']
    #esxi.esxi_virtual_network = ['LAN', "LAN2"] #If activate, this will setup the ip you provide with config.vm.network on LAN2
    esxi.esxi_disk_store = "datastore1"
    esxi.guest_memsize = "2048"
    esxi.guest_numvcpus = node[:numvcpus]
    esxi.guest_virtualhw_version = '11' #Necessary to compatibilty with ESXI 6.0, check documentation of plugin to see more
    esxi.debug = "true"
    #esxi.guest_custom_vmx_set
    esxi.guest_nic_type = 'vmxnet3'
    esxi.guest_disk_type = 'thin'
    esxi.guest_mac_address = [node[:mac]]
    end  
  end
end
end
end