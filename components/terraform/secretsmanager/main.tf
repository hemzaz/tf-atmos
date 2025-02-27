##################################################
# AWS Secrets Manager component
##################################################

locals {
  enabled             = module.this.enabled
  name_prefix         = "${module.this.environment}-${module.this.name}"
  default_description = "Managed by Terraform"
  
  # Create a map of secrets from the input variables
  defined_secrets = { for k, v in var.secrets : k => {
    name        = coalesce(lookup(v, "name", null), k)
    description = lookup(v, "description", local.default_description)
    policy      = lookup(v, "policy", null)
    path        = lookup(v, "path", "")
    kms_key_id  = lookup(v, "kms_key_id", var.default_kms_key_id)
    secret_data = lookup(v, "secret_data", null)
    rotation_lambda_arn = lookup(v, "rotation_lambda_arn", null)
    rotation_days       = lookup(v, "rotation_days", var.default_rotation_days)
    rotation_automatically = lookup(v, "rotation_automatically", var.default_rotation_automatically)
    recovery_window_in_days = lookup(v, "recovery_window_in_days", var.default_recovery_window_in_days)
    generate_random_password = lookup(v, "generate_random_password", false)
  } if var.secrets_enabled }

  # Process secret paths with proper structure
  secrets_with_path = { for k, v in local.defined_secrets : k => merge(v, {
    full_path = join("/", compact([var.context_name, module.this.environment, trimprefix(trimsuffix(v.path, "/"), "/"), v.name]))
  })}
}

# Generate random passwords for secrets that need it
resource "random_password" "this" {
  for_each = { for k, v in local.secrets_with_path : k => v if v.generate_random_password }
  
  length           = var.random_password_length
  special          = var.random_password_special
  override_special = var.random_password_override_special
  min_lower        = var.random_password_min_lower
  min_upper        = var.random_password_min_upper
  min_numeric      = var.random_password_min_numeric
  min_special      = var.random_password_min_special
}

# Create the AWS secrets
resource "aws_secretsmanager_secret" "this" {
  for_each = local.secrets_with_path
  
  name                    = each.value.full_path
  description             = each.value.description
  kms_key_id              = each.value.kms_key_id
  recovery_window_in_days = each.value.recovery_window_in_days
  tags                    = module.this.tags
  
  lifecycle {
    precondition {
      condition     = each.value.kms_key_id != null || var.default_kms_key_id != null
      error_message = "Either default_kms_key_id or individual secret kms_key_id must be set to ensure encryption."
    }
  }
}

# Create secret versions with values
resource "aws_secretsmanager_secret_version" "this" {
  for_each = { for k, v in local.secrets_with_path : k => v if v.secret_data != null || v.generate_random_password }
  
  secret_id     = aws_secretsmanager_secret.this[each.key].id
  secret_string = each.value.generate_random_password ? random_password.this[each.key].result : each.value.secret_data
}

# Attach resource policies to secrets if specified
resource "aws_secretsmanager_secret_policy" "this" {
  for_each = { for k, v in local.secrets_with_path : k => v if v.policy != null }
  
  secret_arn = aws_secretsmanager_secret.this[each.key].arn
  policy     = each.value.policy
}

# Configure rotation for secrets that require it
resource "aws_secretsmanager_secret_rotation" "this" {
  for_each = { for k, v in local.secrets_with_path : k => v if v.rotation_automatically && v.rotation_lambda_arn != null }
  
  secret_id           = aws_secretsmanager_secret.this[each.key].id
  rotation_lambda_arn = each.value.rotation_lambda_arn
  
  rotation_rules {
    automatically_after_days = each.value.rotation_days
  }
}