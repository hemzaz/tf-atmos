# Organizations resource-based delegation policy for Security Hub.
#
# This grants the delegated administrator account permissions to manage Security Hub policies
# via Organizations APIs. The policy must include ALL 8 statements that AWS expects, including the
# SecurityServicesDelegating* statements with specific resource ARNs scoped to the organization.
#
# See: https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-v2-policy-statement.html
#
# IMPORTANT: aws_organizations_resource_policy is an organization-wide singleton. Only one can exist
# per organization. If another service (e.g., AWS Backup, Inspector) already manages an Organizations
# resource policy, set `organizations_resource_policy_enabled = false` and combine the statements
# into a single policy managed elsewhere.

locals {
  create_org_resource_policy = local.create_org_delegation && var.organizations_resource_policy_enabled

  # Common values used in the delegation policy
  partition                 = local.enabled ? data.aws_partition.this[0].partition : ""
  org_id                    = local.create_org_resource_policy ? data.aws_organizations_organization.this[0].id : ""
  delegated_admin_principal = "arn:${local.partition}:iam::${local.org_delegated_administrator_account_id}:root"
  org_resource_arn_prefix   = "arn:${local.partition}:organizations::${local.org_management_account_id}"

  # Organization resource ARNs for the delegation policy (scoped to org ID)
  org_scoped_resource_arns = [
    "${local.org_resource_arn_prefix}:root/${local.org_id}/*",
    "${local.org_resource_arn_prefix}:ou/${local.org_id}/*",
    "${local.org_resource_arn_prefix}:account/${local.org_id}/*",
    "${local.org_resource_arn_prefix}:policy/${local.org_id}/securityhub_policy/*",
    "${local.org_resource_arn_prefix}:policy/${local.org_id}/inspector_policy/*",
  ]
}

data "aws_organizations_organization" "this" {
  count = local.create_org_resource_policy ? 1 : 0
}

resource "aws_organizations_resource_policy" "security_hub" {
  count = local.create_org_resource_policy ? 1 : 0

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DelegatingNecessaryDescribeListActions"
        Effect    = "Allow"
        Principal = { AWS = local.delegated_admin_principal }
        Action = [
          "organizations:DescribeOrganization",
          "organizations:DescribeOrganizationalUnit",
          "organizations:DescribeAccount",
          "organizations:DescribePolicy",
          "organizations:DescribeEffectivePolicy",
          "organizations:DescribeResourcePolicy",
          "organizations:ListRoots",
          "organizations:ListOrganizationalUnitsForParent",
          "organizations:ListParents",
          "organizations:ListChildren",
          "organizations:ListAccounts",
          "organizations:ListAccountsForParent",
          "organizations:ListPolicies",
          "organizations:ListPoliciesForTarget",
          "organizations:ListTargetsForPolicy",
          "organizations:ListTagsForResource",
          "organizations:ListDelegatedAdministrators",
          "organizations:ListAWSServiceAccessForOrganization",
        ]
        Resource = "*"
      },
      {
        Sid       = "DelegatingSecurityHubPolicyActions"
        Effect    = "Allow"
        Principal = { AWS = local.delegated_admin_principal }
        Action = [
          "organizations:CreatePolicy",
          "organizations:UpdatePolicy",
          "organizations:DeletePolicy",
          "organizations:AttachPolicy",
          "organizations:DetachPolicy",
          "organizations:EnablePolicyType",
          "organizations:DisablePolicyType",
        ]
        Resource  = "*"
        Condition = { StringLikeIfExists = { "organizations:PolicyType" = ["SECURITYHUB_POLICY"] } }
      },
      {
        Sid       = "DelegatingSecurityHubPolicyTagging"
        Effect    = "Allow"
        Principal = { AWS = local.delegated_admin_principal }
        Action    = ["organizations:TagResource", "organizations:UntagResource", "organizations:ListTagsForResource"]
        Resource  = "*"
        Condition = { StringLikeIfExists = { "organizations:PolicyType" = ["SECURITYHUB_POLICY"] } }
      },
      {
        Sid       = "SecurityServicesDelegatingOrgReadActions"
        Effect    = "Allow"
        Principal = { AWS = local.delegated_admin_principal }
        Action    = "organizations:ListRoots"
        Resource  = "*"
      },
      {
        Sid       = "SecurityServicesDelegatingNecessaryOrgManagementActions"
        Effect    = "Allow"
        Principal = { AWS = local.delegated_admin_principal }
        Action = [
          "organizations:DescribeOrganization",
          "organizations:DescribeOrganizationalUnit",
          "organizations:DescribeAccount",
          "organizations:ListRoots",
          "organizations:ListOrganizationalUnitsForParent",
          "organizations:ListParents",
          "organizations:ListChildren",
          "organizations:ListAccounts",
          "organizations:ListAccountsForParent",
          "organizations:ListTagsForResource",
          "organizations:ListDelegatedAdministrators",
          "organizations:ListHandshakesForAccount",
        ]
        Resource = concat(
          local.org_scoped_resource_arns,
          ["${local.org_resource_arn_prefix}:organization/${local.org_id}"],
        )
      },
      {
        Sid       = "SecurityServicesDelegatingPolicyDescribeActions"
        Effect    = "Allow"
        Principal = { AWS = local.delegated_admin_principal }
        Action = [
          "organizations:DescribePolicy",
          "organizations:DescribeEffectivePolicy",
          "organizations:ListPolicies",
          "organizations:ListPoliciesForTarget",
          "organizations:ListTargetsForPolicy",
        ]
        Resource = local.org_scoped_resource_arns
      },
      {
        Sid       = "SecurityServicesDelegatingPolicyMutationActions"
        Effect    = "Allow"
        Principal = { AWS = local.delegated_admin_principal }
        Action = [
          "organizations:CreatePolicy",
          "organizations:UpdatePolicy",
          "organizations:DeletePolicy",
          "organizations:AttachPolicy",
          "organizations:DetachPolicy",
          "organizations:EnablePolicyType",
          "organizations:DisablePolicyType",
        ]
        Resource = local.org_scoped_resource_arns
      },
      {
        Sid       = "SecurityServicesDelegatingPolicyTagActions"
        Effect    = "Allow"
        Principal = { AWS = local.delegated_admin_principal }
        Action    = ["organizations:TagResource", "organizations:UntagResource"]
        Resource = [
          "${local.org_resource_arn_prefix}:policy/${local.org_id}/securityhub_policy/*",
          "${local.org_resource_arn_prefix}:policy/${local.org_id}/inspector_policy/*",
        ]
      },
    ]
  })
}
