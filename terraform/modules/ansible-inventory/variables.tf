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
    condition     = contains([1, 3, 5], length([for n in var.nodes : n if n.role == "control_plane"]))
    error_message = "There must be 1, 3 or 5 nodes with the control_plane role (etcd quorum)."
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

variable "extra_vars" {
  description = "Extra variables written in [k8s_cluster:vars] (e.g. the Longhorn disk selector on vSphere). No secret."
  type        = map(string)
  default     = {}
}
