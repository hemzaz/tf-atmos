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
# Only the reply leg OUT of the database subnet (egress rule 100) carries
# that wider range as its destination port, so only that rule needs
# widening. The reply leg INTO the database subnet (ingress rule 140) is for
# connections the database subnet itself initiates outbound -- a Lambda's
# request into this subnet arrives on the target service's fixed port
# (rules 100-130), never on rule 140 -- so it stays at the standard Linux
# 32768-65535 range; widening it would also make the per-engine rules
# 100-130 redundant for any VPC-CIDR host on ports 1024-32767.
run "database_nacl_lambda_reply_leg_ranges" {
  command = plan

  assert {
    condition = anytrue([
      for r in aws_network_acl.database[0].ingress :
      r.rule_no == 140 && r.from_port == 32768 && r.to_port == 65535
    ])
    error_message = "Database NACL ingress rule 140 must stay at 32768-65535 (standard Linux ephemeral range for the database subnet's own outbound connections), not be widened to 1024-65535."
  }

  assert {
    condition = anytrue([
      for r in aws_network_acl.database[0].egress :
      r.rule_no == 100 && r.from_port == 1024 && r.to_port == 65535
    ])
    error_message = "Database NACL egress rule 100 must admit ports 1024-65535 (AWS Lambda's documented ephemeral range), not only 32768-65535."
  }
}

# --- Peered VPCs on the private NACL (private_network_acl_peer_cidr_blocks) ---

run "private_nacl_has_no_peer_rules_by_default" {
  command = plan

  assert {
    condition = length([
      for r in concat(tolist(aws_network_acl.private[0].ingress), tolist(aws_network_acl.private[0].egress)) : r
      if r.rule_no >= 200
    ]) == 0
    error_message = "With no peer CIDRs the private NACL must have no peer rules (200+)."
  }
}

# NACLs are stateless: the request in and the reply out both need a rule.
run "private_nacl_allows_each_peer_cidr_both_ways" {
  command = plan

  variables {
    private_network_acl_peer_cidr_blocks = ["10.21.0.0/16", "10.30.0.0/16"]
  }

  assert {
    condition = alltrue([
      for rules in [aws_network_acl.private[0].ingress, aws_network_acl.private[0].egress] :
      length([for r in rules : r if r.rule_no == 200 && r.cidr_block == "10.21.0.0/16" && r.protocol == "-1" && r.action == "allow"]) == 1 &&
      length([for r in rules : r if r.rule_no == 201 && r.cidr_block == "10.30.0.0/16" && r.protocol == "-1" && r.action == "allow"]) == 1
    ])
    error_message = "Each peer CIDR must get an allow-all ingress and egress rule numbered 200 + index."
  }

  assert {
    condition     = length([for r in aws_network_acl.public[0].ingress : r if r.rule_no >= 200]) == 0
    error_message = "Peer rules belong on the private NACL only."
  }
}

run "private_nacl_peer_world_cidr_is_rejected" {
  command = plan

  variables {
    private_network_acl_peer_cidr_blocks = ["10.21.0.0/16", "0.0.0.0/0"]
  }

  expect_failures = [var.private_network_acl_peer_cidr_blocks]
}

run "private_nacl_peer_malformed_cidr_is_rejected" {
  command = plan

  variables {
    private_network_acl_peer_cidr_blocks = ["10.21.0.0"]
  }

  expect_failures = [var.private_network_acl_peer_cidr_blocks]
}
