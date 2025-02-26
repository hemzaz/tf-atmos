provider "aws" {
  region = var.region

  assume_role {
    role_arn = var.assume_role_arn
  }

  default_tags {
    tags = var.default_tags
  }
}

terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.10"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.5"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9.0"
    }
  }
}

# We intentionally use explicit providers to avoid circular dependencies
# between eks and eks-addons modules.
# This allows the eks-addons module to consume outputs from the eks module 
# without creating circular dependencies.