# service-linked-roles.tf's create-if-absent logic. The real AWS provider is
# used, not a mock: every other data/resource in this component is exercised
# elsewhere without a tests/ dir, so this file stays scoped to the new
# resource. Credentials are dummies and every data source that would call AWS
# is overridden.
# Run: terraform init -backend=false && terraform test

provider "aws" {
  region                      = "eu-west-2"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

override_data {
  target = data.aws_caller_identity.current
  values = {
    account_id = "123456789012"
  }
}

override_data {
  target = data.aws_iam_roles.existing_autoscaling_slr
  values = {
    names = []
    arns  = []
  }
}

variables {
  region                  = "eu-west-2"
  cross_account_role_name = "test-CrossAccountRole"
  policy_name             = "test-CrossAccountPolicy"
  # Same as the overridden caller identity: trusts_other_accounts is false,
  # so the cross-account trust-condition precondition does not apply.
  trusted_account_ids = ["123456789012"]
  account_id          = "123456789012"
  environment         = "dev"
}

run "creates_the_service_linked_role_when_absent" {
  command = plan

  assert {
    condition     = length(aws_iam_service_linked_role.autoscaling) == 1
    error_message = "manage_autoscaling_service_linked_role defaults to true and the role lookup is overridden to empty, so the role must be created."
  }
}

run "skips_the_service_linked_role_when_it_already_exists" {
  command = plan

  override_data {
    target = data.aws_iam_roles.existing_autoscaling_slr
    values = {
      names = ["AWSServiceRoleForAutoScaling"]
      arns  = ["arn:aws:iam::123456789012:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"]
    }
  }

  assert {
    condition     = length(aws_iam_service_linked_role.autoscaling) == 0
    error_message = "When the lookup finds an existing role, this component must not try to create it again (aws_iam_service_linked_role errors if the role already exists)."
  }

  assert {
    condition     = output.autoscaling_service_linked_role_arn == "arn:aws:iam::123456789012:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
    error_message = "The output must fall back to the looked-up role's ARN when this component does not create one of its own."
  }
}

run "manage_flag_off_never_creates_the_role" {
  command = plan

  variables {
    manage_autoscaling_service_linked_role = false
  }

  assert {
    condition     = length(aws_iam_service_linked_role.autoscaling) == 0
    error_message = "manage_autoscaling_service_linked_role = false must never create the role, even when the lookup finds nothing."
  }
}
