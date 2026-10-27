locals {
  enabled                       = module.this.enabled
  organization_features_enabled = length(var.organization_enabled_features) > 0

  # Ensure iam.amazonaws.com is in service access principals when IAM features are enabled
  iam_service_principal = local.organization_features_enabled ? ["iam.amazonaws.com"] : []
  aws_service_access_principals = distinct(concat(
    var.aws_service_access_principals,
    local.iam_service_principal
  ))
}

resource "aws_organizations_organization" "this" {
  count = local.enabled ? 1 : 0

  aws_service_access_principals = local.aws_service_access_principals
  enabled_policy_types          = var.enabled_policy_types
  feature_set                   = var.feature_set
}

# Centralized root access features
# See: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_root-enable-root-access.html
resource "aws_iam_organizations_features" "this" {
  count = local.enabled && local.organization_features_enabled ? 1 : 0

  enabled_features = var.organization_enabled_features

  depends_on = [aws_organizations_organization.this]
}
