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

module "secret_basic" {
  source = "../../"

  name_prefix = "example-basic"
  description = "Basic secret example"

  secret_string = jsonencode({
    api_key = "example-key"
  })

  recovery_window_days = 7

  tags = {
    Environment = "example"
  }
}

output "secret_arn" {
  value = module.secret_basic.secret_arn
}
