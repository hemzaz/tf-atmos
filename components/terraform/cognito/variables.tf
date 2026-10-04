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
  description = "Cognito threat protection: OFF, AUDIT (log only) or ENFORCED (block risky sign-ins). AUDIT and ENFORCED require user_pool_tier = PLUS"
  # OFF, the AWS default, so the component's own defaults are consistent with
  # user_pool_tier's ESSENTIALS. catalog/cognito/defaults.yaml sets ENFORCED +
  # PLUS for every AWS stack.
  default = "OFF"

  validation {
    condition     = contains(["OFF", "AUDIT", "ENFORCED"], var.advanced_security_mode)
    error_message = "advanced_security_mode must be one of OFF, AUDIT, ENFORCED."
  }

  # Threat protection is a Plus-plan feature: "If you set AdvancedSecurityMode
  # to AUDIT or ENFORCED, your user pool tier must be PLUS"
  # (https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-sign-in-feature-plans.html).
  # Left unset, AWS silently moves the pool to PLUS; this makes the cost explicit.
  validation {
    condition     = var.advanced_security_mode == "OFF" || var.user_pool_tier == "PLUS"
    error_message = "advanced_security_mode AUDIT or ENFORCED requires user_pool_tier = \"PLUS\" (threat protection is a Plus-plan feature, billed per MAU with no free tier)."
  }
}

variable "user_pool_tier" {
  type        = string
  description = "Cognito user pool feature plan: LITE, ESSENTIALS (the AWS default) or PLUS (required for threat protection, advanced_security_mode AUDIT/ENFORCED)"
  default     = "ESSENTIALS"

  validation {
    condition     = contains(["LITE", "ESSENTIALS", "PLUS"], var.user_pool_tier)
    error_message = "user_pool_tier must be one of LITE, ESSENTIALS, PLUS."
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

variable "string_schemas" {
  type = list(object({
    name                     = string
    attribute_data_type      = optional(string, "String")
    developer_only_attribute = optional(bool, false)
    mutable                  = optional(bool, true)
    required                 = optional(bool, false)
    string_attribute_constraints = optional(object({
      min_length = optional(number, 0)
      max_length = optional(number, 2048)
    }), {})
  }))
  description = "String attributes of the pool's schema, as Cloud Posse aws-cognito's string_schemas. A custom attribute is named without its custom: prefix (tenant_id is custom:tenant_id). Attributes cannot be changed or removed once the pool exists; new ones can be added"
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for s in var.string_schemas : s.attribute_data_type == "String"])
    error_message = "string_schemas entries must have attribute_data_type String."
  }

  validation {
    condition     = alltrue([for s in var.string_schemas : can(regex("^[A-Za-z0-9_]{1,20}$", s.name))])
    error_message = "string_schemas names must be 1-20 letters, digits or underscores, without the custom: prefix."
  }

  validation {
    condition     = length(distinct([for s in var.string_schemas : s.name])) == length(var.string_schemas)
    error_message = "string_schemas names must be unique."
  }

  validation {
    condition = alltrue([for s in var.string_schemas :
      s.string_attribute_constraints.min_length >= 0
      && s.string_attribute_constraints.min_length <= s.string_attribute_constraints.max_length
      && s.string_attribute_constraints.max_length <= 2048
    ])
    error_message = "string_attribute_constraints need 0 <= min_length <= max_length <= 2048."
  }

  # AWS rejects a required custom attribute at apply; only standard (OIDC) attributes can be required.
  validation {
    condition = alltrue([for s in var.string_schemas : s.required == false || contains([
      "address", "birthdate", "email", "family_name", "gender", "given_name", "locale", "middle_name",
      "name", "nickname", "phone_number", "picture", "preferred_username", "profile", "updated_at",
      "website", "zoneinfo",
    ], s.name)])
    error_message = "Only standard attributes (email, name, phone_number, ...) can be required; a custom attribute must set required = false."
  }
}

variable "resource_servers" {
  type = list(object({
    identifier = string
    name       = string
    scope = optional(list(object({
      scope_name        = string
      scope_description = string
    })), [])
  }))
  description = "OAuth resource servers, as Cloud Posse aws-cognito's resource_servers. A client's allowed_oauth_scopes name their scopes as <identifier>/<scope_name> (client_credentials clients need them)"
  default     = []
  nullable    = false

  validation {
    condition     = length(distinct([for r in var.resource_servers : r.identifier])) == length(var.resource_servers)
    error_message = "resource_servers identifiers must be unique."
  }

  validation {
    condition = alltrue([for r in var.resource_servers :
      can(regex("^[\\x21\\x23-\\x5B\\x5D-\\x7E]{1,256}$", r.identifier))
      && alltrue([for s in r.scope : can(regex("^[\\x21\\x23-\\x2E\\x30-\\x5B\\x5D-\\x7E]{1,256}$", s.scope_name))])
      && length(distinct([for s in r.scope : s.scope_name])) == length(r.scope)
    ])
    error_message = "Each resource server needs an identifier of 1-256 printable characters without spaces, quotes or backslashes, and unique scope names without slashes."
  }

  validation {
    condition = alltrue([for r in var.resource_servers :
      can(regex("^[\\w\\s+=,.@-]{1,256}$", r.name))
      && length(r.scope) <= 100
      && alltrue([for s in r.scope : length(s.scope_description) >= 1 && length(s.scope_description) <= 256])
    ])
    error_message = "Each resource server needs a name of 1-256 word characters, spaces or +=,.@-, at most 100 scopes, and a 1-256 character scope_description per scope."
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

  # AWS rejects these client_credentials combinations at apply.
  validation {
    condition = alltrue([for c in values(var.clients) :
      contains(c.allowed_oauth_flows, "client_credentials") == false
      || (c.generate_secret && length(setsubtract(c.allowed_oauth_flows, ["client_credentials"])) == 0)
    ])
    error_message = "A client_credentials client needs generate_secret = true and no other allowed_oauth_flows (code, implicit)."
  }

  validation {
    condition     = var.domain_prefix != "" || alltrue([for c in values(var.clients) : !contains(c.allowed_oauth_flows, "client_credentials")])
    error_message = "A client_credentials client needs domain_prefix: its token endpoint is the hosted domain."
  }

  # A resource-server scope (<identifier>/<scope_name>) must be declared in resource_servers.
  validation {
    condition = alltrue(flatten([for c in values(var.clients) : [
      for sc in c.allowed_oauth_scopes : !strcontains(sc, "/") || contains(flatten([
        for r in var.resource_servers : [for s in r.scope : "${r.identifier}/${s.scope_name}"]
      ]), sc)
    ]]))
    error_message = "Every <identifier>/<scope_name> in clients[*].allowed_oauth_scopes must be a scope declared in resource_servers."
  }
}
