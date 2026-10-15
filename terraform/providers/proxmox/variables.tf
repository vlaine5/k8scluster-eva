# =============================================================================
#  Variables communes à tous les providers (fournies par ./k8s-lab depuis
#  config/lab.env via TF_VAR_*). Les valeurs par défaut sont identiques.
# =============================================================================

variable "cluster_name" {
  description = "Cluster name (kubectl context will be <cluster_name>-proxmox)."
  type        = string
  default     = "k8s-lab"
}

variable "control_plane_count" {
  description = "Number of control-plane VMs: 1, 3 or 5 (HA with kube-vip, see docs/high-availability.md)."
  type        = number
  default     = 1

  validation {
    condition     = contains([1, 3, 5], var.control_plane_count)
    error_message = "control_plane_count must be 1, 3 or 5 (etcd quorum)."
  }
}

variable "worker_count" {
  description = "Number of worker VMs."
  type        = number
  default     = 2
}

variable "node_os" {
  description = "Operating system of the VMs (ubuntu, debian, rocky): only used for names and tags; the image comes from image_url."
  type        = string
  default     = "ubuntu"
}

variable "node_os_version" {
  description = "Version of node_os (e.g. 24.04, 12, 9)."
  type        = string
  default     = "24.04"
}

variable "os_family" {
  description = "OS family: debian (Ubuntu, Debian) or redhat (Rocky). Selects the admin group of the cloud-init user."
  type        = string
  default     = "debian"
}

variable "longhorn_disk_gb" {
  description = "Size of the dedicated Longhorn disk of each storage node. 0 = no dedicated disk."
  type        = number
  default     = 0
}

variable "longhorn_datastore" {
  description = "Datastore of the dedicated Longhorn disks. Null = vm_datastore."
  type        = string
  default     = null
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
#  Accès à l'API Proxmox. Laissez ces variables à null : le provider lit alors
#  PROXMOX_VE_ENDPOINT / PROXMOX_VE_API_TOKEN / PROXMOX_VE_INSECURE (.env).
#  Ne mettez JAMAIS le token dans terraform.tfvars.
# =============================================================================

variable "proxmox_endpoint" {
  description = "Proxmox API URL (e.g. https://pve.example.lan:8006/). Null = PROXMOX_VE_ENDPOINT."
  type        = string
  default     = null
}

variable "proxmox_api_token" {
  description = "Proxmox API token 'user@realm!name=secret'. Null = PROXMOX_VE_API_TOKEN. Never store it in a versioned file."
  type        = string
  default     = null
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip TLS verification (self-signed certificate only). Null = PROXMOX_VE_INSECURE."
  type        = bool
  default     = null
}

# =============================================================================
#  Variables propres à Proxmox (à définir dans terraform.tfvars)
# =============================================================================

variable "proxmox_node" {
  description = "Name of the Proxmox VE node that hosts the VMs (e.g. pve)."
  type        = string
}

variable "vm_datastore" {
  description = "Datastore of the VM disks (e.g. local-lvm, local-zfs, ceph...)."
  type        = string
  default     = "local-lvm"
}

variable "cloud_init_datastore" {
  description = "Datastore of the cloud-init drives. Null = vm_datastore."
  type        = string
  default     = null
}

variable "image_datastore" {
  description = "Datastore where the cloud image is downloaded. It must allow the 'Import' content type."
  type        = string
  default     = "local"
}

variable "image_url" {
  description = "URL of the cloud image (pinned release, never 'current'). ./k8s-lab sets it from config/versions.yaml (NODE_OS)."
  type        = string
  default     = "https://cloud-images.ubuntu.com/releases/noble/release-20260926/ubuntu-24.04-server-cloudimg-amd64.img"
}

variable "image_sha256" {
  description = "SHA-256 of image_url (from the SHA256SUMS file of the release). Proxmox verifies it."
  type        = string
  default     = "6a81c37564db9b1ee84e141922625e1d7c5b389b99bb3c572e0243607d5bb4d2"

  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.image_sha256))
    error_message = "image_sha256 must be a 64 hexadecimal characters SHA-256."
  }
}

variable "template_vm_id" {
  description = "Optional: ID of an existing cloud-init ready VM template to clone instead of importing image_url."
  type        = number
  default     = null
}

variable "proxmox_nodes" {
  description = "Optional: Proxmox nodes the VMs are spread over, in turn (control-planes first). Empty = proxmox_node only."
  type        = list(string)
  default     = []
}

variable "template_node" {
  description = "Proxmox node that holds template_vm_id. Null = proxmox_node."
  type        = string
  default     = null
}

variable "vm_id_start" {
  description = "Optional: VM ID of the control-plane, workers get the next IDs. Null = let Proxmox choose."
  type        = number
  default     = null
}

variable "cpu_type" {
  description = "Emulated CPU type (x86-64-v2-AES works on most hosts; 'host' is faster but prevents migration)."
  type        = string
  default     = "x86-64-v2-AES"
}

variable "network_bridge" {
  description = "Proxmox bridge the VMs are connected to (e.g. vmbr0)."
  type        = string
  default     = "vmbr0"
}

variable "vlan_id" {
  description = "Optional VLAN tag of the VM network interface. Leave null when the bridge is already on the right VLAN."
  type        = number
  default     = null
}

variable "network_cidr" {
  description = "IPv4 network of the VMs (e.g. 192.168.1.0/24). The VMs get static addresses in it."
  type        = string
}

# Optionnel : trois premiers octets des adresses IP des VM.
# Exemple : network_cidr="10.20.0.0/16", node_ip_prefix="10.20.50", ip_start=10
# -> VM 10.20.50.10/16, puis 10.20.50.11/16, etc.
# Ce parametre NE change PAS le masque reseau des VM (/16 ici).
# Sans cette option, les IP sont calculees depuis network_cidr comme avant.
variable "node_ip_prefix" {
  description = "Optional first three octets of node IPs (e.g. 10.20.50); VM mask still comes from network_cidr."
  type        = string
  default     = null
}

variable "ip_start" {
  description = "Last octet of the first control-plane when node_ip_prefix is set (10 -> 10.20.50.10)."
  type        = number
  default     = 100
}

variable "worker_ip_offset" {
  description = "Offset of the first worker address from ip_start. Null = right after the control-planes."
  type        = number
  default     = null
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

variable "tags" {
  description = "Tags added to every VM."
  type        = list(string)
  default     = ["k8s-lab"]
}

variable "inventory_path" {
  description = "Where to write the Ansible inventory. Null = ansible/inventories/terraform-proxmox.ini."
  type        = string
  default     = null
}
