# =============================================================================
#  Variables communes à tous les providers (fournies par ./k8s-lab depuis
#  config/lab.env via TF_VAR_*). Les valeurs par défaut sont identiques.
# =============================================================================

variable "cluster_name" {
  description = "Cluster name (kubectl context will be <cluster_name>-libvirt)."
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
  description = "System disk size per VM in GiB."
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
#  Variables propres à libvirt (valeurs par défaut adaptées à un poste Linux)
# =============================================================================

variable "libvirt_uri" {
  description = "libvirt connection URI."
  type        = string
  default     = "qemu:///system"
}

variable "domain_type" {
  description = "kvm (hardware virtualization, default) or qemu (software emulation, very slow: only when /dev/kvm is missing)."
  type        = string
  default     = "kvm"

  validation {
    condition     = contains(["kvm", "qemu"], var.domain_type)
    error_message = "domain_type must be kvm or qemu."
  }
}

variable "image_source" {
  description = "Ubuntu cloud image: URL or local path (./k8s-lab downloads it and verifies its SHA-256 first)."
  type        = string
  default     = "https://cloud-images.ubuntu.com/releases/noble/release-20260911/ubuntu-24.04-server-cloudimg-amd64.img"
}

variable "storage_pool_path" {
  description = "Directory of the storage pool created for the lab (on the libvirt host)."
  type        = string
  default     = "/var/lib/libvirt/images/k8s-lab"
}

variable "network_cidr" {
  description = "NAT network created for the lab. The VMs get static addresses in it."
  type        = string
  default     = "192.168.123.0/24"
}

variable "ip_start" {
  description = "Host number of the control-plane in network_cidr (10 -> x.x.x.10); workers follow."
  type        = number
  default     = 10
}

variable "inventory_path" {
  description = "Where to write the Ansible inventory. Null = ansible/inventories/terraform-libvirt.ini."
  type        = string
  default     = null
}
