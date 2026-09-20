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
  description = "Create the GuardDuty detector and everything attached to it"
  default     = true
}

##############################################
# Protection Plans
##############################################

variable "enable_s3_protection" {
  type        = bool
  description = "Enable the S3_DATA_EVENTS protection plan"
  default     = true
}

variable "enable_kubernetes_protection" {
  type        = bool
  description = "Enable the EKS_AUDIT_LOGS protection plan"
  default     = true
}

variable "enable_malware_protection" {
  type        = bool
  description = "Enable the EBS_MALWARE_PROTECTION protection plan"
  default     = true
}

variable "finding_publishing_frequency" {
  type        = string
  description = "How often findings are published to EventBridge and other members"
  default     = "FIFTEEN_MINUTES"

  validation {
    condition     = contains(["FIFTEEN_MINUTES", "ONE_HOUR", "SIX_HOURS"], var.finding_publishing_frequency)
    error_message = "finding_publishing_frequency must be FIFTEEN_MINUTES, ONE_HOUR or SIX_HOURS."
  }
}

##############################################
# Auto-archive Filters
##############################################

variable "auto_archive_filter" {
  type = list(object({
    severity = number
    criteria = map(list(string))
  }))
  description = "Filters that archive matching findings. `criteria` maps a GuardDuty finding field (e.g. `type`) to the values it must equal."
  default     = []

  validation {
    condition     = alltrue([for f in var.auto_archive_filter : f.severity >= 1 && f.severity <= 8])
    error_message = "Each auto_archive_filter severity must be between 1 and 8."
  }

  validation {
    condition     = alltrue([for f in var.auto_archive_filter : length(f.criteria) > 0])
    error_message = "Each auto_archive_filter must set at least one criteria field; a severity-only archive rule would suppress every finding at that severity."
  }

  validation {
    condition     = length(var.auto_archive_filter) <= 100
    error_message = "GuardDuty allows at most 100 filters per detector (rank is 1-100)."
  }
}
