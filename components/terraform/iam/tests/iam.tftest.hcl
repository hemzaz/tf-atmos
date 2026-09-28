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

# ci_apply_kms_key_arn: least-privilege access to a customer-managed key the
# apply role deploys resources against (kms/main), scoped to that one ARN --
# a consumer's own IAM policy, never a kms key-policy key_users entry (see
# ../../kms/README.md).
run "ci_apply_kms_policy_is_inert_without_the_apply_role" {
  command = plan

  variables {
    github_oidc_enabled      = true
    github_oidc_repository   = "hemzaz/tf-atmos"
    github_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    ci_role_name_prefix      = "test-ci"
    ci_apply_role_enabled    = false
    ci_apply_kms_key_arn     = "arn:aws:kms:eu-west-2:123456789012:key/11111111-1111-1111-1111-111111111111"
  }

  assert {
    condition     = length(aws_iam_role_policy.ci_apply_kms) == 0
    error_message = "ci_apply_kms_key_arn must not create a policy when ci_apply_role_enabled is false: there is no ci_apply role to attach it to."
  }
}

run "ci_apply_kms_policy_scoped_to_the_one_key_arn" {
  command = plan

  variables {
    github_oidc_enabled        = true
    github_oidc_repository     = "hemzaz/tf-atmos"
    github_oidc_provider_arn   = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    ci_role_name_prefix        = "test-ci"
    ci_apply_role_enabled      = true
    ci_apply_role_environments = ["fnx-prod-production"]
    ci_apply_policy_arns       = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
    ci_apply_kms_key_arn       = "arn:aws:kms:eu-west-2:123456789012:key/11111111-1111-1111-1111-111111111111"
  }

  assert {
    condition = (
      length(aws_iam_role_policy.ci_apply_kms) == 1
      && jsondecode(aws_iam_role_policy.ci_apply_kms[0].policy).Statement[0].Resource == "arn:aws:kms:eu-west-2:123456789012:key/11111111-1111-1111-1111-111111111111"
      && toset(jsondecode(aws_iam_role_policy.ci_apply_kms[0].policy).Statement[0].Action) == toset(["kms:DescribeKey", "kms:CreateGrant", "kms:ListGrants", "kms:RevokeGrant", "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*"])
    )
    error_message = "ci_apply_kms_key_arn must scope the policy to exactly that key ARN (never \"*\") and grant DescribeKey/CreateGrant (required by eks:CreateCluster/UpdateClusterConfig on the calling principal) plus Encrypt/Decrypt/GenerateDataKey* for the other kms/main consumers this role deploys."
  }
}

run "no_ci_apply_kms_policy_without_the_key_arn" {
  command = plan

  variables {
    github_oidc_enabled        = true
    github_oidc_repository     = "hemzaz/tf-atmos"
    github_oidc_provider_arn   = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    ci_role_name_prefix        = "test-ci"
    ci_apply_role_enabled      = true
    ci_apply_role_environments = ["fnx-prod-production"]
    ci_apply_policy_arns       = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
  }

  assert {
    condition     = length(aws_iam_role_policy.ci_apply_kms) == 0
    error_message = "ci_apply_kms_key_arn defaults to null, so no policy should be created without it."
  }
}
