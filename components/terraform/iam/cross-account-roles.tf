data "aws_caller_identity" "current" {}

locals {
  # Name prefix that scopes the resources the cross-account role may manage
  resource_name_prefix = coalesce(var.resource_name_prefix, var.environment)

  trusts_other_accounts = anytrue([
    for id in var.trusted_account_ids : id != data.aws_caller_identity.current.account_id
  ])
  has_trust_condition = var.trusted_principal_org_id != null || var.external_id != null || var.require_mfa
}

data "aws_iam_policy_document" "cross_account_assume_role" {
  statement {
    sid     = "TrustedAccountsAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [for id in var.trusted_account_ids : "arn:aws:iam::${id}:root"]
    }

    dynamic "condition" {
      for_each = var.trusted_principal_org_id != null ? [var.trusted_principal_org_id] : []
      content {
        test     = "StringEquals"
        variable = "aws:PrincipalOrgID"
        values   = [condition.value]
      }
    }

    dynamic "condition" {
      for_each = var.external_id != null ? [var.external_id] : []
      content {
        test     = "StringEquals"
        variable = "sts:ExternalId"
        values   = [condition.value]
      }
    }

    dynamic "condition" {
      for_each = var.require_mfa ? [1] : []
      content {
        test     = "Bool"
        variable = "aws:MultiFactorAuthPresent"
        values   = ["true"]
      }
    }
  }
}

resource "aws_iam_role" "cross_account_role" {
  name               = var.cross_account_role_name
  assume_role_policy = data.aws_iam_policy_document.cross_account_assume_role.json

  lifecycle {
    precondition {
      condition     = !local.trusts_other_accounts || local.has_trust_condition
      error_message = "Trusting another account requires at least one of trusted_principal_org_id, external_id or require_mfa."
    }
  }
}

data "aws_iam_policy_document" "cross_account_policy" {
  statement {
    sid    = "ReadOnlyDiscovery"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListRoles",
      "iam:ListPolicies",
      "iam:ListAttachedRolePolicies",
      "s3:ListAllMyBuckets",
      "s3:GetBucketLocation",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ManagePrefixedBuckets"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketPolicy",
      "s3:PutBucketPolicy",
    ]
    resources = ["arn:aws:s3:::${local.resource_name_prefix}-*"]
  }

  # Guard rails that hold even if other policies are attached to the role
  statement {
    sid    = "DenyIamPrivilegeEscalation"
    effect = "Deny"
    actions = [
      "iam:CreateUser",
      "iam:CreateAccessKey",
      "iam:CreateLoginProfile",
      "iam:CreatePolicy",
      "iam:CreatePolicyVersion",
      "iam:AttachUserPolicy",
      "iam:AttachGroupPolicy",
      "iam:AttachRolePolicy",
      "iam:PutUserPolicy",
      "iam:PutGroupPolicy",
      "iam:PutRolePolicy",
      "iam:AddUserToGroup",
      "iam:UpdateAssumeRolePolicy",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "DenyStateBucketPolicyChanges"
    effect    = "Deny"
    actions   = ["s3:PutBucketPolicy", "s3:DeleteBucketPolicy"]
    resources = concat(["arn:aws:s3:::*terraform-state*"], [for name in var.state_bucket_names : "arn:aws:s3:::${name}"])
  }
}

resource "aws_iam_policy" "cross_account_policy" {
  name        = var.policy_name
  path        = "/"
  description = "Cross-account access policy"

  policy = data.aws_iam_policy_document.cross_account_policy.json
}

resource "aws_iam_role_policy_attachment" "cross_account_policy_attachment" {
  role       = aws_iam_role.cross_account_role.name
  policy_arn = aws_iam_policy.cross_account_policy.arn
}
