variable "inventory_path" {
  description = "Path of the Ansible inventory file to write (INI format)."
  type        = string
}

variable "cluster_name" {
  description = "Cluster name written in the inventory (kubectl context / kubeadm clusterName)."
  type        = string
}

variable "nodes" {
  description = "Nodes as returned by the k8s-nodes module: map of name => { role, ip, ... }."
  type = map(object({
    name = string
    role = string
    ip   = string
  }))

  validation {
    condition     = length([for n in var.nodes : n if n.role == "control_plane"]) == 1
    error_message = "Exactly one node must have the control_plane role."
  }
}

variable "ssh_user" {
  description = "SSH user Ansible connects with."
  type        = string
}

variable "ssh_private_key_file" {
  description = "Path (on the Ansible controller) of the private SSH key matching the authorized public key."
  type        = string
}

variable "generated_by" {
  description = "Human readable origin written in the file header (e.g. terraform/providers/proxmox)."
  type        = string
}
