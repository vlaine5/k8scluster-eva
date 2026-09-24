variable "hostname_prefix" {
  description = "Hostname prefix of the nodes (k8s -> k8s-cp-1, k8s-worker-1, ...)."
  type        = string
  default     = "k8s"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,40}$", var.hostname_prefix))
    error_message = "hostname_prefix must be lowercase letters, digits or dashes and start with a letter."
  }
}

variable "worker_count" {
  description = "Number of worker nodes (the control-plane is always a single node)."
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

variable "ip_start" {
  description = "Host number of the control-plane inside network_cidr (e.g. 100 -> 192.168.1.100); workers follow."
  type        = number
  default     = 100

  validation {
    condition     = var.ip_start >= 2 && floor(var.ip_start) == var.ip_start
    error_message = "ip_start must be an integer >= 2 (.0 is the network, .1 is usually the gateway)."
  }

  # Validation croisée (Terraform >= 1.9) : toutes les IP doivent tenir dans le réseau.
  validation {
    condition     = !can(cidrhost(var.network_cidr, 0)) || var.ip_start + var.worker_count < pow(2, 32 - tonumber(split("/", var.network_cidr)[1])) - 1
    error_message = "network_cidr is too small for the control-plane + worker_count workers starting at ip_start."
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

variable "ssh_public_key" {
  description = "Public SSH key (OpenSSH format) authorized for ssh_user."
  type        = string

  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp[0-9]+) ", var.ssh_public_key))
    error_message = "ssh_public_key must be an OpenSSH public key (ssh-ed25519 AAAA...)."
  }
}

variable "interface_match" {
  description = "Name pattern of the network interface configured by cloud-init (en* matches ens192, enp1s0...)."
  type        = string
  default     = "en*"
}

variable "extra_packages" {
  description = "Extra packages installed by cloud-init at first boot (e.g. qemu-guest-agent)."
  type        = list(string)
  default     = []
}
