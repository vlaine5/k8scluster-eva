output "nodes" {
  description = "Map of node name => { name, role, index, ip_offset, ip, address (ip/prefix), longhorn_disk }."
  value       = local.nodes
}

output "control_planes" {
  description = "List of the control-plane nodes, in order (the first one runs kubeadm init)."
  value       = [for n in local.control_planes : local.nodes[n.name]]
}

output "control_plane" {
  description = "The first control-plane node."
  value       = local.nodes[local.control_planes[0].name]
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

output "longhorn_disk_serial" {
  description = "Serial number given to the dedicated Longhorn disks (the storage_disk Ansible role looks for it)."
  value       = "k8slab-longhorn"
}
