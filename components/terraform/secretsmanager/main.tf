##################################################
# AWS Secrets Manager component
##################################################

locals {
  default_description = "Managed by Terraform"

  # Create a map of secrets from the input variables
  defined_secrets = { for k, v in var.secrets : k => {
    name                   = coalesce(lookup(v, "name", null), k)
    description            = lookup(v, "description", local.default_description)
    policy                 = lookup(v, "policy", null)
    path                   = lookup(v, "path", "")
    kms_key_id             = lookup(v, "kms_key_id", var.default_kms_key_id)
    secret_data            = lookup(v, "secret_data", null)
    rotation_lambda_arn    = lookup(v, "rotation_lambda_arn", null)
    rotation_days          = lookup(v, "rotation_days", var.default_rotation_days)
    rotation_automatically = lookup(v, "rotation_automatically", var.default_rotation_automatically)
    rotate_immediately     = lookup(v, "rotate_immediately", var.default_rotate_immediately)
    # Set when a SEPARATE component instance's own aws_secretsmanager_secret_rotation
    # (e.g. the lambda component's rotation_secret_arn) owns this secret's
    # rotation instead -- see that variable's description for why rotation
    # for a Lambda that itself reads this secret cannot be configured here,
    # on this component's own first apply, without failing outright. Drives
    # the same ignore_changes split as rotation_automatically/rotation_lambda_arn
    # below, without requiring this component to also know the Lambda's ARN.
    rotation_managed_externally      = lookup(v, "rotation_managed_externally", false)
    recovery_window_in_days          = lookup(v, "recovery_window_in_days", var.default_recovery_window_in_days)
    generate_random_password         = lookup(v, "generate_random_password", false)
    random_password_override_special = lookup(v, "random_password_override_special", var.random_password_override_special)
  } if var.enabled && var.secrets_enabled }

  # Secrets whose rotation THIS component itself configures via
  # aws_secretsmanager_secret_rotation.this below -- only safe when
  # rotation_lambda_arn already names a function that exists and is
  # permitted to be invoked by Secrets Manager at THIS component's own apply
  # time (rotate_immediately or not, RotateSecret always tests the
  # configuration against the live function). A Lambda that itself reads
  # this secret (the common case) cannot satisfy that on the secret's own
  # first apply -- see rotation_managed_externally above and the lambda
  # component's rotation_secret_arn, which configures rotation from the
  # Lambda's own component instance instead, once the function and its
  # invoke permission already exist.
  rotation_enabled = { for k, v in local.secrets_with_path : k => v if v.rotation_automatically && v.rotation_lambda_arn != null }

  # Secrets whose value in AWS is owned by a rotation Lambda's finishSecret
  # step, either way -- this component's own rotation_enabled above, or a
  # separate component instance's rotation_managed_externally. Either way,
  # this component's aws_secretsmanager_secret_version must stop fighting
  # that Lambda for the value after the initial create -- see the two
  # aws_secretsmanager_secret_version resources below for why they are split
  # on this.
  version_managed_externally = { for k, v in local.secrets_with_path : k => v if v.rotation_managed_externally || (v.rotation_automatically && v.rotation_lambda_arn != null) }

  # Process secret paths with proper structure
  secrets_with_path = { for k, v in local.defined_secrets : k => merge(v, {
    full_path = join("/", compact([var.context_name, var.environment, trimprefix(trimsuffix(v.path, "/"), "/"), v.name]))
  }) }
}

# Generate random passwords for secrets that need it
resource "random_password" "this" {
  for_each = { for k, v in local.secrets_with_path : k => v if v.generate_random_password }

  length           = var.random_password_length
  special          = var.random_password_special
  override_special = each.value.random_password_override_special
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
      condition     = !contains(["prod", "production"], lower(var.environment)) || each.value.recovery_window_in_days >= 7
      error_message = "Production secrets must have a recovery window of at least 7 days for protection against accidental deletion."
    }
  }
}

# Create secret versions with values. Split in two by rotation status: once a
# secret's rotation Lambda has run at least once, the value AWS actually
# holds under AWSCURRENT is whatever the Lambda's finishSecret step put
# there, not var.secret_data/random_password.this -- so this resource, which
# only ever knows the ORIGINAL value, must not fight the Lambda for it on
# every later apply. The rotation-enabled half below is otherwise identical
# but ignores secret_string after the initial create; the non-rotating half
# keeps managing it exactly as before.
resource "aws_secretsmanager_secret_version" "this" {
  for_each = { for k, v in local.secrets_with_path : k => v if(v.secret_data != null || v.generate_random_password) && !contains(keys(local.version_managed_externally), k) }

  secret_id     = aws_secretsmanager_secret.this[each.key].id
  secret_string = each.value.generate_random_password ? random_password.this[each.key].result : each.value.secret_data

  lifecycle {
    precondition {
      condition     = each.value.generate_random_password || (each.value.secret_data != null && length(each.value.secret_data) > 0)
      error_message = "Secret data must not be empty. For secret ${each.key}, either provide non-empty secret_data or set generate_random_password=true."
    }

    precondition {
      condition     = each.value.generate_random_password || (each.value.secret_data == null) || (!can(regex("^\\s*\\{", each.value.secret_data))) || (can(jsondecode(each.value.secret_data)) && length(jsondecode(each.value.secret_data)) > 0)
      error_message = "Secret data for ${each.key} appears to be JSON but is not valid or is empty. Ensure the JSON is well-formed and contains data."
    }

    precondition {
      condition     = each.value.generate_random_password || each.value.secret_data == null || (!can(regex("(?i)(testpass|password123|p@ssw0rd|admin123|changeme|secret|secretkey|test-only|abc123|123456|default|temp|dummy|foobar|[a-z0-9]{1,8}|dev|test|stage|prod)[-_]?(password|secret|key|credential|token|pass|pwd)", each.value.secret_data)) && !can(regex("(?i)(AKIA[0-9A-Z]{16})", each.value.secret_data)) && !can(regex("(?i)(sk_live_[0-9a-zA-Z]{24})", each.value.secret_data)) && !can(regex("(?i)(github_pat_[0-9a-zA-Z]{22}_[0-9a-zA-Z]{59})", each.value.secret_data)) && !can(regex("(?i)(api[_-]?key|secret[_-]?key|access[_-]?key|auth[_-]?token)['\"]?\\s*[=:]\\s*['\"]?[a-zA-Z0-9_]{8,}['\"]?", each.value.secret_data)))
      error_message = "Secret data for ${each.key} appears to contain a weak, test, or hardcoded credential pattern. Use generate_random_password or provide a strong secret without using predictable patterns."
    }
  }
}

# The rotation-enabled half of the version resource above: same secret_data/
# generate_random_password validation, but secret_string changes after the
# initial create are ignored, because the rotation Lambda's finishSecret step
# owns the value from then on (see the comment above aws_secretsmanager_secret_version.this).
resource "aws_secretsmanager_secret_version" "rotating" {
  for_each = { for k, v in local.secrets_with_path : k => v if(v.secret_data != null || v.generate_random_password) && contains(keys(local.version_managed_externally), k) }

  secret_id     = aws_secretsmanager_secret.this[each.key].id
  secret_string = each.value.generate_random_password ? random_password.this[each.key].result : each.value.secret_data

  lifecycle {
    ignore_changes = [secret_string]

    precondition {
      condition     = each.value.generate_random_password || (each.value.secret_data != null && length(each.value.secret_data) > 0)
      error_message = "Secret data must not be empty. For secret ${each.key}, either provide non-empty secret_data or set generate_random_password=true."
    }

    precondition {
      condition     = each.value.generate_random_password || (each.value.secret_data == null) || (!can(regex("^\\s*\\{", each.value.secret_data))) || (can(jsondecode(each.value.secret_data)) && length(jsondecode(each.value.secret_data)) > 0)
      error_message = "Secret data for ${each.key} appears to be JSON but is not valid or is empty. Ensure the JSON is well-formed and contains data."
    }

    precondition {
      condition     = each.value.generate_random_password || each.value.secret_data == null || (!can(regex("(?i)(testpass|password123|p@ssw0rd|admin123|changeme|secret|secretkey|test-only|abc123|123456|default|temp|dummy|foobar|[a-z0-9]{1,8}|dev|test|stage|prod)[-_]?(password|secret|key|credential|token|pass|pwd)", each.value.secret_data)) && !can(regex("(?i)(AKIA[0-9A-Z]{16})", each.value.secret_data)) && !can(regex("(?i)(sk_live_[0-9a-zA-Z]{24})", each.value.secret_data)) && !can(regex("(?i)(github_pat_[0-9a-zA-Z]{22}_[0-9a-zA-Z]{59})", each.value.secret_data)) && !can(regex("(?i)(api[_-]?key|secret[_-]?key|access[_-]?key|auth[_-]?token)['\"]?\\s*[=:]\\s*['\"]?[a-zA-Z0-9_]{8,}['\"]?", each.value.secret_data)))
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

# Configure rotation for secrets whose rotation THIS component itself can
# safely own -- see local.rotation_enabled's comment above for when that is
# (rotation_lambda_arn must already name a function that exists and is
# permitted to invoke, at THIS apply). A secret rotated by a Lambda that
# itself reads the secret (the common case, e.g. microservices/secrets' redis
# and jwt_signing) uses rotation_managed_externally instead, and the lambda
# component's own rotation_secret_arn creates this same kind of resource from
# the Lambda's own component instance, where the ordering is safe.
resource "aws_secretsmanager_secret_rotation" "this" {
  for_each = local.rotation_enabled

  secret_id           = aws_secretsmanager_secret.this[each.key].id
  rotation_lambda_arn = each.value.rotation_lambda_arn
  # Default false: rotate_immediately (the AWS provider's own default is
  # true) would invoke rotation_lambda_arn the moment this resource applies.
  # Even at false, Secrets Manager's RotateSecret API (which creating this
  # resource calls under the hood) tests the rotation configuration by
  # invoking the function's testSecret step against a temporary AWSPENDING
  # version it creates and then removes -- so rotation_lambda_arn must
  # already be invokable by secretsmanager.amazonaws.com before this
  # resource applies, not merely exist. Set true only once the rotation
  # function is confirmed deployed, invokable, and tested independently of
  # this apply.
  rotate_immediately = each.value.rotate_immediately

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