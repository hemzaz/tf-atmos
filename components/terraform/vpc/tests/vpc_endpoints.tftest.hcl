# Mock-provider tests for VPC endpoints: no AWS credentials, no network. Run
# from the component directory with
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
  vpc_flow_logs_enabled   = false
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "disabled_by_default" {
  command = plan

  assert {
    condition     = length(aws_vpc_endpoint.interface) == 0 && length(aws_vpc_endpoint.gateway) == 0 && length(aws_security_group.vpc_endpoints) == 0
    error_message = "No endpoint or endpoint security group is created unless enable_vpc_endpoints is true."
  }
}

run "interface_endpoints_scoped_to_vpc_cidr" {
  command = plan

  variables {
    enable_vpc_endpoints = true
    vpc_endpoints        = ["secretsmanager", "elasticache"]
  }

  assert {
    condition     = aws_vpc_endpoint.interface["secretsmanager"].vpc_endpoint_type == "Interface" && aws_vpc_endpoint.interface["secretsmanager"].service_name == "com.amazonaws.eu-west-2.secretsmanager"
    error_message = "secretsmanager must be an Interface endpoint with the correct PrivateLink service name."
  }

  assert {
    condition     = aws_vpc_endpoint.interface["elasticache"].vpc_endpoint_type == "Interface" && aws_vpc_endpoint.interface["elasticache"].service_name == "com.amazonaws.eu-west-2.elasticache"
    error_message = "elasticache must be an Interface endpoint with the correct PrivateLink service name."
  }

  assert {
    condition     = length(aws_vpc_endpoint.gateway) == 0
    error_message = "Neither secretsmanager nor elasticache is a Gateway-type service."
  }

  assert {
    condition = anytrue([
      for r in aws_security_group.vpc_endpoints[0].ingress :
      tolist(r.cidr_blocks) == tolist(["10.20.0.0/16"]) && r.from_port == 443 && r.to_port == 443
    ])
    error_message = "The endpoint security group must admit HTTPS from the VPC CIDR only, never 0.0.0.0/0 -- the whole point is to keep this traffic off the NAT gateway's public /0 reply leg."
  }

  assert {
    condition     = aws_vpc_endpoint.interface["secretsmanager"].private_dns_enabled == true
    error_message = "Private DNS must be enabled so the AWS SDK resolves the endpoint without code changes."
  }
}

run "interface_endpoint_sg_has_no_egress_rule" {
  # aws_security_group.egress is an unknown set of objects until the plan is
  # applied (it depends on the mock provider's post-apply state), so this
  # assertion needs command = apply, unlike the plan-only run above.
  command = apply

  variables {
    enable_vpc_endpoints = true
    vpc_endpoints        = ["secretsmanager", "elasticache"]
  }

  assert {
    condition     = length(aws_security_group.vpc_endpoints[0].egress) == 0
    error_message = "The endpoint security group must declare no egress rule at all (never 0.0.0.0/0) -- an Interface endpoint's ENI only answers inbound 443, and security groups are stateful, so the reply flows back without one."
  }
}

run "s3_uses_gateway_type_and_every_route_table" {
  # route_table_ids is only known after apply (it is built from computed
  # route table ids), so this run needs command = apply, unlike the plan-only
  # runs above.
  command = apply

  variables {
    enable_vpc_endpoints = true
    vpc_endpoints        = ["s3"]
  }

  assert {
    condition     = aws_vpc_endpoint.gateway["s3"].vpc_endpoint_type == "Gateway"
    error_message = "s3 must be a Gateway endpoint, not an Interface endpoint."
  }

  assert {
    condition     = length(aws_vpc_endpoint.gateway["s3"].route_table_ids) == 3
    error_message = "The s3 gateway endpoint must attach to the public route table and both private route tables (one per private subnet here)."
  }

  assert {
    condition     = length(aws_vpc_endpoint.interface) == 0 && length(aws_security_group.vpc_endpoints) == 0
    error_message = "A Gateway-only endpoint list needs no Interface endpoint security group."
  }
}
