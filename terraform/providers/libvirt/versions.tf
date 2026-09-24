terraform {
  required_version = ">= 1.9.0"

  required_providers {
    # Provider libvirt (réécriture 0.9.x, schéma calqué sur le XML libvirt) :
    # https://registry.terraform.io/providers/dmacvicar/libvirt
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.9.9"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9"
    }
  }
}
