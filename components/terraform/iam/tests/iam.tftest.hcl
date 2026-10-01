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

override_data {
  target = data.aws_partition.current
  values = {
    partition = "aws"
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
    github_oidc_enabled                = true
    github_oidc_repository             = "hemzaz/tf-atmos"
    github_oidc_provider_arn           = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    ci_role_name_prefix                = "test-ci"
    ci_apply_role_enabled              = true
    ci_apply_role_trusted_github_repos = ["hemzaz/tf-atmos:master"]
    ci_apply_policy_arns               = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
    ci_apply_kms_key_aliases           = ["alias/production-main"]
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
    github_oidc_enabled                = true
    github_oidc_repository             = "hemzaz/tf-atmos"
    github_oidc_provider_arn           = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    ci_role_name_prefix                = "test-ci"
    ci_apply_role_enabled              = true
    ci_apply_role_trusted_github_repos = ["hemzaz/tf-atmos:master"]
    ci_apply_policy_arns               = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
  }

  assert {
    condition     = length(aws_iam_role_policy.ci_apply_kms) == 0
    error_message = "ci_apply_kms_key_aliases defaults to null, so no policy should be created without it."
  }
}

# State access: the CI roles reach the single state backend (backend/main in
# fnx-core-root) only through its stage-split access roles -- prod's plan role
# may assume only the prod READ-only role, prod's apply role only the prod
# WRITE role -- and hold no S3/KMS grant on the state bucket themselves (so no
# lock-object writes from plans either). The values are prod's security.yaml.
run "ci_state_access_is_sts_assume_role_on_the_stage_backend_roles_only" {
  command = plan

  variables {
    github_oidc_enabled                = true
    github_oidc_repository             = "hemzaz/tf-atmos"
    github_oidc_provider_arn           = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    ci_role_name_prefix                = "test-ci"
    ci_apply_role_enabled              = true
    ci_apply_role_trusted_github_repos = ["hemzaz/tf-atmos:master"]
    ci_apply_policy_arns               = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
    ci_backend_read_role_arns          = ["arn:aws:iam::111111111111:role/fnx-terraform-backend-prod-read-role"]
    ci_backend_write_role_arn          = "arn:aws:iam::111111111111:role/fnx-terraform-backend-prod-role"
  }

  assert {
    condition = (
      length(jsondecode(aws_iam_role_policy.ci_plan_state[0].policy).Statement) == 1
      && jsondecode(aws_iam_role_policy.ci_plan_state[0].policy).Statement[0].Action == "sts:AssumeRole"
      && jsondecode(aws_iam_role_policy.ci_plan_state[0].policy).Statement[0].Resource == "arn:aws:iam::111111111111:role/fnx-terraform-backend-prod-read-role"
    )
    error_message = "The prod plan role's only state grant is sts:AssumeRole on the prod read-only role: no non-prod read role, no s3:PutObject/DeleteObject (lock files), no KMS."
  }

  assert {
    condition = (
      length(jsondecode(aws_iam_role_policy.ci_apply_state[0].policy).Statement) == 1
      && jsondecode(aws_iam_role_policy.ci_apply_state[0].policy).Statement[0].Action == "sts:AssumeRole"
      && jsondecode(aws_iam_role_policy.ci_apply_state[0].policy).Statement[0].Resource == "arn:aws:iam::111111111111:role/fnx-terraform-backend-prod-role"
    )
    error_message = "The prod apply role's only state grant is sts:AssumeRole on the prod write role (never the non-prod or core one)."
  }
}

# Apply-role trust: Cloud Posse's branch-pinned trusted_github_repos
# (github-assume-role-policy.mixin.tf). "<org>/<repo>:<branch>" becomes exactly
# one sub, repo:<org>/<repo>:ref:refs/heads/<branch>, matched with StringEquals.
run "ci_apply_role_trusts_only_the_pinned_branch" {
  command = plan

  variables {
    github_oidc_enabled                = true
    github_oidc_repository             = "hemzaz/tf-atmos"
    github_oidc_provider_arn           = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    ci_role_name_prefix                = "test-ci"
    ci_apply_role_enabled              = true
    ci_apply_role_trusted_github_repos = ["hemzaz/tf-atmos:master"]
    ci_apply_policy_arns               = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  }

  assert {
    condition = (
      length(jsondecode(aws_iam_role.ci_apply[0].assume_role_policy).Statement) == 1
      && jsondecode(aws_iam_role.ci_apply[0].assume_role_policy).Statement[0].Action == "sts:AssumeRoleWithWebIdentity"
      && jsondecode(aws_iam_role.ci_apply[0].assume_role_policy).Statement[0].Principal.Federated == "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
      && keys(jsondecode(aws_iam_role.ci_apply[0].assume_role_policy).Statement[0].Condition) == ["StringEquals"]
      && jsondecode(aws_iam_role.ci_apply[0].assume_role_policy).Statement[0].Condition.StringEquals == {
        "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        "token.actions.githubusercontent.com:sub" = "repo:hemzaz/tf-atmos:ref:refs/heads/master"
      }
    )
    error_message = "The apply role must trust exactly sub = repo:hemzaz/tf-atmos:ref:refs/heads/master and aud = sts.amazonaws.com (StringEquals), nothing else."
  }
}

run "ci_apply_role_rejects_pull_request_subject" {
  command = plan

  variables {
    ci_apply_role_trusted_github_repos = ["hemzaz/tf-atmos:pull_request"]
  }

  expect_failures = [var.ci_apply_role_trusted_github_repos]
}

run "ci_apply_role_rejects_environment_subject" {
  command = plan

  variables {
    ci_apply_role_trusted_github_repos = ["hemzaz/tf-atmos:environment:fnx-prod-production"]
  }

  expect_failures = [var.ci_apply_role_trusted_github_repos]
}

run "ci_apply_role_rejects_wildcards" {
  command = plan

  variables {
    ci_apply_role_trusted_github_repos = ["hemzaz/tf-atmos:*", "hemzaz/*:master", "hemzaz/tf-atmos:release/*"]
  }

  expect_failures = [var.ci_apply_role_trusted_github_repos]
}

run "ci_apply_role_rejects_a_repo_without_a_pinned_branch" {
  command = plan

  variables {
    # Upstream would render repo:hemzaz/tf-atmos:* for this
    ci_apply_role_trusted_github_repos = ["hemzaz/tf-atmos"]
  }

  expect_failures = [var.ci_apply_role_trusted_github_repos]
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

# Lambda package uploader (lambda-uploader.tf): an application repo's CI
# uploads zips to this stage's s3/lambda-artifacts bucket, nothing else. The
# bucket is named by the s3 component's convention, <Environment>-lambda-
# artifacts-<account id>, because iam/ci applies before kms and storage.
run "lambda_uploader_absent_without_trusted_repos" {
  command = plan

  variables {
    github_oidc_enabled           = true
    github_oidc_repository        = "hemzaz/tf-atmos"
    github_oidc_provider_arn      = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    ci_role_name_prefix           = "test-ci"
    lambda_uploader_kms_key_alias = "alias/testenv-01-main"
    tags                          = { Environment = "testenv-01" }
  }

  assert {
    condition     = length(aws_iam_role.lambda_uploader) == 0 && length(aws_iam_role_policy.lambda_uploader) == 0
    error_message = "lambda_uploader_trusted_github_repos defaults to [], so no uploader role or policy may be created."
  }

  assert {
    condition     = output.lambda_uploader_role_arn == null && output.lambda_artifacts_bucket_name == null
    error_message = "The uploader outputs must be null when no role is created."
  }
}

run "lambda_uploader_trusts_only_the_pinned_app_branch" {
  command = plan

  variables {
    github_oidc_enabled                  = true
    github_oidc_repository               = "hemzaz/tf-atmos"
    github_oidc_provider_arn             = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    ci_role_name_prefix                  = "fnx-dev-testenv-01-ci"
    lambda_uploader_trusted_github_repos = ["hemzaz/data-app:main"]
    lambda_uploader_kms_key_alias        = "alias/testenv-01-main"
    tags                                 = { Environment = "testenv-01" }
  }

  assert {
    condition     = aws_iam_role.lambda_uploader[0].name == "fnx-dev-testenv-01-ci-lambda-uploader"
    error_message = "The uploader role is <ci_role_name_prefix>-lambda-uploader."
  }

  assert {
    condition = (
      length(jsondecode(aws_iam_role.lambda_uploader[0].assume_role_policy).Statement) == 1
      && jsondecode(aws_iam_role.lambda_uploader[0].assume_role_policy).Statement[0].Action == "sts:AssumeRoleWithWebIdentity"
      && jsondecode(aws_iam_role.lambda_uploader[0].assume_role_policy).Statement[0].Principal.Federated == "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
      && keys(jsondecode(aws_iam_role.lambda_uploader[0].assume_role_policy).Statement[0].Condition) == ["StringEquals"]
      && jsondecode(aws_iam_role.lambda_uploader[0].assume_role_policy).Statement[0].Condition.StringEquals == {
        "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        "token.actions.githubusercontent.com:sub" = "repo:hemzaz/data-app:ref:refs/heads/main"
      }
    )
    error_message = "The uploader role must trust exactly sub = repo:hemzaz/data-app:ref:refs/heads/main and aud = sts.amazonaws.com (StringEquals), nothing else."
  }
}

run "lambda_uploader_writes_only_the_stage_bucket" {
  command = plan

  variables {
    github_oidc_enabled                  = true
    github_oidc_repository               = "hemzaz/tf-atmos"
    github_oidc_provider_arn             = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    ci_role_name_prefix                  = "test-ci"
    lambda_uploader_trusted_github_repos = ["hemzaz/data-app:main"]
    lambda_uploader_kms_key_alias        = "alias/testenv-01-main"
    tags                                 = { Environment = "testenv-01" }
  }

  assert {
    condition     = output.lambda_artifacts_bucket_name == "testenv-01-lambda-artifacts-123456789012"
    error_message = "The bucket must follow the s3 component's convention <Environment>-lambda-artifacts-<account id> (s3/lambda-artifacts)."
  }

  # Statement order is the document's: put, get, list, KMS. A single-element
  # list serializes as a bare string.
  assert {
    condition = (
      length(jsondecode(aws_iam_role_policy.lambda_uploader[0].policy).Statement) == 4
      && jsondecode(aws_iam_role_policy.lambda_uploader[0].policy).Statement[0].Action == "s3:PutObject"
      && jsondecode(aws_iam_role_policy.lambda_uploader[0].policy).Statement[0].Resource == "arn:aws:s3:::testenv-01-lambda-artifacts-123456789012/*"
      && jsondecode(aws_iam_role_policy.lambda_uploader[0].policy).Statement[1].Action == "s3:GetObject"
      && jsondecode(aws_iam_role_policy.lambda_uploader[0].policy).Statement[1].Resource == "arn:aws:s3:::testenv-01-lambda-artifacts-123456789012/*"
      && jsondecode(aws_iam_role_policy.lambda_uploader[0].policy).Statement[2].Action == "s3:ListBucket"
      && jsondecode(aws_iam_role_policy.lambda_uploader[0].policy).Statement[2].Resource == "arn:aws:s3:::testenv-01-lambda-artifacts-123456789012"
    )
    error_message = "S3 access must be PutObject and GetObject on the stage's lambda-artifacts objects and ListBucket on that bucket, and nothing else."
  }

  # Release immutability: PutObject only as a conditional write
  # (If-None-Match: *), so S3 rejects an upload over an existing key with 412.
  assert {
    condition = (
      keys(jsondecode(aws_iam_role_policy.lambda_uploader[0].policy).Statement[0].Condition) == ["Null"]
      && jsondecode(aws_iam_role_policy.lambda_uploader[0].policy).Statement[0].Condition["Null"] == { "s3:if-none-match" = "false" }
      && !can(jsondecode(aws_iam_role_policy.lambda_uploader[0].policy).Statement[1].Condition)
    )
    error_message = "s3:PutObject must require s3:if-none-match (Null = false), so a released key can never be overwritten; GetObject stays unconditional."
  }

  assert {
    condition = (
      toset(jsondecode(aws_iam_role_policy.lambda_uploader[0].policy).Statement[3].Action) == toset(["kms:GenerateDataKey", "kms:Encrypt", "kms:Decrypt"])
      && jsondecode(aws_iam_role_policy.lambda_uploader[0].policy).Statement[3].Resource == "*"
      && jsondecode(aws_iam_role_policy.lambda_uploader[0].policy).Statement[3].Condition["ForAnyValue:StringEquals"]["kms:ResourceAliases"] == "alias/testenv-01-main"
      && jsondecode(aws_iam_role_policy.lambda_uploader[0].policy).Statement[3].Condition["StringEquals"]["kms:ViaService"] == "s3.eu-west-2.amazonaws.com"
    )
    error_message = "KMS access must be GenerateDataKey/Encrypt/Decrypt on the kms/main alias only, and only via s3.<region>.amazonaws.com."
  }
}

# One run per wildcard position, so each is proven rejected on its own.
run "lambda_uploader_rejects_a_wildcard_org" {
  command = plan

  variables {
    github_oidc_enabled                  = true
    github_oidc_repository               = "hemzaz/tf-atmos"
    github_oidc_provider_arn             = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    ci_role_name_prefix                  = "test-ci"
    lambda_uploader_trusted_github_repos = ["*/data-app:main"]
    lambda_uploader_kms_key_alias        = "alias/testenv-01-main"
  }

  expect_failures = [var.lambda_uploader_trusted_github_repos]
}

run "lambda_uploader_rejects_a_wildcard_repo" {
  command = plan

  variables {
    github_oidc_enabled                  = true
    github_oidc_repository               = "hemzaz/tf-atmos"
    github_oidc_provider_arn             = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    ci_role_name_prefix                  = "test-ci"
    lambda_uploader_trusted_github_repos = ["hemzaz/*:main"]
    lambda_uploader_kms_key_alias        = "alias/testenv-01-main"
  }

  expect_failures = [var.lambda_uploader_trusted_github_repos]
}

run "lambda_uploader_rejects_a_wildcard_branch" {
  command = plan

  variables {
    github_oidc_enabled                  = true
    github_oidc_repository               = "hemzaz/tf-atmos"
    github_oidc_provider_arn             = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    ci_role_name_prefix                  = "test-ci"
    lambda_uploader_trusted_github_repos = ["hemzaz/data-app:*"]
    lambda_uploader_kms_key_alias        = "alias/testenv-01-main"
  }

  expect_failures = [var.lambda_uploader_trusted_github_repos]
}

run "lambda_uploader_rejects_pull_request_subject" {
  command = plan

  variables {
    github_oidc_enabled                  = true
    github_oidc_repository               = "hemzaz/tf-atmos"
    github_oidc_provider_arn             = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    ci_role_name_prefix                  = "test-ci"
    lambda_uploader_trusted_github_repos = ["hemzaz/data-app:pull_request"]
    lambda_uploader_kms_key_alias        = "alias/testenv-01-main"
  }

  expect_failures = [var.lambda_uploader_trusted_github_repos]
}

run "lambda_uploader_rejects_a_repo_without_a_pinned_branch" {
  command = plan

  variables {
    github_oidc_enabled                  = true
    github_oidc_repository               = "hemzaz/tf-atmos"
    github_oidc_provider_arn             = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    ci_role_name_prefix                  = "test-ci"
    lambda_uploader_trusted_github_repos = ["hemzaz/data-app"]
    lambda_uploader_kms_key_alias        = "alias/testenv-01-main"
  }

  expect_failures = [var.lambda_uploader_trusted_github_repos]
}

run "lambda_uploader_requires_the_kms_alias" {
  command = plan

  variables {
    github_oidc_enabled                  = true
    github_oidc_repository               = "hemzaz/tf-atmos"
    github_oidc_provider_arn             = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    ci_role_name_prefix                  = "test-ci"
    lambda_uploader_trusted_github_repos = ["hemzaz/data-app:main"]
  }

  expect_failures = [var.lambda_uploader_trusted_github_repos]
}

run "lambda_uploader_requires_github_oidc" {
  command = plan

  variables {
    lambda_uploader_trusted_github_repos = ["hemzaz/data-app:main"]
    lambda_uploader_kms_key_alias        = "alias/testenv-01-main"
  }

  expect_failures = [var.lambda_uploader_trusted_github_repos]
}
