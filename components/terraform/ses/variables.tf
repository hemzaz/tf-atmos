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
  description = "Tags to apply to resources; must include Environment"

  validation {
    condition     = trimspace(lookup(var.tags, "Environment", "")) != ""
    error_message = "tags must include a non-empty Environment value."
  }
}

variable "enabled" {
  type        = bool
  description = "Set to false to prevent the component from creating any resources"
  default     = true
}

variable "domain" {
  type        = string
  description = "Domain to verify as an SES email identity (Cloud Posse's domain_template, rendered)"

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", var.domain))
    error_message = "domain must be a lowercase DNS domain name (e.g. example.com)."
  }
}

variable "zone_id" {
  type        = string
  description = "Route 53 public hosted zone of the domain, where the DKIM records are written (the dns component's zone_ids.<key>). Null writes nothing: publish the dkim_records output by hand"
  default     = null

  validation {
    condition     = var.zone_id == null || can(regex("^Z[A-Z0-9]{1,31}$", var.zone_id))
    error_message = "zone_id must be a Route 53 hosted zone ID (Z...)."
  }
}

# The two inputs below are Cloud Posse's aws-ses inputs, with its defaults.

variable "ses_verify_dkim" {
  type        = bool
  description = "Write the three Easy DKIM CNAME records into zone_id; SES verifies the domain through them"
  default     = true
}

variable "dkim_signing_key_length" {
  type        = string
  description = "Length of the Easy DKIM signing key"
  default     = "RSA_2048_BIT"

  validation {
    condition     = contains(["RSA_1024_BIT", "RSA_2048_BIT"], var.dkim_signing_key_length)
    error_message = "dkim_signing_key_length must be RSA_1024_BIT or RSA_2048_BIT."
  }
}

variable "dkim_record_ttl" {
  type        = number
  description = "TTL of the DKIM CNAME records, in seconds"
  default     = 1800

  validation {
    condition     = var.dkim_record_ttl >= 60 && var.dkim_record_ttl <= 172800
    error_message = "dkim_record_ttl must be between 60 and 172800."
  }
}
