# GitHub Actions OIDC CI roles. Everything here is inert unless
# github_oidc_enabled is true, so iam/main instances are unaffected.
#
# Two roles, because .github/workflows model two different trust surfaces:
#   plan  - assumed by terraform-ci.yml (pull_request, i.e. PR-controlled code),
#           drift-detection.yml and disaster-recovery.yml (default branch).
#           Read-only; its ARN is the repo variable AWS_PLAN_ROLE_ARN.
#   apply - assumed by terraform-cd.yml only through a protected GitHub
#           Environment named after the Atmos stack. Its ARN is that
#           environment's AWS_ROLE_ARN.
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

  github_apply_subjects = [
    for environment in var.ci_apply_role_environments :
    "repo:${local.github_repository}:environment:${environment}"
  ]

  create_ci_apply_role = var.github_oidc_enabled && var.ci_apply_role_enabled
  ci_state_policy      = var.github_oidc_enabled && var.ci_state_bucket_name != null
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

data "aws_iam_policy_document" "ci_plan_state" {
  count = local.ci_state_policy ? 1 : 0

  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.ci_state_bucket_name}"]
  }

  statement {
    sid       = "ReadState"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${var.ci_state_bucket_name}/*"]
  }

  # The S3 backend uses use_lockfile (stacks/orgs/fnx/_defaults.yaml), so even a
  # plan writes and removes a <key>.tflock object. Scoped to that suffix so the
  # plan role still cannot overwrite a state file.
  statement {
    sid       = "WriteStateLock"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.ci_state_bucket_name}/*.tflock"]
  }

  dynamic "statement" {
    for_each = var.ci_state_kms_key_arn != null ? [var.ci_state_kms_key_arn] : []
    content {
      sid    = "StateKms"
      effect = "Allow"
      # GenerateDataKey is needed to write the lock object into the SSE-KMS bucket.
      actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
      resources = [statement.value]
    }
  }
}

resource "aws_iam_role_policy" "ci_plan_state" {
  count = local.ci_state_policy ? 1 : 0

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

    # Environment subjects only. A pull_request or bare ref subject here would
    # hand deploy credentials to PR-controlled code.
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
  description          = "GitHub Actions OIDC role for terraform apply (protected environments only)"
  assume_role_policy   = data.aws_iam_policy_document.ci_apply_assume_role[0].json
  max_session_duration = var.ci_role_max_session_duration
}

resource "aws_iam_role_policy_attachment" "ci_apply_managed" {
  for_each = local.create_ci_apply_role ? toset(var.ci_apply_policy_arns) : toset([])

  role       = aws_iam_role.ci_apply[0].name
  policy_arn = each.value
}

data "aws_iam_policy_document" "ci_apply_state" {
  count = local.create_ci_apply_role && local.ci_state_policy ? 1 : 0

  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.ci_state_bucket_name}"]
  }

  statement {
    sid       = "ReadWriteState"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.ci_state_bucket_name}/*"]
  }

  dynamic "statement" {
    for_each = var.ci_state_kms_key_arn != null ? [var.ci_state_kms_key_arn] : []
    content {
      sid       = "StateKms"
      effect    = "Allow"
      actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
      resources = [statement.value]
    }
  }
}

resource "aws_iam_role_policy" "ci_apply_state" {
  count = local.create_ci_apply_role && local.ci_state_policy ? 1 : 0

  name   = "terraform-state"
  role   = aws_iam_role.ci_apply[0].id
  policy = data.aws_iam_policy_document.ci_apply_state[0].json
}
