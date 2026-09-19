# Common versions configuration - Standardized provider requirements
# This module defines the minimum required versions for all providers

terraform {
  required_version = ">= 1.16.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.9, < 4.0"
    }

    time = {
      source  = "hashicorp/time"
      version = ">= 0.14, < 1.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.4, < 5.0"
    }

    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.8, < 3.0"
    }

    local = {
      source  = "hashicorp/local"
      version = ">= 2.9, < 3.0"
    }

    null = {
      source  = "hashicorp/null"
      version = ">= 3.3, < 4.0"
    }
  }
}
