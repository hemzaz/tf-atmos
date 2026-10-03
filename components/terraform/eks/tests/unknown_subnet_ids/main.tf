# Helper for eks.tftest.hcl: the component with subnet ids that are unknown at
# plan time, as in a combined vpc + eks apply. Not a root module of its own.
# ./eks links the component's files except provider.tf, so the module inherits the
# test's mock provider instead of configuring a real one (add a link for a new file).
terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

resource "aws_vpc" "this" {
  cidr_block = "10.99.0.0/16"
}

resource "aws_subnet" "this" {
  count      = 2
  vpc_id     = aws_vpc.this.id
  cidr_block = cidrsubnet("10.99.0.0/16", 8, count.index)
}

module "eks" {
  source = "./eks"

  region     = "us-east-1"
  name       = "main"
  subnet_ids = aws_subnet.this[*].id
  tags       = { Environment = "production", Tenant = "fnx" }
  node_groups = {
    workers = { instance_types = ["m5.xlarge"] }
  }
}
