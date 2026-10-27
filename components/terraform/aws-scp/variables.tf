variable "region" {
  type        = string
  description = "AWS Region"
}

variable "policy_name" {
  type        = string
  description = "The name of the Service Control Policy. Defaults to module.this.id"
  default     = null
}

variable "policy_description" {
  type        = string
  description = "Description of the SCP"
  default     = "Service Control Policy managed by Terraform"
}

variable "policy_content" {
  type        = string
  description = "The JSON policy document for the SCP. If not provided, policy_statements will be used to generate the policy."
  default     = null
}

variable "policy_statements" {
  type = list(object({
    sid           = optional(string)
    effect        = string
    actions       = optional(list(string), [])
    not_actions   = optional(list(string), [])
    resources     = optional(list(string), [])
    not_resources = optional(list(string), [])
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })), [])
  }))
  description = "List of policy statements to generate the SCP. Alternative to policy_content. Each statement must specify either 'actions' or 'not_actions', but not both, and either 'resources' or 'not_resources', but not both."
  default     = []

  validation {
    condition = alltrue([
      for stmt in var.policy_statements : stmt.effect != null
    ])
    error_message = "Each entry in policy_statements must not be null. This can happen when an !include path is incorrect or the referenced file does not exist."
  }

  validation {
    condition = alltrue([
      for stmt in var.policy_statements :
      (length(stmt.actions) > 0) != (length(stmt.not_actions) > 0)
    ])
    error_message = "Each policy statement must specify either 'actions' or 'not_actions', but not both."
  }

  validation {
    condition = alltrue([
      for stmt in var.policy_statements :
      (length(coalesce(stmt.resources, [])) > 0) != (length(coalesce(stmt.not_resources, [])) > 0)
    ])
    error_message = "Each policy statement must specify either 'resources' or 'not_resources', but not both."
  }
}

variable "target_ids" {
  type        = list(string)
  description = "The IDs of the organization roots, OUs, or accounts to attach the SCP to"
  default     = []

  validation {
    condition     = alltrue([for id in var.target_ids : id != ""])
    error_message = "All target IDs must be non-empty strings. This can happen when a !terraform.output reference resolves to null."
  }

  validation {
    condition     = length(var.target_ids) == length(toset(var.target_ids))
    error_message = "Target IDs must be unique. Duplicate entries are not allowed."
  }

  validation {
    condition     = alltrue([for id in var.target_ids : can(regex("^(r-|ou-|[0-9]{12}$)", id))])
    error_message = "Each target ID must be an organization root (r-), OU (ou-), or 12-digit account ID."
  }
}

variable "skip_destroy" {
  type        = bool
  description = "If true, the policy will be detached from the target but not destroyed when removed from Terraform"
  default     = false
}

variable "attach_to_target" {
  type        = bool
  description = "Whether to attach the SCP to a target. Set to false to create the policy without attaching it."
  default     = true
}
