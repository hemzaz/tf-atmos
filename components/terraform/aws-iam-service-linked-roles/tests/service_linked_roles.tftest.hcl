# House test of the catalog's instance (stacks/catalog/aws-iam-service-linked-roles, E6a2; a vendored
# target admits tests/*.tftest.hcl: scripts/check-vendor.py TESTS): the Auto Scaling service-linked
# role kms/main's allow_autoscaling_ebs key-policy grant names is created exactly once, unconditionally
# (no create-if-absent lookup, which would plan its own destroy on the next run), and the
# account-verification mixin refuses a run in another account. Mocked providers, no AWS.
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "777777777777" }
  }
}

# The catalog's values (aws-iam-service-linked-roles/defaults, vendored, account-map-bypass) in fnx-ue1-dev.
variables {
  region      = "us-east-1"
  enabled     = true
  tenant      = "fnx"
  environment = "ue1"
  stage       = "dev"
  name        = "iam-service-linked-roles"

  account_map_enabled = false
  account_map = {
    full_account_map = {
      "fnx-dev"  = "777777777777"
      "fnx-prod" = "999999999999"
    }
  }
  service_linked_roles = {
    autoscaling = {
      aws_service_name = "autoscaling.amazonaws.com"
      description      = "Auto Scaling, named by kms/main's key policy"
    }
  }
}

run "creates_the_autoscaling_role_once" {
  command = plan

  assert {
    condition     = keys(aws_iam_service_linked_role.default) == ["autoscaling"]
    error_message = "The catalog's one entry must plan exactly one service-linked role."
  }

  assert {
    condition     = aws_iam_service_linked_role.default["autoscaling"].aws_service_name == "autoscaling.amazonaws.com"
    error_message = "kms/main's allow_autoscaling_ebs grant names AWSServiceRoleForAutoScaling: the role must be Auto Scaling's."
  }

  assert {
    condition     = length(terraform_data.account_verification) == 1
    error_message = "With account_map set, the account-verification mixin must check the run's account."
  }
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = length(aws_iam_service_linked_role.default) == 0
    error_message = "enabled = false (null-label) must create no service-linked role."
  }
}

run "another_account_is_refused" {
  command = plan

  variables {
    stage = "prod"
  }

  expect_failures = [terraform_data.account_verification]
}
