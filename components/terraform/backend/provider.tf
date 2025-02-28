provider "aws" {
  region = var.region
  assume_role {
    role_arn = var.iam_role_arn
  }
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