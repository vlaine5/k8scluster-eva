# Tests du provider libvirt avec un libvirt SIMULÉ (mock_provider) : rien n'est créé.
mock_provider "libvirt" {}
mock_provider "local" {}

variables {
  ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeKeyForTestsOnly k8s-lab-test"
  inventory_path = "test-inventory.ini"
  image_source   = "/tmp/fake-image.qcow2"
}

run "ha_with_longhorn_disks" {
  command = plan

  variables {
    control_plane_count = 3
    worker_count        = 2
    longhorn_disk_gb    = 20
    node_os             = "debian"
    node_os_version     = "12"
  }

  assert {
    condition     = length(libvirt_domain.node) == 5 && length(libvirt_volume.longhorn) == 2
    error_message = "3 control-planes + 2 workers, a Longhorn volume per worker only."
  }

  assert {
    condition     = libvirt_domain.node["k8s-worker-1"].devices.disks[2].serial == "k8slab-longhorn"
    error_message = "The Longhorn disk must carry the k8slab-longhorn serial."
  }

  assert {
    condition     = length(libvirt_domain.node["k8s-cp-2"].devices.disks) == 2
    error_message = "Control-planes get no Longhorn disk when there are workers."
  }

  assert {
    condition     = libvirt_volume.base.name == "k8s-lab-debian-12-base.qcow2"
    error_message = "The base image volume must be named after the OS."
  }
}
