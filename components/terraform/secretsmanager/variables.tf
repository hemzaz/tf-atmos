##################################################
# AWS Secrets Manager Component Variables
##################################################

variable "region" {
  type        = string
  description = "AWS region"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "The region must be a valid AWS region name (e.g., us-east-1, eu-west-1)."
  }
}

variable "environment" {
  type        = string
  description = "Environment name used as the second segment of the secret path"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.environment))
    error_message = "environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enabled" {
  type        = bool
  description = "Set to false to prevent the component from creating any resources"
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources via the provider default_tags"
  default     = {}
}

variable "secrets_enabled" {
  type        = bool
  description = "Enable/disable the secrets manager component"
  default     = true
}

variable "context_name" {
  type        = string
  description = "The context name to use as the first segment of the secret path (application, service, or system name)"

  validation {
    condition     = var.context_name != ""
    error_message = "The context_name variable is required and cannot be empty."
  }
}

variable "secrets" {
  type = map(object({
    name                             = optional(string)
    description                      = optional(string)
    policy                           = optional(string)
    path                             = optional(string, "")
    kms_key_id                       = optional(string)
    rotation_lambda_arn              = optional(string)
    rotation_days                    = optional(number)
    rotation_automatically           = optional(bool)
    rotate_immediately               = optional(bool)
    rotation_managed_externally      = optional(bool, false)
    recovery_window_in_days          = optional(number)
    generate_random_password         = optional(bool, false)
    password_length                  = optional(number)
    random_password_override_special = optional(string)
    static_value                     = optional(bool, false)
    secret_string_version            = optional(number, 1)
    # Removed: values never come through this (non-ephemeral) variable. Kept
    # in the type only so that a leftover is rejected below instead of being
    # dropped silently by the object conversion.
    secret_data = optional(any)
  }))
  description = <<-EOT
    Map of secrets to be created. Each secret can have the following attributes:
      - name: The name of the secret (will be used as the last segment of the path; defaults to the map key)
      - description: Description of the secret (defaults to 'Managed by Terraform')
      - policy: JSON IAM policy to attach to the secret (optional)
      - path: Additional path segments to insert between environment and name (optional)
      - kms_key_id: KMS key ID to use for encryption (defaults to default_kms_key_id)
      - generate_random_password: Generate the value with an ephemeral random_password (defaults to false).
        The value is written write-only: never in plan or state
      - password_length: Length of this secret's generated password (defaults to random_password_length)
      - random_password_override_special: Special characters for this secret's generated password
        (defaults to random_password_override_special); override per-secret when the consumer's
        allowed character set differs from the component default, e.g. ElastiCache AUTH tokens
      - static_value: The value is caller-supplied, from var.secret_data[<this key>] (ephemeral,
        written write-only). Mutually exclusive with generate_random_password
      - secret_string_version: Write-only version of the value (defaults to 1). The value is sent on
        create, and on update only when this changes: bump it to rotate a generated value or to push
        a changed var.secret_data value
      - rotation_lambda_arn: ARN of the Lambda function for rotation (optional). Only safe when that
        function already exists and is permitted to be invoked by Secrets Manager AT THIS component's
        own apply time -- a Lambda that itself reads this secret (the common case) cannot satisfy that
        on the secret's first apply; use rotation_managed_externally for that instead, and configure
        rotation from the Lambda's own component instance (the lambda component's rotation_secret_arn)
      - rotation_days: Days between automatic rotation (defaults to default_rotation_days)
      - rotation_automatically: Whether to enable automatic rotation (defaults to default_rotation_automatically)
      - rotate_immediately: Whether enabling rotation invokes rotation_lambda_arn right away (defaults to default_rotate_immediately)
      - rotation_managed_externally: Set true when a SEPARATE component instance's own
        aws_secretsmanager_secret_rotation owns this secret's rotation. Informational for this
        component: the write-only value is never re-sent unless secret_string_version changes, so the
        rotation Lambda's value is never overwritten either way. Defaults to false
      - recovery_window_in_days: Window for recovery before permanent deletion (defaults to default_recovery_window_in_days)
    A secret with neither generate_random_password nor static_value is created empty, for an operator
    or application to fill.
  EOT
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for k, v in var.secrets : !(v.generate_random_password && v.static_value)])
    error_message = "generate_random_password and static_value cannot both be true for the same secret."
  }

  validation {
    condition     = alltrue([for k, v in var.secrets : v.secret_data == null])
    error_message = "secrets[*].secret_data was removed: it put the value in plan and state. Set static_value = true and supply the value through the ephemeral secret_data variable (TF_VAR_secret_data) instead."
  }

  validation {
    condition = alltrue([
      for k, v in var.secrets : v.password_length == null || (
        try(v.password_length >= 8 && floor(v.password_length) == v.password_length, false)
        && v.password_length >= var.random_password_min_lower + var.random_password_min_upper + var.random_password_min_numeric + var.random_password_min_special
      )
    ])
    error_message = "password_length must be a whole number of at least 8, and at least the sum of the random_password_min_* counts."
  }

  validation {
    condition     = alltrue([for k, v in var.secrets : v.secret_string_version >= 1 && floor(v.secret_string_version) == v.secret_string_version])
    error_message = "secret_string_version must be a whole number of at least 1."
  }
}

# Caller-supplied values, for secrets with static_value = true. Ephemeral:
# never in a saved plan or in state; it reaches AWS only through the version's
# write-only secret_string_wo. Supply it as TF_VAR_secret_data in the one
# instance's Atmos `env:` section (a real secret via `!env <INSTANCE_VAR>`),
# never as a global TF_VAR_secret_data, which every secretsmanager instance
# would receive (see README): Terraform requires an ephemeral variable set at
# plan to be set again when a saved plan is applied, and `atmos terraform
# deploy --from-plan` applies the planfile without the varfile.
variable "secret_data" {
  type        = map(string)
  description = "Values of the static_value secrets, keyed by the secrets map key. Ephemeral and sensitive: never in plan or state. A JSON-shaped value is stored as written, so key/value lookups (e.g. ESO's property) keep working."
  ephemeral   = true
  sensitive   = true
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for k in keys(var.secret_data) : try(var.secrets[k].static_value, false)])
    error_message = "Every secret_data key must name a secrets entry with static_value = true."
  }

  validation {
    condition     = alltrue([for k, v in var.secrets : !v.static_value || length(trimspace(lookup(var.secret_data, k, ""))) > 0])
    error_message = "Every secrets entry with static_value = true needs a non-empty value in secret_data (TF_VAR_secret_data)."
  }

  validation {
    condition     = alltrue([for k, v in var.secret_data : !can(regex("^\\s*\\{", v)) || try(length(jsondecode(v)) > 0, false)])
    error_message = "A secret_data value that starts with '{' must be well-formed, non-empty JSON."
  }

  validation {
    # One line: checkov's HCL parser rejects this expression split across lines.
    condition     = alltrue([for k, v in var.secret_data : !can(regex("(?i)(testpass|password123|p@ssw0rd|admin123|changeme|secret|secretkey|test-only|abc123|123456|default|temp|dummy|foobar|[a-z0-9]{1,8}|dev|test|stage|prod)[-_]?(password|secret|key|credential|token|pass|pwd)", v)) && !can(regex("(?i)(AKIA[0-9A-Z]{16})", v)) && !can(regex("(?i)(sk_live_[0-9a-zA-Z]{24})", v)) && !can(regex("(?i)(github_pat_[0-9a-zA-Z]{22}_[0-9a-zA-Z]{59})", v)) && !can(regex("(?i)(api[_-]?key|secret[_-]?key|access[_-]?key|auth[_-]?token)['\"]?\\s*[=:]\\s*['\"]?[a-zA-Z0-9_]{8,}['\"]?", v))])
    error_message = "A secret_data value appears to contain a weak, test, or hardcoded credential pattern. Use generate_random_password or provide a strong secret without predictable patterns."
  }
}

variable "default_kms_key_id" {
  type        = string
  description = "Default KMS key ID to use for encrypting secrets if not specified at the secret level"
  default     = null
}

variable "default_rotation_days" {
  type        = number
  description = "Default number of days between automatic rotation if not specified at the secret level"
  default     = 30

  validation {
    condition     = var.default_rotation_days >= 1 && var.default_rotation_days <= 365
    error_message = "default_rotation_days must be between 1 and 365."
  }
}

variable "default_rotation_automatically" {
  type        = bool
  description = "Default setting for automatic rotation if not specified at the secret level"
  default     = false
}

variable "default_rotate_immediately" {
  type        = bool
  description = "Default for rotate_immediately (whether enabling rotation invokes rotation_lambda_arn right away) if not specified at the secret level. Defaults to false, opposite of the AWS provider's own default of true: rotation_lambda_arn is commonly a Lambda applied by a separate component instance, which may not exist and be invokable yet on this component's first apply."
  default     = false
}

variable "default_recovery_window_in_days" {
  type        = number
  description = "Default recovery window in days before permanent deletion if not specified at the secret level"
  default     = 30

  validation {
    condition     = var.default_recovery_window_in_days >= 0 && var.default_recovery_window_in_days <= 30
    error_message = "default_recovery_window_in_days must be between 0 and 30."
  }
}

# Random password generation parameters
variable "random_password_length" {
  type        = number
  description = "Length of generated random passwords"
  default     = 32

  validation {
    condition     = var.random_password_length >= 8
    error_message = "random_password_length must be at least 8 characters."
  }
}

variable "random_password_special" {
  type        = bool
  description = "Whether to include special characters in random passwords"
  default     = true
}

variable "random_password_override_special" {
  type        = string
  description = "Supply your own list of special characters for random password generation"
  default     = "!#$%&*()-_=+[]{}<>:?"
}

variable "random_password_min_lower" {
  type        = number
  description = "Minimum number of lowercase characters in random passwords"
  default     = 5
}

variable "random_password_min_upper" {
  type        = number
  description = "Minimum number of uppercase characters in random passwords"
  default     = 5
}

variable "random_password_min_numeric" {
  type        = number
  description = "Minimum number of numeric characters in random passwords"
  default     = 5
}

variable "random_password_min_special" {
  type        = number
  description = "Minimum number of special characters in random passwords"
  default     = 5
}