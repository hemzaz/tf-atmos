# Lambda package uploader: a GitHub Actions OIDC role for an APPLICATION
# repository's CI (the Cloud Posse aws-lambda model: the app builds its zip,
# tf-atmos deploys it). It may only put packages into this stage's
# s3/lambda-artifacts bucket; it cannot touch the functions. A new upload
# deploys nothing on its own: a tf-atmos PR bumps the instance's
# settings.package_version, which changes s3_key, and terraform-cd.yml
# applies it (docs/OPERATIONS.md, "Lambda packages").
#
# Inert until lambda_uploader_trusted_github_repos names a repository, so no
# instance creates it today.
#
# The bucket is named, not read: iam/ci applies in the deploy-full-stack
# "iam" layer, before kms and storage (workflows/deploy-full-stack.yaml), so
# a !terraform.state read of s3/lambda-artifacts or kms/main would break the
# layer order. The name follows the s3 component's own convention
# (<Environment>-<name>-<account id>, components/terraform/s3/main.tf) with
# name "lambda-artifacts" (stacks/catalog/s3/lambda-artifacts.yaml), and
# workflows/scripts/common/check-lambda-packages.py fails lint when the
# stack's s3/lambda-artifacts or kms/main instance stops matching it.

locals {
  lambda_artifacts_bucket_name = "${lookup(var.tags, "Environment", "")}-lambda-artifacts-${data.aws_caller_identity.current.account_id}"
  lambda_artifacts_bucket_arn  = "arn:aws:s3:::${local.lambda_artifacts_bucket_name}"

  create_lambda_uploader_role = var.github_oidc_enabled && length(var.lambda_uploader_trusted_github_repos) > 0

  # Same mapping as the apply role's (github-oidc.tf): Cloud Posse's
  # trusted_github_repos "<org>/<repo>:<branch>" -> exact ref subject.
  lambda_uploader_subjects = sort(distinct([
    for repo in var.lambda_uploader_trusted_github_repos :
    format("repo:%s:ref:refs/heads/%s", split(":", repo)[0], split(":", repo)[1])
  ]))
}

data "aws_iam_policy_document" "lambda_uploader_assume_role" {
  count = local.create_lambda_uploader_role ? 1 : 0

  statement {
    sid     = "GitHubActionsLambdaUpload"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # StringEquals on branch-pinned subjects only, like the apply role.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.lambda_uploader_subjects
    }
  }
}

resource "aws_iam_role" "lambda_uploader" {
  count = local.create_lambda_uploader_role ? 1 : 0

  name                 = "${var.ci_role_name_prefix}-lambda-uploader"
  description          = "GitHub Actions OIDC role that uploads Lambda packages to ${local.lambda_artifacts_bucket_name}"
  assume_role_policy   = data.aws_iam_policy_document.lambda_uploader_assume_role[0].json
  max_session_duration = var.ci_role_max_session_duration

  lifecycle {
    precondition {
      condition     = length("${var.ci_role_name_prefix}-lambda-uploader") <= 64
      error_message = "The uploader role name \"<ci_role_name_prefix>-lambda-uploader\" must be at most 64 characters: shorten ci_role_name_prefix to 48 or fewer."
    }

    precondition {
      condition     = lookup(var.tags, "Environment", "") != ""
      error_message = "tags.Environment is required for the uploader role: the bucket it may write is <Environment>-lambda-artifacts-<account id>."
    }
  }
}

data "aws_iam_policy_document" "lambda_uploader" {
  count = local.create_lambda_uploader_role ? 1 : 0

  # PutObject is the upload. GetObject and ListBucket let the app CI check
  # whether a version's key already exists before uploading (without
  # ListBucket, HeadObject on a missing key returns 403, not 404), so a
  # released version is never overwritten.
  statement {
    sid       = "PutLambdaPackages"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:GetObject"]
    resources = ["${local.lambda_artifacts_bucket_arn}/*"]
  }

  statement {
    sid       = "ListLambdaPackages"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.lambda_artifacts_bucket_arn]
  }

  # The bucket is SSE-KMS with kms/main (catalog/s3/defaults.yaml). Scoped
  # like the apply role's deploy-kms policy (by alias: the key ARN does not
  # exist yet when iam/ci applies), and only through S3 in this region.
  statement {
    sid       = "LambdaPackageEncryption"
    effect    = "Allow"
    actions   = ["kms:GenerateDataKey", "kms:Encrypt", "kms:Decrypt"]
    resources = ["*"]

    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "kms:ResourceAliases"
      values   = [var.lambda_uploader_kms_key_alias]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${var.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "lambda_uploader" {
  count = local.create_lambda_uploader_role ? 1 : 0

  name   = "lambda-packages"
  role   = aws_iam_role.lambda_uploader[0].id
  policy = data.aws_iam_policy_document.lambda_uploader[0].json
}
