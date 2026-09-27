# service-linked-roles.tf's aws_iam_service_linked_role.autoscaling. The real
# AWS provider is used, not a mock: every other data/resource in this
# component is exercised elsewhere without a tests/ dir, so this file stays
# scoped to the new resource. Credentials are dummies and every data source
# that would call AWS is overridden.
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

run "disabled_by_default_never_creates_the_role" {
  command = plan

  assert {
    condition     = length(aws_iam_service_linked_role.autoscaling) == 0
    error_message = "enable_autoscaling_service_linked_role defaults to false, so no instance creates the role unless it opts in."
  }

  assert {
    condition     = output.autoscaling_service_linked_role_arn == null
    error_message = "The ARN output must be null when this instance does not create the role."
  }
}

run "enabled_creates_the_service_linked_role" {
  command = plan

  variables {
    enable_autoscaling_service_linked_role = true
  }

  assert {
    condition     = length(aws_iam_service_linked_role.autoscaling) == 1
    error_message = "enable_autoscaling_service_linked_role = true must create exactly one service-linked role, unconditionally (no data-source gate: see service-linked-roles.tf for why a create-if-absent lookup of this same resource would flip-flop on every later plan)."
  }
}
