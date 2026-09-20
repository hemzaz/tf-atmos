variable "region" {
  type        = string
  description = "AWS region"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "The region must be a valid AWS region name (e.g., us-east-1, eu-west-1)."
  }
}

variable "name_prefix" {
  type        = string
  description = "Prefix for resource names. Stacks set this to tenant-account-environment"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.name_prefix))
    error_message = "The name_prefix must be lowercase alphanumeric with hyphens."
  }
}

variable "enabled" {
  type        = bool
  description = "Set to false to prevent the component from creating any resources"
  default     = true
}

# Required on purpose: a `default = {}` here makes every resource look untagged to
# tflint/checkov, which run per-component without stack vars. Keep it required.
variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources; must include Environment (used in resource names)"

  validation {
    condition     = trimspace(lookup(var.tags, "Environment", "")) != ""
    error_message = "tags must include a non-empty Environment value."
  }
}

variable "username_attributes" {
  type        = list(string)
  description = "Attributes users can sign in with. Immutable: changing it replaces the pool and every user in it"
  default     = ["email"]

  validation {
    condition     = alltrue([for a in var.username_attributes : contains(["email", "phone_number"], a)])
    error_message = "username_attributes entries must be email or phone_number."
  }
}

variable "auto_verified_attributes" {
  type        = list(string)
  description = "Attributes Cognito verifies automatically. Immutable, like username_attributes"
  default     = ["email"]

  validation {
    condition     = alltrue([for a in var.auto_verified_attributes : contains(["email", "phone_number"], a)])
    error_message = "auto_verified_attributes entries must be email or phone_number."
  }
}

variable "deletion_protection" {
  type        = bool
  description = "Refuse to delete the pool. Leave on wherever real users exist"
  default     = true
}

variable "password_minimum_length" {
  type        = number
  description = "Minimum password length. Complexity (upper, lower, digit, symbol) is always required"
  default     = 14

  validation {
    condition     = var.password_minimum_length >= 8 && var.password_minimum_length <= 99
    error_message = "password_minimum_length must be between 8 and 99."
  }
}

variable "temporary_password_validity_days" {
  type        = number
  description = "Days an admin-created temporary password stays usable"
  default     = 7

  validation {
    condition     = var.temporary_password_validity_days >= 1 && var.temporary_password_validity_days <= 365
    error_message = "temporary_password_validity_days must be between 1 and 365."
  }
}

variable "mfa_configuration" {
  type        = string
  description = "OFF, ON (every user must use MFA) or OPTIONAL. Software-token MFA is enabled whenever this is not OFF"
  default     = "OPTIONAL"

  validation {
    condition     = contains(["OFF", "ON", "OPTIONAL"], var.mfa_configuration)
    error_message = "mfa_configuration must be one of OFF, ON, OPTIONAL."
  }
}

variable "allow_admin_create_user_only" {
  type        = bool
  description = "Only administrators may create users; public self-signup is refused"
  default     = true
}

variable "advanced_security_mode" {
  type        = string
  description = "Cognito threat protection: OFF, AUDIT (log only) or ENFORCED (block risky sign-ins). Billed per monthly active user above OFF"
  default     = "ENFORCED"

  validation {
    condition     = contains(["OFF", "AUDIT", "ENFORCED"], var.advanced_security_mode)
    error_message = "advanced_security_mode must be one of OFF, AUDIT, ENFORCED."
  }
}

variable "domain_prefix" {
  type        = string
  description = "Prefix for the Cognito hosted UI domain. Empty means no hosted UI, which an API-authorizer-only pool does not need"
  default     = ""

  validation {
    condition     = var.domain_prefix == "" || can(regex("^[a-z0-9][a-z0-9-]{0,62}$", var.domain_prefix))
    error_message = "domain_prefix must be lowercase alphanumeric with hyphens, up to 63 characters."
  }
}

variable "clients" {
  type = map(object({
    generate_secret               = optional(bool, true)
    explicit_auth_flows           = optional(list(string), ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"])
    allowed_oauth_flows           = optional(list(string), [])
    allowed_oauth_scopes          = optional(list(string), [])
    callback_urls                 = optional(list(string), [])
    logout_urls                   = optional(list(string), [])
    supported_identity_providers  = optional(list(string), ["COGNITO"])
    access_token_validity_minutes = optional(number, 60)
    id_token_validity_minutes     = optional(number, 60)
    refresh_token_validity_days   = optional(number, 30)
  }))
  description = "App clients keyed by name. The key is appended to name_prefix"
  default     = {}

  validation {
    condition = alltrue([
      for c in values(var.clients) : alltrue([
        for f in c.explicit_auth_flows : startswith(f, "ALLOW_")
      ])
    ])
    error_message = "clients[*].explicit_auth_flows entries must use the ALLOW_ prefixed names (e.g. ALLOW_USER_SRP_AUTH)."
  }

  validation {
    condition = alltrue([
      for c in values(var.clients) :
      !contains(c.explicit_auth_flows, "ALLOW_USER_PASSWORD_AUTH")
    ])
    error_message = "ALLOW_USER_PASSWORD_AUTH sends the password to the API in cleartext-equivalent form; use ALLOW_USER_SRP_AUTH instead."
  }
}
