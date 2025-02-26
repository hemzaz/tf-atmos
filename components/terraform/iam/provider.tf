provider "aws" {
  region = var.region

  assume_role {
    role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.cross_account_role_name}"
  }
}

data "aws_caller_identity" "current" {}

terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}