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

# ci_apply_kms_key_aliases: least-privilege access to customer-managed key(s)
# the apply role deploys resources against (kms/main), scoped by alias via a
# kms:ResourceAliases condition rather than a key ARN -- a consumer's own IAM
# policy, never a kms key-policy key_users entry (see ../../kms/README.md).
# Alias-scoped, not ARN-scoped, because iam/ci plans and applies in the
# deploy-full-stack layer BEFORE kms/main (../../../../workflows/deploy-full-stack.yaml),
# so a !terraform.state read of the key's ARN would create a layer-order
# cycle (kms/main already depends on iam).
run "ci_apply_kms_policy_is_inert_without_the_apply_role" {
  command = plan

  variables {
    github_oidc_enabled      = true
    github_oidc_repository   = "hemzaz/tf-atmos"
    github_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    ci_role_name_prefix      = "test-ci"
    ci_apply_role_enabled    = false
    ci_apply_kms_key_aliases = ["alias/test-main"]
  }

  assert {
    condition     = length(aws_iam_role_policy.ci_apply_kms) == 0
    error_message = "ci_apply_kms_key_aliases must not create a policy when ci_apply_role_enabled is false: there is no ci_apply role to attach it to."
  }
}

run "ci_apply_kms_policy_scoped_to_the_key_aliases" {
  command = plan

  variables {
    github_oidc_enabled        = true
    github_oidc_repository     = "hemzaz/tf-atmos"
    github_oidc_provider_arn   = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    ci_role_name_prefix        = "test-ci"
    ci_apply_role_enabled      = true
    ci_apply_role_environments = ["fnx-prod-production"]
    ci_apply_policy_arns       = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
    ci_apply_kms_key_aliases   = ["alias/production-main"]
  }

  assert {
    condition     = length(aws_iam_role_policy.ci_apply_kms) == 1
    error_message = "ci_apply_kms_key_aliases must create exactly one policy when set together with the apply role."
  }

  assert {
    condition = (
      length(jsondecode(aws_iam_role_policy.ci_apply_kms[0].policy).Statement) == 2
      && jsondecode(aws_iam_role_policy.ci_apply_kms[0].policy).Statement[0].Resource == "*"
      && jsondecode(aws_iam_role_policy.ci_apply_kms[0].policy).Statement[1].Resource == "*"
    )
    error_message = "ci_apply_kms_key_aliases must never scope to resources = [\"*\"] without a kms:ResourceAliases condition narrowing it (checked below); the key ARN is unknown when this component plans, since iam/ci deploys before kms/main."
  }

  # A single-element condition value list serializes as a bare string in the
  # generated policy JSON (aws_iam_policy_document / AWS IAM convention), not
  # a one-element array -- hence the scalar comparison below.
  assert {
    condition = (
      toset(jsondecode(aws_iam_role_policy.ci_apply_kms[0].policy).Statement[0].Action) == toset(["kms:DescribeKey", "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*"])
      && jsondecode(aws_iam_role_policy.ci_apply_kms[0].policy).Statement[0].Condition["ForAnyValue:StringEquals"]["kms:ResourceAliases"] == "alias/production-main"
    )
    error_message = "The key-use statement must grant DescribeKey (required by eks:CreateCluster/UpdateClusterConfig on the calling principal) plus Encrypt/Decrypt/GenerateDataKey* for the other kms/main consumers this role deploys, scoped to exactly the configured alias(es) via kms:ResourceAliases."
  }

  assert {
    condition = (
      toset(jsondecode(aws_iam_role_policy.ci_apply_kms[0].policy).Statement[1].Action) == toset(["kms:CreateGrant", "kms:ListGrants", "kms:RevokeGrant"])
      && jsondecode(aws_iam_role_policy.ci_apply_kms[0].policy).Statement[1].Condition["ForAnyValue:StringEquals"]["kms:ResourceAliases"] == "alias/production-main"
      && jsondecode(aws_iam_role_policy.ci_apply_kms[0].policy).Statement[1].Condition["Bool"]["kms:GrantIsForAWSResource"] == "true"
    )
    error_message = "CreateGrant/ListGrants/RevokeGrant must be split into their own statement, scoped to the configured alias(es) AND kms:GrantIsForAWSResource = true (AWS's documented pattern for AWS-service-managed grants, e.g. the EKS cluster secrets grant this role deploys)."
  }
}

run "no_ci_apply_kms_policy_without_the_key_aliases" {
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
    error_message = "ci_apply_kms_key_aliases defaults to null, so no policy should be created without it."
  }
}

# State access: the CI roles reach the single state backend (backend/main in
# fnx-core-root) only through its access roles -- the plan role may assume the
# READ-only role, the apply role the WRITE role -- and hold no S3/KMS grant on
# the state bucket themselves (so no lock-object writes from plans either).
run "ci_state_access_is_sts_assume_role_on_the_backend_roles_only" {
  command = plan

  variables {
    github_oidc_enabled        = true
    github_oidc_repository     = "hemzaz/tf-atmos"
    github_oidc_provider_arn   = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    ci_role_name_prefix        = "test-ci"
    ci_apply_role_enabled      = true
    ci_apply_role_environments = ["fnx-prod-production"]
    ci_apply_policy_arns       = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
    ci_backend_read_role_arns = [
      "arn:aws:iam::111111111111:role/fnx-terraform-backend-prod-read-role",
      "arn:aws:iam::111111111111:role/fnx-terraform-backend-read-role",
    ]
    ci_backend_write_role_arn = "arn:aws:iam::111111111111:role/fnx-terraform-backend-role"
  }

  assert {
    condition = (
      length(jsondecode(aws_iam_role_policy.ci_plan_state[0].policy).Statement) == 1
      && jsondecode(aws_iam_role_policy.ci_plan_state[0].policy).Statement[0].Action == "sts:AssumeRole"
      && toset(jsondecode(aws_iam_role_policy.ci_plan_state[0].policy).Statement[0].Resource) == toset([
        "arn:aws:iam::111111111111:role/fnx-terraform-backend-prod-read-role",
        "arn:aws:iam::111111111111:role/fnx-terraform-backend-read-role",
      ])
    )
    error_message = "The plan role's only state grant is sts:AssumeRole on the backend's read-only role(s): no s3:PutObject/DeleteObject (lock files) and no KMS."
  }

  assert {
    condition = (
      length(jsondecode(aws_iam_role_policy.ci_apply_state[0].policy).Statement) == 1
      && jsondecode(aws_iam_role_policy.ci_apply_state[0].policy).Statement[0].Action == "sts:AssumeRole"
      && jsondecode(aws_iam_role_policy.ci_apply_state[0].policy).Statement[0].Resource == "arn:aws:iam::111111111111:role/fnx-terraform-backend-role"
    )
    error_message = "The apply role's only state grant is sts:AssumeRole on the backend's write role."
  }
}

run "no_ci_state_policies_without_the_backend_role_arns" {
  command = plan

  variables {
    github_oidc_enabled      = true
    github_oidc_repository   = "hemzaz/tf-atmos"
    github_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    ci_role_name_prefix      = "test-ci"
  }

  assert {
    condition     = length(aws_iam_role_policy.ci_plan_state) == 0 && length(aws_iam_role_policy.ci_apply_state) == 0
    error_message = "ci_backend_read_role_arns/ci_backend_write_role_arn default to empty/null, so no state policy is created without them."
  }
}

run "ci_backend_role_arn_must_be_a_role_arn" {
  command = plan

  variables {
    ci_backend_read_role_arns = ["arn:aws:s3:::fnx-terraform-state"]
  }

  expect_failures = [var.ci_backend_read_role_arns]
}
