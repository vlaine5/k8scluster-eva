variable "hostname_prefix" {
  description = "Hostname prefix of the nodes (k8s -> k8s-cp-1, k8s-worker-1, ...)."
  type        = string
  default     = "k8s"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,40}$", var.hostname_prefix))
    error_message = "hostname_prefix must be lowercase letters, digits or dashes and start with a letter."
  }
}

variable "control_plane_count" {
  description = "Number of control-plane nodes: 1, 3 or 5 (etcd needs an odd number for its quorum)."
  type        = number
  default     = 1

  validation {
    condition     = contains([1, 3, 5], var.control_plane_count)
    error_message = "control_plane_count must be 1, 3 or 5 (an even number of etcd members does not tolerate more failures)."
  }
}

variable "worker_count" {
  description = "Number of worker nodes."
  type        = number
  default     = 2

  validation {
    condition     = var.worker_count >= 0 && var.worker_count <= 20 && floor(var.worker_count) == var.worker_count
    error_message = "worker_count must be an integer between 0 and 20."
  }
}

variable "network_cidr" {
  description = "IPv4 network of the nodes, e.g. 192.168.1.0/24. The nodes get static addresses in it."
  type        = string

  validation {
    condition     = can(cidrhost(var.network_cidr, 0)) && !strcontains(var.network_cidr, ":")
    error_message = "network_cidr must be an IPv4 CIDR such as 192.168.1.0/24."
  }
}

variable "node_ip_cidr" {
  description = "Optional IPv4 subnet used for node addresses, within network_cidr."
  type = string
  default = null
}

variable "ip_start" {
  description = "Host number of the first control-plane inside network_cidr (e.g. 100 -> 192.168.1.100)."
  type        = number
  default     = 100

  validation {
    condition     = var.ip_start >= 2 && floor(var.ip_start) == var.ip_start
    error_message = "ip_start must be an integer >= 2 (.0 is the network, .1 is usually the gateway)."
  }

  # Validation croisée (Terraform >= 1.9) : toutes les IP doivent tenir dans le réseau.
  validation {
    condition = !can(cidrhost(var.network_cidr, 0)) || (
      var.ip_start + max(var.control_plane_count, coalesce(var.worker_ip_offset, var.control_plane_count) + var.worker_count)
      < pow(2, 32 - tonumber(split("/", coalesce(var.node_ip_cidr, var.network_cidr))[1])) - 1
    )
    error_message = "network_cidr is too small for the control-planes and workers starting at ip_start."
  }
}

variable "worker_ip_offset" {
  description = "Offset of the first worker address from ip_start. Null = control_plane_count (right after the control-planes)."
  type        = number
  default     = null

  validation {
    condition     = var.worker_ip_offset == null || (var.worker_ip_offset >= var.control_plane_count && floor(var.worker_ip_offset) == var.worker_ip_offset)
    error_message = "worker_ip_offset must be an integer >= control_plane_count (addresses would overlap)."
  }
}

variable "gateway" {
  description = "Default gateway of the nodes. Null = first address of network_cidr."
  type        = string
  default     = null
}

variable "dns_servers" {
  description = "DNS servers configured on the nodes."
  type        = list(string)
  default     = ["1.1.1.1", "9.9.9.9"]
}

variable "dns_search_domains" {
  description = "Optional DNS search domains."
  type        = list(string)
  default     = []
}

variable "ssh_user" {
  description = "User created by cloud-init; Ansible connects with it (passwordless sudo, SSH key only)."
  type        = string
  default     = "ubuntu"
}

variable "os_family" {
  description = "Family of the node OS: debian (Ubuntu, Debian: sudo group) or redhat (Rocky: wheel group)."
  type        = string
  default     = "debian"

  validation {
    condition     = contains(["debian", "redhat"], var.os_family)
    error_message = "os_family must be debian or redhat."
  }
}

variable "ssh_public_key" {
  description = "Public SSH key (OpenSSH format) authorized for ssh_user."
  type        = string

  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp[0-9]+) ", var.ssh_public_key))
    error_message = "ssh_public_key must be an OpenSSH public key (ssh-ed25519 AAAA...)."
  }
}

variable "interface_match" {
  description = "Name pattern of the network interface configured by cloud-init (e* matches ens18, enp1s0, eth0...)."
  type        = string
  default     = "e*"
}

variable "extra_packages" {
  description = "Extra packages installed by cloud-init at first boot (e.g. qemu-guest-agent)."
  type        = list(string)
  default     = []
}

variable "longhorn_disk_gb" {
  description = "Size of the dedicated Longhorn disk of each storage node (workers, or control-planes without worker). 0 = none."
  type        = number
  default     = 0

  validation {
    condition     = var.longhorn_disk_gb == 0 || var.longhorn_disk_gb >= 10
    error_message = "longhorn_disk_gb must be 0 (no dedicated disk) or at least 10 GiB."
  }
}
