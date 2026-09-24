# Regression coverage for the allow_all_egress default (fix/securitygroup-egress-default).
#
# This repo's "never 0.0.0.0/0 or ::/0" rule governs INGRESS only -- what the
# outside can reach inside. allow_all_egress now defaults to `true`, matching
# Cloudposse; a prior revision defaulted it to `false` as a misreading of the
# ingress-only rule. These runs prove both halves stayed true after the
# revert: egress is unrestricted by default, and the ingress guard
# (enforce_no_public_ingress, itself now defaulting to `true`) rejects
# 0.0.0.0/0 and ::/0 whether set explicitly or left at its default.
#
# mock_provider avoids needing real AWS credentials; `command = plan` is
# enough since every assertion below is knowable without calling AWS.

mock_provider "aws" {}

variables {
  region = "eu-west-2"
  vpc_id = "vpc-0123456789abcdef0"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
  enable_security_group_logging = false
}

run "default_allows_all_egress" {
  command = plan

  variables {
    security_groups = {
      app = {
        description = "test group"
        ingress_rules = [
          {
            key         = "https-vpc"
            from_port   = 443
            to_port     = 443
            protocol    = "tcp"
            cidr_blocks = ["10.0.0.0/16"]
          }
        ]
        egress_rules = []
      }
    }
  }

  # Default preserve_security_group_id is false, so the group's rules --
  # including the reserved _allow_all_egress_ rule allow_all_egress adds --
  # go through aws_security_group_rule.keyed (see main.tf).
  assert {
    condition     = contains(keys(aws_security_group_rule.keyed), "app/_allow_all_egress_")
    error_message = "allow_all_egress default (true) should add the reserved _allow_all_egress_ rule when a group declares no egress_rules."
  }

  assert {
    condition     = aws_security_group_rule.keyed["app/_allow_all_egress_"].type == "egress"
    error_message = "The default all-egress rule must be an egress rule."
  }

  assert {
    condition     = aws_security_group_rule.keyed["app/_allow_all_egress_"].protocol == "-1"
    error_message = "The default all-egress rule must allow all protocols (-1)."
  }

  assert {
    condition     = tolist(aws_security_group_rule.keyed["app/_allow_all_egress_"].cidr_blocks) == tolist(["0.0.0.0/0"])
    error_message = "The default all-egress rule must allow all IPv4 destinations."
  }

  assert {
    condition     = tolist(aws_security_group_rule.keyed["app/_allow_all_egress_"].ipv6_cidr_blocks) == tolist(["::/0"])
    error_message = "The default all-egress rule must allow all IPv6 destinations."
  }
}

run "explicit_false_preserves_no_egress" {
  command = plan

  # A group that sets allow_all_egress: false explicitly (e.g. because it
  # already carries its own all-outbound rule, as the sandbox's `app` and the
  # web-application template's `alb` do) must not gain the reserved rule.
  variables {
    security_groups = {
      db = {
        description      = "test group with egress locked down"
        allow_all_egress = false
        ingress_rules    = []
        egress_rules     = []
      }
    }
  }

  assert {
    condition     = !contains(keys(aws_security_group_rule.keyed), "db/_allow_all_egress_")
    error_message = "allow_all_egress = false must not add the reserved _allow_all_egress_ rule."
  }
}

run "ingress_ipv4_public_cidr_still_rejected" {
  command = plan

  variables {
    enforce_no_public_ingress = true
    security_groups = {
      app = {
        description = "test group"
        ingress_rules = [
          {
            key         = "https-public"
            from_port   = 443
            to_port     = 443
            protocol    = "tcp"
            cidr_blocks = ["0.0.0.0/0"]
          }
        ]
        egress_rules = []
      }
    }
  }

  expect_failures = [
    terraform_data.validate_no_permissive_rules[0],
  ]
}

run "ingress_ipv6_public_cidr_still_rejected" {
  command = plan

  variables {
    enforce_no_public_ingress = true
    security_groups = {
      app = {
        description = "test group"
        ingress_rules = [
          {
            key              = "https-public-v6"
            from_port        = 443
            to_port          = 443
            protocol         = "tcp"
            ipv6_cidr_blocks = ["::/0"]
          }
        ]
        egress_rules = []
      }
    }
  }

  expect_failures = [
    terraform_data.validate_no_permissive_rules[0],
  ]
}

run "default_now_enforces_no_public_ingress" {
  command = plan

  # enforce_no_public_ingress is not set here: this proves the component's
  # own default (now `true`) blocks public ingress without a stack having to
  # opt in explicitly.
  variables {
    security_groups = {
      app = {
        description = "test group"
        ingress_rules = [
          {
            key         = "https-public"
            from_port   = 443
            to_port     = 443
            protocol    = "tcp"
            cidr_blocks = ["0.0.0.0/0"]
          }
        ]
        egress_rules = []
      }
    }
  }

  expect_failures = [
    terraform_data.validate_no_permissive_rules[0],
  ]
}
