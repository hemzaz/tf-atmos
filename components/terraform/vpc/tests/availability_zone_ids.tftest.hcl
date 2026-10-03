# Mock-provider tests for availability_zone_ids (Cloud Posse aws-dynamic-subnets
# style): IDs resolve to this account's AZ names through
# data.aws_availability_zones, and exactly one of the two inputs may be set.
# No AWS credentials, no network. Run from the component directory with
# `terraform init -backend=false && terraform test`.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c"]
    }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
}

variables {
  region                  = "us-east-1"
  ipv4_primary_cidr_block = "10.30.0.0/16"
  availability_zones      = null
  availability_zone_ids   = ["use1-az4", "use1-az1"]
  private_subnets         = ["10.30.0.0/18", "10.30.64.0/18"]
  public_subnets          = ["10.30.192.0/22", "10.30.196.0/22"]
  database_subnets        = ["10.30.200.0/24", "10.30.201.0/24", "10.30.202.0/24"]
  vpc_flow_logs_enabled   = false
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

# This account maps use1-az1 to us-east-1c and use1-az4 to us-east-1a. The
# data source returns them in name order, not in the order of the input.
override_data {
  target = data.aws_availability_zones.by_id[0]
  values = {
    names    = ["us-east-1a", "us-east-1c"]
    zone_ids = ["use1-az4", "use1-az1"]
  }
}

run "ids_resolve_to_this_accounts_names_in_input_order" {
  command = plan

  variables {
    availability_zone_ids = ["use1-az1", "use1-az4"]
  }

  assert {
    condition     = aws_subnet.private["10.30.0.0/18"].availability_zone == "us-east-1c" && aws_subnet.private["10.30.64.0/18"].availability_zone == "us-east-1a"
    error_message = "Private subnet N goes to the AZ named by availability_zone_ids[N] in this account."
  }

  assert {
    condition     = aws_subnet.public["10.30.192.0/22"].availability_zone == "us-east-1c" && aws_subnet.public["10.30.196.0/22"].availability_zone == "us-east-1a"
    error_message = "Public subnets follow availability_zone_ids in order."
  }

  assert {
    condition     = aws_subnet.database["10.30.202.0/24"].availability_zone == "us-east-1c"
    error_message = "Database subnets wrap around the resolved AZ list."
  }
}

run "names_still_work_without_ids" {
  command = plan

  variables {
    availability_zones    = ["us-east-1b", "us-east-1c"]
    availability_zone_ids = null
  }

  assert {
    condition     = aws_subnet.private["10.30.0.0/18"].availability_zone == "us-east-1b" && length(data.aws_availability_zones.by_id) == 0
    error_message = "availability_zones (names) is used as is and the zone-id lookup is skipped."
  }
}

run "both_inputs_are_rejected" {
  command = plan

  variables {
    availability_zones    = ["us-east-1a", "us-east-1b"]
    availability_zone_ids = ["use1-az1", "use1-az2"]
  }

  expect_failures = [var.availability_zone_ids]
}

run "neither_input_is_rejected" {
  command = plan

  variables {
    availability_zones    = null
    availability_zone_ids = null
  }

  expect_failures = [var.availability_zone_ids]
}

run "malformed_id_is_rejected" {
  command = plan

  variables {
    availability_zone_ids = ["us-east-1a", "use1-az2"]
  }

  expect_failures = [var.availability_zone_ids]
}

run "unknown_id_fails_the_plan" {
  command = plan

  override_data {
    target = data.aws_availability_zones.by_id[0]
    values = {
      names    = ["us-east-1a"]
      zone_ids = ["use1-az4"]
    }
  }

  variables {
    availability_zone_ids = ["use1-az4", "use1-az9"]
  }

  expect_failures = [aws_vpc.main]
}

run "nat_eip_az_tag_is_the_hosting_subnets_az" {
  command = plan

  variables {
    nat_gateway_enabled  = true
    nat_gateway_strategy = "one_per_az"
  }

  assert {
    condition = (
      aws_eip.nat["10.30.192.0/22"].tags["AZ"] == "us-east-1a"
      && aws_eip.nat["10.30.196.0/22"].tags["AZ"] == "us-east-1c"
    )
    error_message = "Each NAT EIP's AZ tag is the AZ of the public subnet hosting its gateway (use1-az4 -> us-east-1a, use1-az1 -> us-east-1c here)."
  }
}
