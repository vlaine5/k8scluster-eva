# Tests du provider vsphere avec un vCenter SIMULÉ (mock_provider) : rien n'est créé.
mock_provider "vsphere" {
  mock_data "vsphere_virtual_machine" {
    defaults = {
      guest_id                = "ubuntu64Guest"
      firmware                = "efi"
      scsi_type               = "pvscsi"
      network_interface_types = ["vmxnet3"]
      disks                   = [{ size = 10, thin_provisioned = true, eagerly_scrub = false, label = "disk0", unit_number = 0 }]
    }
  }
}
mock_provider "local" {}

variables {
  vsphere_datacenter      = "dc"
  vsphere_compute_cluster = "cluster"
  vsphere_datastore       = "ds"
  vsphere_network         = "VM Network"
  vsphere_template        = "ubuntu-24.04-cloud"
  network_cidr            = "192.168.50.0/24"
  ssh_public_key          = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeKeyForTestsOnly k8s-lab-test"
  inventory_path          = "test-inventory.ini"
}

run "ha_anti_affinity_and_longhorn" {
  command = plan

  variables {
    control_plane_count = 3
    worker_count        = 3
    longhorn_disk_gb    = 50
  }

  assert {
    condition     = length(vsphere_compute_cluster_vm_anti_affinity_rule.control_planes) == 1
    error_message = "3 control-planes must get a DRS anti-affinity rule."
  }

  assert {
    condition     = length(vsphere_virtual_machine.node["k8s-worker-1"].disk) == 2 && vsphere_virtual_machine.node["k8s-worker-1"].disk[1].unit_number == 1
    error_message = "Workers must get the Longhorn disk on SCSI unit 1."
  }

  assert {
    condition     = length(vsphere_virtual_machine.node["k8s-cp-1"].disk) == 1
    error_message = "Control-planes get no Longhorn disk when there are workers."
  }

  assert {
    condition     = strcontains(module.inventory.content, "longhorn_disk_match_key=hctl")
    error_message = "The inventory must tell Ansible to find the Longhorn disk by its SCSI address."
  }
}

run "single_control_plane_has_no_rule" {
  command = plan

  assert {
    condition     = length(vsphere_compute_cluster_vm_anti_affinity_rule.control_planes) == 0
    error_message = "No anti-affinity rule with a single control-plane."
  }
}
