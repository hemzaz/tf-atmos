variable "region" {
  type        = string
  description = "AWS region"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "The region must be a valid AWS region name (e.g., us-east-1, eu-west-1)."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources; must include Environment (used in resource names)"

  validation {
    condition     = trimspace(lookup(var.tags, "Environment", "")) != ""
    error_message = "tags must include a non-empty Environment value."
  }
}

variable "enable" {
  type        = bool
  description = "Enable Security Hub in this account and region"
  default     = true
}

variable "enable_default_standards" {
  type        = bool
  description = "Let Security Hub subscribe its default standards (AWS Foundational Security Best Practices v1.0.0 and CIS AWS Foundations Benchmark v1.2.0). Those two are then skipped in `standards` to avoid a duplicate subscription."
  default     = true
}

variable "disabled_security_controls" {
  type        = map(list(string))
  description = "Security controls to disable, by standard (`<name>/v/<version>`, a subscribed one) to the control IDs in it (e.g. IAM.1). For the controls that check global resources outside the region that records them (AWS Security Hub guidance)"
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for id in flatten(values(var.disabled_security_controls)) : can(regex("^[A-Za-z0-9]+\\.[0-9]+$", id))])
    error_message = "disabled_security_controls values must be security control IDs such as IAM.1."
  }

  # Only a subscribed standard has associations to disable.
  validation {
    condition = alltrue([
      for standard in keys(var.disabled_security_controls) :
      contains(var.standards, standard) || (var.enable_default_standards && contains(["aws-foundational-security-best-practices/v/1.0.0", "cis-aws-foundations-benchmark/v/1.2.0"], standard))
    ])
    error_message = "Every disabled_security_controls key must be a subscribed standard: one of standards, or a default standard with enable_default_standards."
  }
}

variable "disabled_security_controls_reason" {
  type        = string
  description = "updated_reason recorded on each disabled_security_controls association"
  default     = "Checks a global resource; evaluated in the region that records global resources"
}

variable "standards" {
  type        = list(string)
  description = "Standards to subscribe to, as `<name>/v/<version>` (e.g. `pci-dss/v/3.2.1`). The region and partition are added when building the ARN."
  default     = []

  validation {
    condition     = alltrue([for standard in var.standards : can(regex("^[a-z0-9]+(-[a-z0-9]+)*/v/[0-9]+\\.[0-9]+\\.[0-9]+$", standard))])
    error_message = "Each standard must be a short path of the form <name>/v/<major>.<minor>.<patch>, not a full ARN."
  }
}
