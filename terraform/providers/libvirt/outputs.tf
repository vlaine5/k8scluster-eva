output "control_plane_ip" {
  description = "IP address of the control-plane."
  value       = module.nodes.control_plane.ip
}

output "worker_ips" {
  description = "IP addresses of the workers."
  value       = [for w in module.nodes.workers : w.ip]
}

output "nodes" {
  description = "Cluster nodes: name => { role, ip }."
  value       = { for name, node in module.nodes.nodes : name => { role = node.role, ip = node.ip } }
}

output "ssh_commands" {
  description = "SSH command for each node."
  value       = { for name, node in module.nodes.nodes : name => "ssh -i ${var.ssh_private_key_file} ${var.ssh_user}@${node.ip}" }
}

output "network" {
  description = "libvirt network created for the lab."
  value       = "${libvirt_network.lab.name} (${var.network_cidr}, gateway ${local.gateway})"
}

output "ansible_inventory" {
  description = "Generated Ansible inventory."
  value       = module.inventory.path
}

output "kubeconfig" {
  description = "Where the kubeconfig is written once Ansible has installed Kubernetes."
  value       = "Run ./k8s-lab kubeconfig terraform libvirt (file: .kube/clusters/${local.context_name}.yaml, context ${local.context_name})"
}
