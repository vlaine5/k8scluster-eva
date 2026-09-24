# Tests du module k8s-nodes (aucune infrastructure créée) : terraform test
variables {
  network_cidr   = "192.168.10.0/24"
  ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeKeyForTestsOnly k8s-lab-test"
}

run "default_topology" {
  command = plan

  assert {
    condition     = length(output.nodes) == 3
    error_message = "The default topology must be 1 control-plane + 2 workers."
  }

  assert {
    condition     = output.control_plane.name == "k8s-cp-1" && output.control_plane.ip == "192.168.10.100"
    error_message = "The control-plane must be k8s-cp-1 with the first address (ip_start)."
  }

  assert {
    condition     = [for w in output.workers : w.ip] == ["192.168.10.101", "192.168.10.102"]
    error_message = "Workers must get consecutive addresses after the control-plane."
  }

  assert {
    condition     = output.nodes["k8s-worker-2"].address == "192.168.10.102/24"
    error_message = "address must be ip/prefix."
  }

  assert {
    condition     = output.gateway == "192.168.10.1"
    error_message = "The default gateway must be the first address of the network."
  }

  assert {
    condition     = strcontains(output.cloud_init["k8s-cp-1"].user_data, "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeKeyForTestsOnly")
    error_message = "The SSH public key must be in the cloud-init user-data."
  }

  assert {
    condition     = startswith(output.cloud_init["k8s-cp-1"].user_data, "#cloud-config")
    error_message = "user-data must start with #cloud-config."
  }

  assert {
    condition     = yamldecode(output.cloud_init["k8s-worker-1"].network_config).ethernets.primary.addresses[0] == "192.168.10.101/24"
    error_message = "network-config must contain the static address of the node."
  }

  assert {
    condition     = yamldecode(output.cloud_init["k8s-worker-1"].meta_data)["local-hostname"] == "k8s-worker-1"
    error_message = "meta-data must contain the hostname."
  }
}

run "custom_topology" {
  command = plan

  variables {
    hostname_prefix = "lab"
    worker_count    = 4
    ip_start        = 20
    gateway         = "192.168.10.254"
    extra_packages  = ["qemu-guest-agent"]
  }

  assert {
    condition     = length(output.workers) == 4 && output.workers[3].name == "lab-worker-4" && output.workers[3].ip == "192.168.10.24"
    error_message = "worker_count, hostname_prefix and ip_start must be honoured."
  }

  assert {
    condition     = output.gateway == "192.168.10.254"
    error_message = "An explicit gateway must be honoured."
  }

  assert {
    condition     = strcontains(output.cloud_init["lab-cp-1"].user_data, "- qemu-guest-agent")
    error_message = "extra_packages must be installed by cloud-init."
  }
}

run "single_node_cluster" {
  command = plan

  variables {
    worker_count = 0
  }

  assert {
    condition     = length(output.nodes) == 1 && length(output.workers) == 0
    error_message = "worker_count = 0 must create a single control-plane node."
  }
}

run "network_too_small_is_rejected" {
  command = plan

  variables {
    network_cidr = "10.0.0.0/28"
    ip_start     = 10
    worker_count = 8
  }

  expect_failures = [var.ip_start]
}

run "invalid_ssh_key_is_rejected" {
  command = plan

  variables {
    ssh_public_key = "not-a-key"
  }

  expect_failures = [var.ssh_public_key]
}
