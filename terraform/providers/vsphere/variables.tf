# =============================================================================
#  Variables communes à tous les providers (fournies par ./k8s-lab depuis
#  config/lab.env via TF_VAR_*). Les valeurs par défaut sont identiques.
# =============================================================================

variable "cluster_name" {
  description = "Cluster name (kubectl context will be <cluster_name>-vsphere)."
  type        = string
  default     = "k8s-lab"
}

variable "worker_count" {
  description = "Number of worker VMs."
  type        = number
  default     = 2
}

variable "hostname_prefix" {
  description = "Hostname prefix of the VMs (k8s -> k8s-cp-1, k8s-worker-1...)."
  type        = string
  default     = "k8s"
}

variable "node_cpus" {
  description = "vCPUs per VM (kubeadm requires at least 2 on the control-plane)."
  type        = number
  default     = 2

  validation {
    condition     = var.node_cpus >= 2
    error_message = "kubeadm requires at least 2 vCPUs."
  }
}

variable "node_memory_mb" {
  description = "Memory per VM in MiB."
  type        = number
  default     = 2048

  validation {
    condition     = var.node_memory_mb >= 2048
    error_message = "Use at least 2048 MiB of memory per node."
  }
}

variable "node_disk_gb" {
  description = "System disk size per VM in GiB (never smaller than the template disk)."
  type        = number
  default     = 20
}

variable "ssh_user" {
  description = "User created by cloud-init (Ansible connects with it)."
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_key" {
  description = "Public SSH key authorized on the VMs (./k8s-lab generates a dedicated one)."
  type        = string
}

variable "ssh_private_key_file" {
  description = "Private key matching ssh_public_key, written in the Ansible inventory."
  type        = string
  default     = "~/.ssh/id_ed25519"
}

# =============================================================================
#  Accès au vCenter. Laissez ces variables à null : le provider lit alors
#  VSPHERE_SERVER / VSPHERE_USER / VSPHERE_PASSWORD (.env).
#  Ne mettez JAMAIS le mot de passe dans terraform.tfvars.
# =============================================================================

variable "vsphere_server" {
  description = "vCenter hostname. Null = VSPHERE_SERVER."
  type        = string
  default     = null
}

variable "vsphere_user" {
  description = "vCenter user. Null = VSPHERE_USER."
  type        = string
  default     = null
}

variable "vsphere_password" {
  description = "vCenter password. Null = VSPHERE_PASSWORD. Never store it in a versioned file."
  type        = string
  default     = null
  sensitive   = true
}

variable "vsphere_allow_unverified_ssl" {
  description = "Skip TLS verification (self-signed certificate only). Null = VSPHERE_ALLOW_UNVERIFIED_SSL."
  type        = bool
  default     = null
}

# =============================================================================
#  Variables propres à vSphere (à définir dans terraform.tfvars)
# =============================================================================

variable "vsphere_datacenter" {
  description = "vCenter datacenter name."
  type        = string
}

variable "vsphere_compute_cluster" {
  description = "vCenter compute cluster that runs the VMs (its root resource pool is used)."
  type        = string
}

variable "vsphere_datastore" {
  description = "Datastore of the VM disks."
  type        = string
}

variable "vsphere_network" {
  description = "Port group the VMs are connected to (e.g. 'VM Network')."
  type        = string
}

variable "vsphere_template" {
  description = "Name (or inventory path) of the Ubuntu cloud image template to clone. See docs/terraform-vsphere.md."
  type        = string
}

variable "vsphere_folder" {
  description = "Optional existing VM folder (relative to the datacenter)."
  type        = string
  default     = null
}

variable "network_cidr" {
  description = "IPv4 network of the VMs (e.g. 10.10.0.0/24). The VMs get static addresses in it."
  type        = string
}

variable "ip_start" {
  description = "Host number of the control-plane in network_cidr (100 -> x.x.x.100); workers follow."
  type        = number
  default     = 100
}

variable "gateway" {
  description = "Default gateway of the VMs. Null = first address of network_cidr."
  type        = string
  default     = null
}

variable "dns_servers" {
  description = "DNS servers of the VMs."
  type        = list(string)
  default     = ["1.1.1.1", "9.9.9.9"]
}

variable "wait_for_guest_net_timeout" {
  description = "Minutes to wait for VMware Tools to report the VM network (0 = do not wait)."
  type        = number
  default     = 5
}

variable "inventory_path" {
  description = "Where to write the Ansible inventory. Null = ansible/inventories/terraform-vsphere.ini."
  type        = string
  default     = null
}
