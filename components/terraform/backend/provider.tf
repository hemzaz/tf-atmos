provider "aws" {
  region = var.region
  # Note: Do not assume role during backend setup as it may not exist yet
}

terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}