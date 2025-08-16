# Common versions configuration - Standardized provider requirements
# This module defines the minimum required versions for all providers

terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    
    random = {
      source  = "hashicorp/random"
      version = ">= 3.1"
    }
    
    time = {
      source  = "hashicorp/time"
      version = ">= 0.7"
    }
    
    tls = {
      source  = "hashicorp/tls"
      version = ">= 3.0"
    }
    
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.0"
    }
    
    template = {
      source  = "hashicorp/template"
      version = ">= 2.2"
    }
    
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0"
    }
    
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}