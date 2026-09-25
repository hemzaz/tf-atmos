# Mock-provider tests for the Cloud Posse aws-vpc input names and for the
# removal of the VPC management IAM role. No AWS credentials, no network.
# Run from the component directory with
# `terraform init -backend=false && terraform test`.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]
    }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
}

variables {
  region                  = "eu-west-2"
  ipv4_primary_cidr_block = "10.30.0.0/16"
  availability_zones      = ["eu-west-2a", "eu-west-2b"]
  private_subnets         = ["10.30.0.0/18", "10.30.64.0/18"]
  public_subnets          = ["10.30.192.0/22", "10.30.196.0/22"]
  vpc_flow_logs_enabled   = false
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "primary_cidr_and_availability_zones" {
  command = plan

  assert {
    condition     = aws_vpc.main.cidr_block == "10.30.0.0/16"
    error_message = "ipv4_primary_cidr_block sets the VPC's CIDR."
  }

  assert {
    condition     = aws_subnet.private["10.30.64.0/18"].availability_zone == "eu-west-2b" && aws_subnet.public["10.30.192.0/22"].availability_zone == "eu-west-2a"
    error_message = "Subnet N is placed in availability_zones[N]."
  }

  assert {
    condition     = contains([for r in aws_network_acl.private[0].ingress : r.cidr_block if r.rule_no == 100], "10.30.0.0/16")
    error_message = "The NACLs' intra-VPC rules use ipv4_primary_cidr_block."
  }
}

run "no_public_ip_on_launch_by_default" {
  command = plan

  assert {
    condition     = alltrue([for s in aws_subnet.public : s.map_public_ip_on_launch == false])
    error_message = "map_public_ip_on_launch defaults to false."
  }
}

run "map_public_ip_on_launch_opt_in" {
  command = plan

  variables {
    map_public_ip_on_launch = true
  }

  assert {
    condition     = alltrue([for s in aws_subnet.public : s.map_public_ip_on_launch])
    error_message = "map_public_ip_on_launch = true maps public IPs in every public subnet."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.private : s.map_public_ip_on_launch != true])
    error_message = "map_public_ip_on_launch never applies to private subnets."
  }
}

run "vpc_flow_logs_disabled" {
  command = plan

  assert {
    condition     = length(aws_flow_log.main) == 0 && length(aws_kms_key.flow_logs) == 0 && length(aws_iam_role.flow_logs) == 0
    error_message = "vpc_flow_logs_enabled = false creates no flow log, key or delivery role."
  }
}

run "vpc_flow_logs_enabled" {
  command = plan

  variables {
    vpc_flow_logs_enabled                  = true
    vpc_flow_logs_traffic_type             = "REJECT"
    vpc_flow_logs_max_aggregation_interval = 60
    vpc_flow_logs_format                   = "$${srcaddr} $${dstaddr}"
  }

  assert {
    condition     = length(aws_flow_log.main) == 1
    error_message = "vpc_flow_logs_enabled = true creates the flow log."
  }

  assert {
    condition     = aws_flow_log.main[0].traffic_type == "REJECT"
    error_message = "vpc_flow_logs_traffic_type reaches the flow log."
  }

  assert {
    condition     = aws_flow_log.main[0].max_aggregation_interval == 60 && aws_flow_log.main[0].log_format == "$${srcaddr} $${dstaddr}"
    error_message = "vpc_flow_logs_max_aggregation_interval and vpc_flow_logs_format reach the flow log."
  }
}

run "nat_gateway_disabled" {
  command = plan

  variables {
    nat_gateway_enabled = false
  }

  assert {
    condition     = length(aws_nat_gateway.main) == 0 && length(aws_eip.nat) == 0
    error_message = "nat_gateway_enabled = false creates no NAT gateway or EIP."
  }
}

run "rejects_bad_aggregation_interval" {
  command = plan

  variables {
    vpc_flow_logs_max_aggregation_interval = 300
  }

  expect_failures = [var.vpc_flow_logs_max_aggregation_interval]
}

# Cloud Posse's aws-vpc has no VPC management role, so neither does this
# component: no iam.tf, no policies/, no instance profile, no variable or
# output for it, and none of the pre-rename input names is declared.
run "no_vpc_management_role_or_old_names" {
  command = plan

  assert {
    condition     = !fileexists("${path.module}/iam.tf") && length(fileset(path.module, "policies/*")) == 0
    error_message = "iam.tf and policies/ are gone."
  }

  assert {
    condition = alltrue([
      for f in fileset(path.module, "*.tf") : !can(regex(
        "aws_iam_instance_profile|vpc_management|create_vpc_iam_role|variable \"(vpc_cidr|cidr_block|azs|enable_nat_gateway|enable_flow_logs|flow_logs_aggregation_interval|flow_logs_custom_format)\"",
        file("${path.module}/${f}")
      ))
    ])
    error_message = "No .tf file declares the management role, its instance profile or outputs, or a pre-rename input."
  }
}
