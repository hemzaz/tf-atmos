##################################################
# AWS Secrets Manager component
##################################################

locals {
  enabled             = module.this.enabled
  name_prefix         = "${module.this.environment}-${module.this.name}"
  default_description = "Managed by Terraform"

  # Create a map of secrets from the input variables
  defined_secrets = { for k, v in var.secrets : k => {
    name                     = coalesce(lookup(v, "name", null), k)
    description              = lookup(v, "description", local.default_description)
    policy                   = lookup(v, "policy", null)
    path                     = lookup(v, "path", "")
    kms_key_id               = lookup(v, "kms_key_id", var.default_kms_key_id)
    secret_data              = lookup(v, "secret_data", null)
    rotation_lambda_arn      = lookup(v, "rotation_lambda_arn", null)
    rotation_days            = lookup(v, "rotation_days", var.default_rotation_days)
    rotation_automatically   = lookup(v, "rotation_automatically", var.default_rotation_automatically)
    recovery_window_in_days  = lookup(v, "recovery_window_in_days", var.default_recovery_window_in_days)
    generate_random_password = lookup(v, "generate_random_password", false)
  } if var.secrets_enabled }

  # Process secret paths with proper structure
  secrets_with_path = { for k, v in local.defined_secrets : k => merge(v, {
    full_path = join("/", compact([var.context_name, module.this.environment, trimprefix(trimsuffix(v.path, "/"), "/"), v.name]))
  }) }
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
  
  lifecycle {
    # Ensure passwords are treated as sensitive values
    precondition {
      condition     = var.random_password_length >= 8
      error_message = "Password length must be at least 8 characters for security."
    }
  }
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
    # Validate encryption key is specified
    precondition {
      condition     = each.value.kms_key_id != null || var.default_kms_key_id != null
      error_message = "Either default_kms_key_id or individual secret kms_key_id must be set to ensure encryption."
    }
    
    # Validate recovery window is reasonable
    precondition {
      condition     = each.value.recovery_window_in_days >= 7 || each.value.recovery_window_in_days == 0
      error_message = "Recovery window should be either 0 (force delete with no window) or at least 7 days for security (recommended: 7-30 days)."
    }
    
    # Add explicit protection for production secrets
    precondition {
      condition     = !contains(["prod", "production"], lower(module.this.environment)) || each.value.recovery_window_in_days >= 7
      error_message = "Production secrets must have a recovery window of at least 7 days for protection against accidental deletion."
    }
  }
}

# Create secret versions with values
resource "aws_secretsmanager_secret_version" "this" {
  for_each = { for k, v in local.secrets_with_path : k => v if v.secret_data != null || v.generate_random_password }

  secret_id     = aws_secretsmanager_secret.this[each.key].id
  secret_string = each.value.generate_random_password ? random_password.this[each.key].result : each.value.secret_data

  lifecycle {
    # Add validation to ensure secret data is not empty
    precondition {
      condition     = each.value.generate_random_password || (each.value.secret_data != null && length(each.value.secret_data) > 0)
      error_message = "Secret data must not be empty. For secret ${each.key}, either provide non-empty secret_data or set generate_random_password=true."
    }

    # Add validation for JSON-formatted secrets with strict checking
    precondition {
      # More robust JSON validation for secret data
      # First check if random password is being generated or if secret data is null (both are valid)
      # Then check if it doesn't look like JSON (starts with '{') - if not JSON, no validation needed
      # Finally, if it looks like JSON, validate it can be decoded and is not empty
      condition     = each.value.generate_random_password || 
                     (each.value.secret_data == null) || 
                     (!can(regex("^\\s*\\{", each.value.secret_data))) || 
                     (can(jsondecode(each.value.secret_data)) && length(jsondecode(each.value.secret_data)) > 0)
      error_message = "Secret data for ${each.key} appears to be JSON but is not valid or is empty. Ensure the JSON is well-formed and contains data."
    }
    
    # Add comprehensive validation for sensitive data patterns
    precondition {
      # Check that secrets don't contain obviously hardcoded credentials in dev/test patterns
      # More comprehensive regex pattern to catch various forms of weak or test credentials
      condition     = each.value.generate_random_password || each.value.secret_data == null ||
                      !can(regex("(?i)(testpass|password123|p@ssw0rd|admin123|changeme|secret|secretkey|test-only|abc123|123456|default|temp|dummy|foobar|[a-z0-9]{1,8}|dev|test|stage|prod)[-_]?(password|secret|key|credential|token|pass|pwd)", each.value.secret_data)) &&
                      !can(regex("(?i)(AKIA[0-9A-Z]{16})", each.value.secret_data)) &&  # AWS Access Key pattern
                      !can(regex("(?i)(sk_live_[0-9a-zA-Z]{24})", each.value.secret_data)) &&  # Stripe secret key pattern
                      !can(regex("(?i)(github_pat_[0-9a-zA-Z]{22}_[0-9a-zA-Z]{59})", each.value.secret_data)) && # GitHub PAT
                      !can(regex("(?i)(api[_-]?key|secret[_-]?key|access[_-]?key|auth[_-]?token)['\"]?\\s*[=:]\\s*['\"]?[a-zA-Z0-9_]{8,}['\"]?", each.value.secret_data))  # Generic API key patterns
      error_message = "Secret data for ${each.key} appears to contain a weak, test, or hardcoded credential pattern. Use generate_random_password or provide a strong secret without using predictable patterns."
    }
  }
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
  
  # Add validation for Lambda ARN format and rotation days
  lifecycle {
    precondition {
      condition     = can(regex("^arn:aws:lambda:[a-z0-9-]+:[0-9]{12}:function:.+$", each.value.rotation_lambda_arn))
      error_message = "The rotation_lambda_arn must be a valid Lambda function ARN (e.g., arn:aws:lambda:region:account-id:function:function-name)."
    }
    
    precondition {
      condition     = each.value.rotation_days >= 1 && each.value.rotation_days <= 365
      error_message = "The rotation_days value must be between 1 and 365."
    }
  }
}