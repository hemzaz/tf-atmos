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
    # Cloud Posse acm-request-certificate's flag: false writes no validation
    # records for this certificate (another state owns them, e.g. the primary
    # region's in a DR region). Unlike upstream, it still waits for validation.
    process_domain_validation_options = optional(bool, true)
    tags                              = optional(map(string), {})
  }))
  description = "Map of domain configurations to create ACM certificates for"
  default     = {}

  # The leading (\*\.)? admits wildcard certificates and the repeated label
  # group admits subdomains. The previous pattern allowed neither -- it matched
  # only "label.tld", so every stack's "*.example.com" was rejected and acm
  # could not plan anywhere. Garbage is still refused: "-bad.com", "example"
  # and "not_a_domain" all fail. A wildcard is only valid as the leftmost
  # label, which the anchored prefix enforces.
  validation {
    condition = alltrue([
      for k, v in var.dns_domains : can(regex("^(\\*\\.)?([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\\.)+[a-zA-Z]{2,}$", v.domain_name))
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
        for san in coalesce(v.subject_alternative_names, []) : can(regex("^(\\*\\.)?([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\\.)+[a-zA-Z]{2,}$", san))
      ])
    ])
    error_message = "All subject alternative names must be valid DNS domains."
  }
}

variable "zone_id" {
  type        = string
  description = "Route53 zone ID to create validation records in; empty only when no DNS certificate processes its validation options"
  default     = ""

  validation {
    condition     = var.zone_id == "" || can(regex("^Z[A-Z0-9]{1,32}$", var.zone_id))
    error_message = "The zone_id must be a valid Route53 Zone ID (e.g., Z00000000000000000000)."
  }

  # Records are written only for DNS certificates that process their
  # validation options; any such certificate needs the zone.
  validation {
    condition = var.zone_id != "" || alltrue([
      for k, v in var.dns_domains : v.validation_method != "DNS" || v.process_domain_validation_options == false
    ])
    error_message = "zone_id is required when a DNS-validated certificate has process_domain_validation_options = true (the default)."
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
    condition     = trimspace(lookup(var.tags, "Environment", "")) != ""
    error_message = "tags must include a non-empty Environment value."
  }
}
