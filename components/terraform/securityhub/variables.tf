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

variable "standards" {
  type        = list(string)
  description = "Standards to subscribe to, as `<name>/v/<version>` (e.g. `pci-dss/v/3.2.1`). The region and partition are added when building the ARN."
  default     = []

  validation {
    condition     = alltrue([for standard in var.standards : can(regex("^[a-z0-9]+(-[a-z0-9]+)*/v/[0-9]+\\.[0-9]+\\.[0-9]+$", standard))])
    error_message = "Each standard must be a short path of the form <name>/v/<major>.<minor>.<patch>, not a full ARN."
  }
}
