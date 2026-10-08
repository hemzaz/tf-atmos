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
# There is no scanner baseline: the PR gate fails on every finding that is
# not fixed or suppressed inline. Only write "False positive" when the rule
# genuinely does not apply to this resource - if the risk is real but
# accepted, say so and say why. A risk the owner has not accepted yet starts
# its reason with "TODO(owner):".

locals {
  enabled     = var.enabled
  name_prefix = var.name_prefix

  # The triggers that are set ("" counts as unset, as Cloud Posse's defaults).
  lambda_triggers = { for k, arn in var.lambda_config : k => arn if try(length(arn), 0) > 0 }
}

resource "aws_cognito_user_pool" "this" {
  count = local.enabled ? 1 : 0

  name = "${local.name_prefix}-users"

  # Cognito cannot change these after creation, so editing either one replaces
  # the pool and every user in it.
  username_attributes      = var.username_attributes
  auto_verified_attributes = var.auto_verified_attributes

  deletion_protection = var.deletion_protection ? "ACTIVE" : "INACTIVE"

  # Feature plan; PLUS is what advanced_security_mode AUDIT/ENFORCED needs
  # (validated in variables.tf).
  user_pool_tier = var.user_pool_tier

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

  # Cloud Posse aws-cognito's email_configuration. Always one block, as there:
  # COGNITO_DEFAULT with no other key is the AWS default. "" means unset.
  email_configuration {
    email_sending_account  = var.email_configuration.email_sending_account
    source_arn             = try(length(var.email_configuration.source_arn), 0) > 0 ? var.email_configuration.source_arn : null
    from_email_address     = try(length(var.email_configuration.from_email_address), 0) > 0 ? var.email_configuration.from_email_address : null
    reply_to_email_address = try(length(var.email_configuration.reply_to_email_address), 0) > 0 ? var.email_configuration.reply_to_email_address : null
  }

  # Cloud Posse aws-cognito's lambda_config: one block, only when a trigger is set.
  dynamic "lambda_config" {
    for_each = length(local.lambda_triggers) > 0 ? [1] : []
    content {
      create_auth_challenge          = lookup(local.lambda_triggers, "create_auth_challenge", null)
      custom_message                 = lookup(local.lambda_triggers, "custom_message", null)
      define_auth_challenge          = lookup(local.lambda_triggers, "define_auth_challenge", null)
      post_authentication            = lookup(local.lambda_triggers, "post_authentication", null)
      post_confirmation              = lookup(local.lambda_triggers, "post_confirmation", null)
      pre_authentication             = lookup(local.lambda_triggers, "pre_authentication", null)
      pre_sign_up                    = lookup(local.lambda_triggers, "pre_sign_up", null)
      pre_token_generation           = lookup(local.lambda_triggers, "pre_token_generation", null)
      user_migration                 = lookup(local.lambda_triggers, "user_migration", null)
      verify_auth_challenge_response = lookup(local.lambda_triggers, "verify_auth_challenge_response", null)
    }
  }

  # Cloud Posse aws-cognito's string_schemas (its number_schemas and generic
  # schemas are not ported).
  dynamic "schema" {
    for_each = var.string_schemas
    content {
      name                     = schema.value.name
      attribute_data_type      = schema.value.attribute_data_type
      developer_only_attribute = schema.value.developer_only_attribute
      mutable                  = schema.value.mutable
      required                 = schema.value.required

      string_attribute_constraints {
        min_length = schema.value.string_attribute_constraints.min_length
        max_length = schema.value.string_attribute_constraints.max_length
      }
    }
  }
}

# Cognito invokes a trigger through the function's resource policy, which must
# allow cognito-idp.amazonaws.com scoped to this pool's ARN
# (https://docs.aws.amazon.com/cognito/latest/developerguide/user-pool-lambda-migrate-user.html#user-pool-lambda-migrate-user-troubleshooting).
# Deviation from Cloud Posse aws-cognito, which leaves this grant to the
# caller: here the pool's component grants it, because only it knows the pool
# ARN before the function's component could (that would read the pool, which
# reads the function: a cycle).
resource "aws_lambda_permission" "cognito" {
  for_each = local.enabled ? local.lambda_triggers : {}

  statement_id  = "${local.name_prefix}-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = each.value
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.this[0].arn
}

# OAuth resource servers (Cloud Posse aws-cognito's resource_servers): the
# custom scopes a client_credentials client is granted.
resource "aws_cognito_resource_server" "this" {
  for_each = local.enabled ? { for r in var.resource_servers : r.identifier => r } : {}

  identifier   = each.key
  name         = each.value.name
  user_pool_id = aws_cognito_user_pool.this[0].id

  dynamic "scope" {
    for_each = each.value.scope
    content {
      scope_name        = scope.value.scope_name
      scope_description = scope.value.scope_description
    }
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

  # A client's allowed_oauth_scopes may name a resource server's scopes, which
  # must exist first.
  depends_on = [aws_cognito_resource_server.this]
}

# Hosted UI / OAuth endpoints. Only created when a domain prefix is given; an
# API authorized by the pool does not need one.
resource "aws_cognito_user_pool_domain" "this" {
  count = local.enabled && var.domain_prefix != "" ? 1 : 0

  domain       = var.domain_prefix
  user_pool_id = aws_cognito_user_pool.this[0].id
}
