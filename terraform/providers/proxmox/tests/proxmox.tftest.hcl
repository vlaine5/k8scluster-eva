# Tests du provider proxmox avec un Proxmox SIMULÉ (mock_provider) : aucun appel
# à une API réelle, aucune VM créée. terraform test
mock_provider "proxmox" {}
mock_provider "local" {}

variables {
  proxmox_node   = "pv05"
  network_cidr   = "10.20.0.0/16"
  ip_start       = 100
  ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeKeyForTestsOnly k8s-lab-test"
  inventory_path = "test-inventory.ini"
}

run "homelab_pv05_topology" {
  command = plan

  variables {
    worker_count = 3
    node_cpus    = 2
    vm_id_start  = 700
  }

  assert {
    condition     = length(proxmox_virtual_environment_vm.node) == 4
    error_message = "1 control-plane + 3 workers expected."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.node["k8s-cp-1"].vm_id == 700 && proxmox_virtual_environment_vm.node["k8s-worker-3"].vm_id == 703
    error_message = "VM IDs must follow vm_id_start: control-planes, then workers."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.node["k8s-worker-1"].initialization[0].ip_config[0].ipv4[0].address == "10.20.0.101/16"
    error_message = "The first worker must get 10.20.0.101/16."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.node["k8s-worker-1"].network_device[0].vlan_id == null
    error_message = "No VLAN tag by default (the bridge may already be on the right VLAN)."
  }

  assert {
    condition     = length(proxmox_virtual_environment_vm.node["k8s-worker-1"].disk) == 1
    error_message = "No dedicated Longhorn disk unless longhorn_disk_gb > 0."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.node["k8s-cp-1"].cpu[0].type == "x86-64-v2-AES"
    error_message = "The default CPU type must run on x86-64-v2 hosts (Westmere)."
  }
}

run "ha_spread_over_two_hypervisors" {
  command = plan

  variables {
    control_plane_count = 3
    worker_count        = 2
    proxmox_nodes       = ["pve-a", "pve-b"]
  }

  assert {
    condition     = [for n in ["k8s-cp-1", "k8s-cp-2", "k8s-cp-3"] : proxmox_virtual_environment_vm.node[n].node_name] == ["pve-a", "pve-b", "pve-a"]
    error_message = "Control-planes must be spread over the Proxmox nodes in turn."
  }

  assert {
    condition     = length(proxmox_download_file.image) == 2
    error_message = "The image must be downloaded on each Proxmox node used."
  }
}

run "dedicated_longhorn_disks" {
  command = plan

  variables {
    worker_count       = 3
    longhorn_disk_gb   = 100
    longhorn_datastore = "local-lvm"
  }

  assert {
    condition     = length(proxmox_virtual_environment_vm.node["k8s-cp-1"].disk) == 1
    error_message = "The control-plane gets no Longhorn disk when there are workers."
  }

  assert {
    condition = alltrue([for w in ["k8s-worker-1", "k8s-worker-2", "k8s-worker-3"] :
      length(proxmox_virtual_environment_vm.node[w].disk) == 2 &&
      proxmox_virtual_environment_vm.node[w].disk[1].serial == "k8slab-longhorn" &&
      proxmox_virtual_environment_vm.node[w].disk[1].size == 100 &&
    proxmox_virtual_environment_vm.node[w].disk[1].interface == "scsi1"])
    error_message = "Each worker must get a 100 GiB scsi1 disk with the k8slab-longhorn serial."
  }
}

run "rocky_image_and_user" {
  command = plan

  variables {
    node_os         = "rocky"
    node_os_version = "9"
    os_family       = "redhat"
    ssh_user        = "rocky"
    image_url       = "https://dl.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base-9.8-20260525.0.x86_64.qcow2"
    image_sha256    = "92c206cc6f790c61583247eefe87890f8828420662c17cacf247cec78ab4eec8"
  }

  assert {
    condition     = proxmox_download_file.image["pv05"].file_name == "k8s-lab-rocky-9-Rocky-9-GenericCloud-Base-9.8-20260525.0.x86_64.qcow2"
    error_message = "The imported image name must identify the OS and keep the qcow2 extension."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.node["k8s-cp-1"].initialization[0].user_account[0].username == "rocky"
    error_message = "The cloud-init user must be the OS user."
  }
}

run "even_control_plane_count_is_rejected" {
  command = plan

  variables {
    control_plane_count = 2
  }

  expect_failures = [var.control_plane_count]
}
