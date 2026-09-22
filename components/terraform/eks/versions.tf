terraform {
  required_version = ">= 1.16.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.65"
    }
    # Patch-level pin: random_pet's word list comes from the golang-petname
    # version this provider release vendors, and the node group name length
    # validation assumes its longest word is 8 characters. Re-check that
    # before widening the constraint.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9.1"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.4"
    }
  }
}
