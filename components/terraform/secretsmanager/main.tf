##################################################
# AWS Secrets Manager component
##################################################

locals {
  default_description = "Managed by Terraform"

  # Resolve each secret's optional attributes against the component defaults.
  defined_secrets = { for k, v in var.secrets : k => {
    name                   = coalesce(v.name, k)
    description            = coalesce(v.description, local.default_description)
    policy                 = v.policy
    path                   = v.path
    kms_key_id             = v.kms_key_id != null ? v.kms_key_id : var.default_kms_key_id
    rotation_lambda_arn    = v.rotation_lambda_arn
    rotation_days          = coalesce(v.rotation_days, var.default_rotation_days)
    rotation_automatically = coalesce(v.rotation_automatically, var.default_rotation_automatically)
    rotate_immediately     = coalesce(v.rotate_immediately, var.default_rotate_immediately)
    # Set when a SEPARATE component instance's own aws_secretsmanager_secret_rotation
    # (e.g. the lambda component's rotation_secret_arn) owns this secret's
    # rotation instead -- see that variable's description for why rotation
    # for a Lambda that itself reads this secret cannot be configured here,
    # on this component's own first apply, without failing outright. The
    # write-only value below is never re-sent unless secret_string_version
    # changes, so nothing here fights that Lambda for the value.
    rotation_managed_externally      = v.rotation_managed_externally
    recovery_window_in_days          = coalesce(v.recovery_window_in_days, var.default_recovery_window_in_days)
    generate_random_password         = v.generate_random_password
    static_value                     = v.static_value
    secret_string_version            = v.secret_string_version
    password_length                  = coalesce(v.password_length, var.random_password_length)
    random_password_override_special = coalesce(v.random_password_override_special, var.random_password_override_special)
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

  # Process secret paths with proper structure
  secrets_with_path = { for k, v in local.defined_secrets : k => merge(v, {
    full_path = join("/", compact([var.context_name, var.environment, trimprefix(trimsuffix(v.path, "/"), "/"), v.name]))
  }) }

  # Secrets that get a value from Terraform: generated, or caller-supplied
  # through the ephemeral var.secret_data. Any other secret is created empty.
  versioned_secrets = { for k, v in local.secrets_with_path : k => v if v.generate_random_password || v.static_value }

  # A local, not inline: tests cannot assert an ephemeral resource's
  # arguments. password_length is per secret (it used to be silently
  # ignored, so every generated secret was random_password_length long).
  password_generators = { for k, v in local.secrets_with_path : k => {
    length           = v.password_length
    special          = var.random_password_special
    override_special = v.random_password_override_special
    min_lower        = var.random_password_min_lower
    min_upper        = var.random_password_min_upper
    min_numeric      = var.random_password_min_numeric
    min_special      = var.random_password_min_special
  } if v.generate_random_password }
}

# Generated values. Ephemeral, as elasticache's AUTH token (#258): regenerated
# on every run but never in plan or state. A value reaches AWS only through
# the version's write-only secret_string_wo, sent only when the version is
# created; a secret_string_version change replaces the version (ForceNew).
# Cloud Posse's components keep a stored random_password instead; this one
# deliberately does not, so state readers (CI plan roles included) cannot read
# any secret.
ephemeral "random_password" "this" {
  for_each = local.password_generators

  length           = each.value.length
  special          = each.value.special
  override_special = each.value.override_special
  min_lower        = each.value.min_lower
  min_upper        = each.value.min_upper
  min_numeric      = each.value.min_numeric
  min_special      = each.value.min_special
}

locals {
  # Ephemeral (it reads ephemeral values): usable only in write-only
  # arguments. var.secret_data's keys are validated to be static_value
  # secrets, never generated ones, so the merge cannot shadow a generated
  # value.
  secret_values = merge(
    { for k, v in ephemeral.random_password.this : k => v.result },
    var.secret_data,
  )
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

# The secret's value, write-only: secret_string stays null in plan and state.
# The provider sends secret_string_wo only when the version is created; a
# secret_string_wo_version change replaces the version (ForceNew), as does a
# renamed secret. Bump the secret's secret_string_version to rotate a
# generated value or to push a changed var.secret_data value.
#
# One resource for rotating and non-rotating secrets alike. The stored value
# used to need an ignore_changes split so that Terraform would not overwrite
# a rotation Lambda's value on every apply; a write-only value is never
# compared, so it is re-sent only on a deliberate version bump. For a secret a
# Lambda rotates (rotation_lambda_arn or rotation_managed_externally), such a
# bump puts a Terraform value back as AWSCURRENT: rotate it with
# `aws secretsmanager rotate-secret` instead.
resource "aws_secretsmanager_secret_version" "this" {
  for_each = local.versioned_secrets

  secret_id                = aws_secretsmanager_secret.this[each.key].id
  secret_string_wo         = local.secret_values[each.key]
  secret_string_wo_version = each.value.secret_string_version
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
  #checkov:skip=CKV_AWS_304:False positive; rotation_days (else default_rotation_days) is validated to 1-90 days, but checkov cannot resolve it through for_each
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
      condition     = each.value.rotation_days >= 1 && each.value.rotation_days <= 90
      error_message = "The rotation_days value must be between 1 and 90 (rotate at least quarterly)."
    }
  }
}