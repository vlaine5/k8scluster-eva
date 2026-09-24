# Tests du module ansible-inventory : terraform test
variables {
  inventory_path       = "test-inventory.ini"
  cluster_name         = "k8s-lab-test"
  ssh_user             = "ubuntu"
  ssh_private_key_file = "/home/student/.ssh/id_ed25519"
  generated_by         = "terraform test"
  nodes = {
    "k8s-cp-1"      = { name = "k8s-cp-1", role = "control_plane", ip = "10.0.0.10" }
    "k8s-worker-1"  = { name = "k8s-worker-1", role = "worker", ip = "10.0.0.11" }
    "k8s-worker-2"  = { name = "k8s-worker-2", role = "worker", ip = "10.0.0.12" }
    "k8s-worker-10" = { name = "k8s-worker-10", role = "worker", ip = "10.0.0.20" }
  }
}

run "inventory_content" {
  command = plan

  assert {
    condition     = strcontains(output.content, "[control_plane]\nk8s-cp-1 ansible_host=10.0.0.10 node_ip=10.0.0.10\n")
    error_message = "The control-plane group is wrong:\n${output.content}"
  }

  assert {
    condition     = strcontains(output.content, "[workers]\nk8s-worker-1 ansible_host=10.0.0.11 node_ip=10.0.0.11\nk8s-worker-2 ansible_host=10.0.0.12 node_ip=10.0.0.12\nk8s-worker-10 ansible_host=10.0.0.20 node_ip=10.0.0.20\n")
    error_message = "Workers must be listed in natural order:\n${output.content}"
  }

  assert {
    condition     = strcontains(output.content, "ansible_ssh_private_key_file=/home/student/.ssh/id_ed25519") && strcontains(output.content, "cluster_name=k8s-lab-test")
    error_message = "Connection variables are missing:\n${output.content}"
  }
}

run "two_control_planes_are_rejected" {
  command = plan

  variables {
    nodes = {
      "a" = { name = "a", role = "control_plane", ip = "10.0.0.10" }
      "b" = { name = "b", role = "control_plane", ip = "10.0.0.11" }
    }
  }

  expect_failures = [var.nodes]
}
