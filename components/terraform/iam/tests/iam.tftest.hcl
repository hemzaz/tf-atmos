# House tests of the GitHub OIDC Lambda uploader role (the CI plan and apply roles are the vendored
# aws-iam-role's, tested in ../../aws-iam-role/tests/ci_roles.tftest.hcl, E6a4). The real AWS provider is used, not a mock:
# credentials are dummies and every data source that would call AWS is overridden.
# Run: terraform init -backend=false && terraform test

provider "aws" {
  region                      = "us-east-1"
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
  region = "us-east-1"
}

# Lambda package uploader (lambda-uploader.tf): an application repo's CI
# uploads zips to this stage's s3/lambda-artifacts bucket, nothing else. The
# bucket is named by the s3 component's convention, <Environment>-lambda-
# artifacts-<account id>, because iam/ci applies before kms and storage.
run "lambda_uploader_absent_without_trusted_repos" {
  command = plan

  variables {
    github_oidc_enabled           = true
    github_oidc_provider_arn      = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    ci_role_name_prefix           = "test-ci"
    lambda_uploader_kms_key_alias = "alias/ue1-main"
    tags                          = { Environment = "ue1" }
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
    github_oidc_provider_arn             = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    ci_role_name_prefix                  = "fnx-ue1-dev-ci"
    lambda_uploader_trusted_github_repos = ["hemzaz/data-app:main"]
    lambda_uploader_kms_key_alias        = "alias/ue1-main"
    tags                                 = { Environment = "ue1" }
  }

  assert {
    condition     = aws_iam_role.lambda_uploader[0].name == "fnx-ue1-dev-ci-lambda-uploader"
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
    github_oidc_provider_arn             = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    ci_role_name_prefix                  = "test-ci"
    lambda_uploader_trusted_github_repos = ["hemzaz/data-app:main"]
    lambda_uploader_kms_key_alias        = "alias/ue1-main"
    tags                                 = { Environment = "ue1" }
  }

  assert {
    condition     = output.lambda_artifacts_bucket_name == "ue1-lambda-artifacts-123456789012"
    error_message = "The bucket must follow the s3 component's convention <Environment>-lambda-artifacts-<account id> (s3/lambda-artifacts)."
  }

  # Statement order is the document's: put, get, list, KMS. A single-element
  # list serializes as a bare string.
  assert {
    condition = (
      length(jsondecode(aws_iam_role_policy.lambda_uploader[0].policy).Statement) == 4
      && jsondecode(aws_iam_role_policy.lambda_uploader[0].policy).Statement[0].Action == "s3:PutObject"
      && jsondecode(aws_iam_role_policy.lambda_uploader[0].policy).Statement[0].Resource == "arn:aws:s3:::ue1-lambda-artifacts-123456789012/*"
      && jsondecode(aws_iam_role_policy.lambda_uploader[0].policy).Statement[1].Action == "s3:GetObject"
      && jsondecode(aws_iam_role_policy.lambda_uploader[0].policy).Statement[1].Resource == "arn:aws:s3:::ue1-lambda-artifacts-123456789012/*"
      && jsondecode(aws_iam_role_policy.lambda_uploader[0].policy).Statement[2].Action == "s3:ListBucket"
      && jsondecode(aws_iam_role_policy.lambda_uploader[0].policy).Statement[2].Resource == "arn:aws:s3:::ue1-lambda-artifacts-123456789012"
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
      && jsondecode(aws_iam_role_policy.lambda_uploader[0].policy).Statement[3].Condition["ForAnyValue:StringEquals"]["kms:ResourceAliases"] == "alias/ue1-main"
      && jsondecode(aws_iam_role_policy.lambda_uploader[0].policy).Statement[3].Condition["StringEquals"]["kms:ViaService"] == "s3.us-east-1.amazonaws.com"
    )
    error_message = "KMS access must be GenerateDataKey/Encrypt/Decrypt on the kms/main alias only, and only via s3.<region>.amazonaws.com."
  }
}

# One run per wildcard position, so each is proven rejected on its own.
run "lambda_uploader_rejects_a_wildcard_org" {
  command = plan

  variables {
    github_oidc_enabled                  = true
    github_oidc_provider_arn             = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    ci_role_name_prefix                  = "test-ci"
    lambda_uploader_trusted_github_repos = ["*/data-app:main"]
    lambda_uploader_kms_key_alias        = "alias/ue1-main"
  }

  expect_failures = [var.lambda_uploader_trusted_github_repos]
}

run "lambda_uploader_rejects_a_wildcard_repo" {
  command = plan

  variables {
    github_oidc_enabled                  = true
    github_oidc_provider_arn             = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    ci_role_name_prefix                  = "test-ci"
    lambda_uploader_trusted_github_repos = ["hemzaz/*:main"]
    lambda_uploader_kms_key_alias        = "alias/ue1-main"
  }

  expect_failures = [var.lambda_uploader_trusted_github_repos]
}

run "lambda_uploader_rejects_a_wildcard_branch" {
  command = plan

  variables {
    github_oidc_enabled                  = true
    github_oidc_provider_arn             = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    ci_role_name_prefix                  = "test-ci"
    lambda_uploader_trusted_github_repos = ["hemzaz/data-app:*"]
    lambda_uploader_kms_key_alias        = "alias/ue1-main"
  }

  expect_failures = [var.lambda_uploader_trusted_github_repos]
}

run "lambda_uploader_rejects_pull_request_subject" {
  command = plan

  variables {
    github_oidc_enabled                  = true
    github_oidc_provider_arn             = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    ci_role_name_prefix                  = "test-ci"
    lambda_uploader_trusted_github_repos = ["hemzaz/data-app:pull_request"]
    lambda_uploader_kms_key_alias        = "alias/ue1-main"
  }

  expect_failures = [var.lambda_uploader_trusted_github_repos]
}

run "lambda_uploader_rejects_a_repo_without_a_pinned_branch" {
  command = plan

  variables {
    github_oidc_enabled                  = true
    github_oidc_provider_arn             = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    ci_role_name_prefix                  = "test-ci"
    lambda_uploader_trusted_github_repos = ["hemzaz/data-app"]
    lambda_uploader_kms_key_alias        = "alias/ue1-main"
  }

  expect_failures = [var.lambda_uploader_trusted_github_repos]
}

run "lambda_uploader_requires_the_kms_alias" {
  command = plan

  variables {
    github_oidc_enabled                  = true
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
    lambda_uploader_kms_key_alias        = "alias/ue1-main"
  }

  expect_failures = [var.lambda_uploader_trusted_github_repos]
}

# The account's GitHub OIDC provider is the vendored aws-github-oidc-provider's (E6a3): iam creates
# none, so an uploader without its ARN would trust nothing.
run "uploader_requires_the_provider_arn" {
  command = plan

  variables {
    github_oidc_enabled = true
    ci_role_name_prefix = "test-ci"
  }

  expect_failures = [var.github_oidc_provider_arn]
}
