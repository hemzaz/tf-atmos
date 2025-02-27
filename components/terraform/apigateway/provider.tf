provider "aws" {
  region = var.region
  
  # Use assume_role if provided
  dynamic "assume_role" {
    for_each = var.assume_role_arn != null && var.assume_role_arn != "" ? [1] : []
    content {
      role_arn = var.assume_role_arn
    }
  }
}

terraform {
  required_version = ">= 1.0.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.9.0"
    }
  }
}