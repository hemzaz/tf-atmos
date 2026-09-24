# Mock-provider tests: no AWS credentials, no network. Run from the component
# directory with `terraform init -backend=false && terraform test`.
#
# This is the first test file for the rds component; it currently covers only
# the custom_ingress_rules /0 guard (fix/ingress-validation-and-pins). Extend
# it in place for future rds regression coverage.

mock_provider "aws" {}

variables {
  region     = "eu-west-2"
  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  identifier = "test-db"
  db_name    = "testdb"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "default_has_no_custom_ingress_rules" {
  command = plan

  assert {
    condition     = length(var.custom_ingress_rules) == 0
    error_message = "custom_ingress_rules must default to an empty list."
  }
}

run "custom_ingress_open_to_everywhere_is_rejected" {
  command = plan

  variables {
    custom_ingress_rules = [{
      description = "example"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = ["10.0.0.0/8", "0.0.0.0/0"]
    }]
  }

  expect_failures = [var.custom_ingress_rules]
}

run "custom_ingress_ipv6_open_to_everywhere_is_rejected" {
  command = plan

  # ::/0 is as open as 0.0.0.0/0; the prefix-length check must catch both.
  variables {
    custom_ingress_rules = [{
      description = "example"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = ["::/0"]
    }]
  }

  expect_failures = [var.custom_ingress_rules]
}

run "custom_ingress_slash_00_is_rejected" {
  command = plan

  # AWS parses "/00" the same as "/0"; the check compares the prefix length
  # as a number, not as the literal string "0", so this must be caught too.
  variables {
    custom_ingress_rules = [{
      description = "example"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/00"]
    }]
  }

  expect_failures = [var.custom_ingress_rules]
}

run "custom_ingress_from_private_cidr_is_allowed" {
  command = plan

  variables {
    custom_ingress_rules = [{
      description = "example"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = ["10.0.0.0/8"]
    }]
  }

  assert {
    condition     = length(var.custom_ingress_rules) == 1
    error_message = "A private CIDR must be accepted."
  }
}
