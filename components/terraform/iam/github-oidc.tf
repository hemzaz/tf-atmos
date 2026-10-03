# GitHub Actions OIDC CI roles. Everything here is inert unless
# github_oidc_enabled is true, so iam/main instances are unaffected.
#
# Two roles, because .github/workflows model two different trust surfaces:
#   plan  - assumed by terraform-ci.yml (pull_request, i.e. PR-controlled code;
#           prod's instance trusts the default branch only - see
#           ci_plan_role_subjects in its security.yaml),
#           drift-detection.yml and disaster-recovery.yml (default branch).
#           Read-only. Each workflow derives this stack's ARN from its iam/ci
#           config (workflows/scripts/common/ci-apply-role-arn.py --kind plan);
#           repo variable AWS_PLAN_ROLE_ARN only switches the AWS jobs on.
#   apply - assumed by terraform-cd.yml, which runs only on the default branch
#           and uses no GitHub Environment, so its token's sub is
#           repo:<org>/<repo>:ref:refs/heads/<branch> - the only subject this
#           role trusts (Cloud Posse's branch-pinned trusted_github_repos).
#           terraform-cd.yml derives its ARN from this stack's iam/ci config.
#           There is no manual approval: every default-branch merge applies.
# Keeping them separate is what stops a pull request from running deploy
# credentials; terraform-ci.yml calls that out explicitly.

locals {
  # Empty only while the CI roles are off: the variable validations require a
  # repository whenever github_oidc_enabled is true.
  github_repository = var.github_oidc_repository == null ? "" : var.github_oidc_repository

  github_oidc_provider_arn = var.github_oidc_create_provider ? one(aws_iam_openid_connect_provider.github[*].arn) : var.github_oidc_provider_arn

  # Exact subject claims. Anything wildcarded here would let another repository
  # assume the role, so the defaults spell out the three workflow triggers and
  # ci_plan_role_subjects is validated against wildcards.
  github_plan_subjects = var.ci_plan_role_subjects != null ? var.ci_plan_role_subjects : [
    "repo:${local.github_repository}:pull_request",
    "repo:${local.github_repository}:ref:refs/heads/${var.github_oidc_default_branch}",
  ]

  # Cloud Posse's trusted_github_repos -> sub mapping (github-assume-role-policy.mixin.tf):
  # "<org>/<repo>:<branch>" -> "repo:<org>/<repo>:ref:refs/heads/<branch>". The
  # variable validation requires the branch, so upstream's "repo:<org>/<repo>:*"
  # form (which would admit pull_request and environment subjects) never arises.
  github_apply_subjects = sort(distinct([
    for repo in var.ci_apply_role_trusted_github_repos :
    format("repo:%s:ref:refs/heads/%s", split(":", repo)[0], split(":", repo)[1])
  ]))

  create_ci_apply_role  = var.github_oidc_enabled && var.ci_apply_role_enabled
  ci_plan_state_policy  = var.github_oidc_enabled && length(var.ci_backend_read_role_arns) > 0
  ci_apply_state_policy = local.create_ci_apply_role && var.ci_backend_write_role_arn != null
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.github_oidc_enabled && var.github_oidc_create_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

# ---------------------------------------------------------------------------
# Plan role (read-only)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ci_plan_assume_role" {
  count = var.github_oidc_enabled ? 1 : 0

  statement {
    sid     = "GitHubActionsPlan"
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

    # StringEquals, never StringLike: a wildcard sub is the GitHub OIDC
    # misconfiguration that lets any repository assume this role.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.github_plan_subjects
    }
  }
}

resource "aws_iam_role" "ci_plan" {
  count = var.github_oidc_enabled ? 1 : 0

  name                 = "${var.ci_role_name_prefix}-plan"
  description          = "GitHub Actions OIDC role for terraform plan (read-only)"
  assume_role_policy   = data.aws_iam_policy_document.ci_plan_assume_role[0].json
  max_session_duration = var.ci_role_max_session_duration
}

resource "aws_iam_role_policy_attachment" "ci_plan_managed" {
  for_each = var.github_oidc_enabled ? toset(var.ci_plan_policy_arns) : toset([])

  role       = aws_iam_role.ci_plan[0].name
  policy_arn = each.value
}

# Terraform state lives in the management account's single backend
# (components/terraform/backend, instance backend/main in stack fnx-core-root).
# CI reaches it only by assuming that backend's access roles, each split by
# stage: the plan role its stage's READ-only one (CI plans run with
# -lock=false, so they write no .tflock), the apply role its stage's WRITE
# one. No S3 or KMS grant on the state bucket itself.
data "aws_iam_policy_document" "ci_plan_state" {
  count = local.ci_plan_state_policy ? 1 : 0

  statement {
    sid       = "AssumeStateReadRoles"
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = var.ci_backend_read_role_arns
  }
}

resource "aws_iam_role_policy" "ci_plan_state" {
  count = local.ci_plan_state_policy ? 1 : 0

  name   = "terraform-state"
  role   = aws_iam_role.ci_plan[0].id
  policy = data.aws_iam_policy_document.ci_plan_state[0].json
}

# ---------------------------------------------------------------------------
# Apply role (deploy)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ci_apply_assume_role" {
  count = local.create_ci_apply_role ? 1 : 0

  statement {
    sid     = "GitHubActionsApply"
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

    # Branch-pinned ref subjects only (Cloud Posse model). A pull_request,
    # environment or wildcard subject here would hand deploy credentials to
    # PR-controlled code; the variable validation rejects all three.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.github_apply_subjects
    }
  }
}

resource "aws_iam_role" "ci_apply" {
  count = local.create_ci_apply_role ? 1 : 0

  name                 = "${var.ci_role_name_prefix}-apply"
  description          = "GitHub Actions OIDC role for terraform apply (pinned branch only)"
  assume_role_policy   = data.aws_iam_policy_document.ci_apply_assume_role[0].json
  max_session_duration = var.ci_role_max_session_duration
}

resource "aws_iam_role_policy_attachment" "ci_apply_managed" {
  for_each = local.create_ci_apply_role ? toset(var.ci_apply_policy_arns) : toset([])

  role       = aws_iam_role.ci_apply[0].name
  policy_arn = each.value
}

data "aws_iam_policy_document" "ci_apply_state" {
  count = local.ci_apply_state_policy ? 1 : 0

  statement {
    sid       = "AssumeStateWriteRole"
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [var.ci_backend_write_role_arn]
  }
}

resource "aws_iam_role_policy" "ci_apply_state" {
  count = local.ci_apply_state_policy ? 1 : 0

  name   = "terraform-state"
  role   = aws_iam_role.ci_apply[0].id
  policy = data.aws_iam_policy_document.ci_apply_state[0].json
}

# Least-privilege access to customer-managed key(s) this role deploys
# resources against (kms/main), scoped by alias rather than key ARN -- the
# Cloud Posse pattern of a consumer's own IAM policy rather than a kms
# key-policy key_users entry (see ../kms/README.md; cloudposse-terraform-
# components/aws-eks-cluster's github-actions-iam-policy.mixin.tf
# AllowKMSAccess statement is prior art for a CI role holding its own scoped
# KMS IAM statement, not for the specific EKS grant below). A key ARN is
# deliberately not used: this component's iam/ci instance plans and applies
# in the layer BEFORE kms/main (workflows/deploy-full-stack.yaml), so on a
# first deploy the key does not exist yet, and a !terraform.state read of
# kms/main here would make iam depend on kms while kms/main already depends
# on iam (allow_autoscaling_ebs's service-linked role) -- a cycle
# check-deploy-layers.py rejects. AWS derives the kms:ResourceAliases
# condition key from the KMS key an operation actually acts on, regardless
# of how the request named it (key ID, key ARN, alias name or alias ARN), so
# resources = ["*"] plus that condition is still an exact-match grant.
#
# AWS requires the principal that calls eks:CreateCluster/
# UpdateClusterConfig -- not the EKS cluster's own service role -- to hold
# DescribeKey/CreateGrant/Encrypt on the key named in
# cluster_encryption_config_kms_key_id ("Encrypting Kubernetes secrets", AWS
# EKS docs); Encrypt/Decrypt/GenerateDataKey* additionally cover the other
# kms/main consumers this role deploys (secretsmanager, rds, elasticache,
# ec2). CreateGrant/ListGrants/RevokeGrant are split into their own statement
# under kms:GrantIsForAWSResource, AWS's documented pattern for grant
# management scoped to AWS-service-managed grants (used in AWS's own default
# key policies for services like EBS and RDS).
data "aws_iam_policy_document" "ci_apply_kms" {
  count = local.create_ci_apply_role && var.ci_apply_kms_key_aliases != null && length(var.ci_apply_kms_key_aliases) > 0 ? 1 : 0

  statement {
    sid    = "DeployKmsKeyUse"
    effect = "Allow"
    actions = [
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
    ]
    resources = ["*"]

    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "kms:ResourceAliases"
      values   = var.ci_apply_kms_key_aliases
    }
  }

  statement {
    sid    = "DeployKmsGrants"
    effect = "Allow"
    actions = [
      "kms:CreateGrant",
      "kms:ListGrants",
      "kms:RevokeGrant",
    ]
    resources = ["*"]

    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "kms:ResourceAliases"
      values   = var.ci_apply_kms_key_aliases
    }

    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }
}

resource "aws_iam_role_policy" "ci_apply_kms" {
  count = local.create_ci_apply_role && var.ci_apply_kms_key_aliases != null && length(var.ci_apply_kms_key_aliases) > 0 ? 1 : 0

  name   = "deploy-kms"
  role   = aws_iam_role.ci_apply[0].id
  policy = data.aws_iam_policy_document.ci_apply_kms[0].json
}
