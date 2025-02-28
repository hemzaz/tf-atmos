variable "region" {
  type        = string
  description = "AWS region"
  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "The region must be a valid AWS region name (e.g., us-east-1, eu-west-1)."
  }
}

variable "dns_domains" {
  type = map(object({
    domain_name               = string
    subject_alternative_names = optional(list(string), [])
    validation_method         = optional(string, "DNS")
    wait_for_validation       = optional(bool, true)
    tags                      = optional(map(string), {})
  }))
  description = "Map of domain configurations to create ACM certificates for"
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.dns_domains : can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]\\.[a-zA-Z]{2,}$", v.domain_name))
    ])
    error_message = "All domain names must be valid DNS domains (e.g., example.com)."
  }

  validation {
    condition = alltrue([
      for k, v in var.dns_domains : v.validation_method == "DNS" || v.validation_method == "EMAIL"
    ])
    error_message = "The validation_method must be either DNS or EMAIL."
  }

  validation {
    condition = alltrue([
      for k, v in var.dns_domains : alltrue([
        for san in coalesce(v.subject_alternative_names, []) : can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]\\.[a-zA-Z]{2,}$", san))
      ])
    ])
    error_message = "All subject alternative names must be valid DNS domains."
  }
}

variable "zone_id" {
  type        = string
  description = "Route53 zone ID to create validation records in"

  validation {
    condition     = can(regex("^Z[A-Z0-9]{1,32}$", var.zone_id))
    error_message = "The zone_id must be a valid Route53 Zone ID (e.g., Z00000000000000000000)."
  }
}

variable "cert_transparency_logging" {
  type        = bool
  description = "Whether to enable certificate transparency logging"
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
  default     = {}

  validation {
    condition     = contains(keys(var.tags), "Environment")
    error_message = "The tags map must contain an 'Environment' key."
  }
}