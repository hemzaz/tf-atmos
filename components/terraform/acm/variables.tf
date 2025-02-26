variable "region" {
  type        = string
  description = "AWS region"
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
}

variable "zone_id" {
  type        = string
  description = "Route53 zone ID to create validation records in"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
  default     = {}
}