terraform {
  required_version = ">= 1.16.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.65"
    }
    # Patch-level pin: random_pet's words come from the golang-petname
    # version this provider release vendors (eebcea082ee0 in 3.9.0 and 3.9.1).
    # The node group name length validation assumes its word shapes and
    # maxima: names and adjectives at most 8 characters, adverbs at most 10.
    # Re-check those before widening the constraint.
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
