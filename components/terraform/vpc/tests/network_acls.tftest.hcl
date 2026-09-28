# Mock-provider tests for the network ACLs: no AWS credentials, no network.
# Run from the component directory with
# `terraform init -backend=false && terraform test`.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]
    }
  }
}

variables {
  region                  = "eu-west-2"
  ipv4_primary_cidr_block = "10.20.0.0/16"
  availability_zones      = ["eu-west-2a", "eu-west-2b"]
  private_subnets         = ["10.20.0.0/18", "10.20.64.0/18"]
  public_subnets          = ["10.20.192.0/22", "10.20.196.0/22"]
  database_subnets        = ["10.20.200.0/24", "10.20.201.0/24"]
  vpc_flow_logs_enabled   = false
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

# A VPC-attached Lambda function (e.g. redis-auth-rotation, reachable from
# the private subnets) sources outbound connections to a database-subnet
# target from its Hyperplane ENI using ports across the full documented
# 1024-65535 ephemeral range, not the narrower 32768-65535 Linux convention.
# The database NACL's return-traffic rules must admit the whole range on
# both legs (ingress: reply routed back into the database subnet on a
# connection it initiated; egress: reply routed OUT of the database subnet
# on a connection a client, including a Lambda, initiated into it) or the
# stateless NACL silently drops roughly half of Lambda's possible source
# ports.
run "database_nacl_admits_full_lambda_ephemeral_range" {
  command = plan

  assert {
    condition = anytrue([
      for r in aws_network_acl.database[0].ingress :
      r.rule_no == 140 && r.from_port == 1024 && r.to_port == 65535
    ])
    error_message = "Database NACL ingress rule 140 must admit ports 1024-65535 (AWS Lambda's documented ephemeral range), not only 32768-65535."
  }

  assert {
    condition = anytrue([
      for r in aws_network_acl.database[0].egress :
      r.rule_no == 100 && r.from_port == 1024 && r.to_port == 65535
    ])
    error_message = "Database NACL egress rule 100 must admit ports 1024-65535 (AWS Lambda's documented ephemeral range), not only 32768-65535."
  }
}
