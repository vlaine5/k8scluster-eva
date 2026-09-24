terraform {
  required_version = ">= 1.9.0"

  required_providers {
    # Provider AWS officiel : https://registry.terraform.io/providers/hashicorp/aws
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.66"
    }
  }
}
