terraform {
  required_version = ">= 1.9.0"

  required_providers {
    # Provider officiel VMware (anciennement hashicorp/vsphere) :
    # https://registry.terraform.io/providers/vmware/vsphere
    vsphere = {
      source  = "vmware/vsphere"
      version = "~> 2.17"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9"
    }
  }
}
