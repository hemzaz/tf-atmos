# cognito - Cognito user pool and app clients for API authorization
#
# Resource naming follows the repository convention:
#
#   "${var.name_prefix}-<resource>"   # name_prefix = tenant-account-environment
#
# Scanner suppressions are always inline and always carry an honest reason:
#
#   #checkov:skip=CKV_AWS_123:<honest reason>   # inside the resource block
#   #trivy:ignore:AWS-0123 <honest reason>      # immediately above the block
#
# NEVER add an entry to .checkov.baseline or .trivyignore.yaml to make a scan
# pass. Those baselines exist to burn findings down, and regenerating them to
# turn a PR green hides the finding instead of fixing it. Only write
# "False positive" when the rule genuinely does not apply to this resource -
# if the risk is real but accepted, say so and say why.

locals {
  enabled     = var.enabled
  name_prefix = var.name_prefix
}

resource "aws_cognito_user_pool" "this" {
  count = local.enabled ? 1 : 0

  name = "${local.name_prefix}-users"

  # Cognito cannot change these after creation, so editing either one replaces
  # the pool and every user in it.
  username_attributes      = var.username_attributes
  auto_verified_attributes = var.auto_verified_attributes

  deletion_protection = var.deletion_protection ? "ACTIVE" : "INACTIVE"

  password_policy {
    minimum_length                   = var.password_minimum_length
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = var.temporary_password_validity_days
  }

  mfa_configuration = var.mfa_configuration

  # software_token_mfa_configuration is only accepted when MFA is not OFF.
  dynamic "software_token_mfa_configuration" {
    for_each = var.mfa_configuration == "OFF" ? [] : [1]
    content {
      enabled = true
    }
  }

  admin_create_user_config {
    allow_admin_create_user_only = var.allow_admin_create_user_only
  }

  user_pool_add_ons {
    advanced_security_mode = var.advanced_security_mode
  }
}

resource "aws_cognito_user_pool_client" "this" {
  for_each = local.enabled ? var.clients : {}

  name         = "${local.name_prefix}-${each.key}"
  user_pool_id = aws_cognito_user_pool.this[0].id

  # A confidential client gets a secret; a public client (browser, mobile) must
  # not have one, because it cannot keep it.
  generate_secret = each.value.generate_secret

  explicit_auth_flows = each.value.explicit_auth_flows

  allowed_oauth_flows_user_pool_client = length(each.value.allowed_oauth_flows) > 0
  allowed_oauth_flows                  = each.value.allowed_oauth_flows
  allowed_oauth_scopes                 = each.value.allowed_oauth_scopes
  callback_urls                        = each.value.callback_urls
  logout_urls                          = each.value.logout_urls
  supported_identity_providers         = each.value.supported_identity_providers

  access_token_validity  = each.value.access_token_validity_minutes
  id_token_validity      = each.value.id_token_validity_minutes
  refresh_token_validity = each.value.refresh_token_validity_days

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  # Without this, an unauthenticated caller can tell a wrong password from an
  # unknown user, which enumerates the user directory.
  prevent_user_existence_errors = "ENABLED"
}

# Hosted UI / OAuth endpoints. Only created when a domain prefix is given; an
# API authorized by the pool does not need one.
resource "aws_cognito_user_pool_domain" "this" {
  count = local.enabled && var.domain_prefix != "" ? 1 : 0

  domain       = var.domain_prefix
  user_pool_id = aws_cognito_user_pool.this[0].id
}
