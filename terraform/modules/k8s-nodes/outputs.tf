output "nodes" {
  description = "Map of node name => { name, role, index, ip, address (ip/prefix) }."
  value       = local.nodes
}

output "control_plane" {
  description = "The control-plane node."
  value       = local.nodes[local.control_plane[0].name]
}

output "workers" {
  description = "List of the worker nodes, in order."
  value       = [for w in local.workers : local.nodes[w.name]]
}

output "cloud_init" {
  description = "Map of node name => { user_data, meta_data, network_config } (cloud-init documents)."
  value       = local.cloud_init
}

output "network_config" {
  description = "Map of node name => network configuration (netplan v2 object)."
  value       = local.network_config
}

output "gateway" {
  description = "Default gateway of the nodes."
  value       = local.gateway
}

output "prefix_length" {
  description = "Prefix length of network_cidr (e.g. 24)."
  value       = local.prefix_length
}

output "ssh_user" {
  description = "User Ansible connects with."
  value       = var.ssh_user
}
