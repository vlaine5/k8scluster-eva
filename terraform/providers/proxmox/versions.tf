terraform {
  required_version = ">= 1.9.0"

  required_providers {
    # Provider Proxmox maintenu activement : https://registry.terraform.io/providers/bpg/proxmox
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.114.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9"
    }
  }
}
