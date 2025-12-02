terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0, < 6.0.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "kms_basic" {
  source = "../../"

  name_prefix = "example-basic"
  description = "Basic KMS key example"

  enable_key_rotation = true

  key_administrators = [
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
  ]

  tags = {
    Environment = "example"
  }
}

data "aws_caller_identity" "current" {}

output "key_id" {
  value = module.kms_basic.key_id
}

output "key_arn" {
  value = module.kms_basic.key_arn
}
