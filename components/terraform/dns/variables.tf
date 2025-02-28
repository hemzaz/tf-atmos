variable "region" {
  type        = string
  description = "AWS region"
}

variable "assume_role_arn" {
  type        = string
  description = "ARN of the IAM role to assume for the main account"
  default     = null
}

variable "dns_account_assume_role_arn" {
  type        = string
  description = "ARN of the IAM role to assume in the DNS account (if using multi-account setup)"
  default     = null
}

variable "root_domain" {
  type        = string
  description = "The root domain name (e.g., example.com)"
}

variable "create_root_zone" {
  type        = bool
  description = "Whether to create the root zone (set to false if the zone already exists)"
  default     = false
}

variable "multi_account_dns_delegation" {
  type        = bool
  description = "Whether to create delegations across accounts (true if DNS managed in a separate account)"
  default     = false
}

variable "zones" {
  type = map(object({
    name                 = string
    comment              = optional(string, "Managed by Terraform")
    force_destroy        = optional(bool, false)
    delegation_set_id    = optional(string)
    enable_health_checks = optional(bool, true)
    default_ttl          = optional(number, 300)
    enable_query_logging = optional(bool, false)
    query_logging_config = optional(map(string), {})
    vpc_associations     = optional(list(string), [])
    tags                 = optional(map(string), {})
  }))
  description = "Map of Route53 zones to create"
  default     = {}
}

variable "records" {
  type = map(object({
    zone_name                        = string
    name                             = string
    type                             = string
    ttl                              = optional(number)
    records                          = optional(list(string), [])
    alias                            = optional(map(any))
    health_check_id                  = optional(string)
    set_identifier                   = optional(string)
    weighted_routing_policy          = optional(map(number))
    latency_routing_policy           = optional(map(string))
    geolocation_routing_policy       = optional(map(string))
    failover_routing_policy          = optional(map(string))
    multivalue_answer_routing_policy = optional(bool)
  }))
  description = "Map of Route53 records to create"
  default     = {}
}

variable "health_checks" {
  type = map(object({
    name               = string
    fqdn               = optional(string)
    ip_address         = optional(string)
    port               = optional(number)
    type               = string # "HTTP", "HTTPS", "HTTP_STR_MATCH", "HTTPS_STR_MATCH", "TCP", "CALCULATED"
    resource_path      = optional(string)
    search_string      = optional(string)
    request_interval   = optional(number, 30)
    failure_threshold  = optional(number, 3)
    measure_latency    = optional(bool, true)
    invert_healthcheck = optional(bool, false)
    enable_sns         = optional(bool, false)
    sns_topic_arn      = optional(string)
    regions            = optional(list(string), ["us-east-1", "us-west-1", "eu-west-1"])
    tags               = optional(map(string), {})
  }))
  description = "Map of Route53 health checks to create"
  default     = {}
}

variable "delegation_sets" {
  type = map(object({
    name           = string
    reference_name = string
  }))
  description = "Map of Route53 delegation sets"
  default     = {}
}

variable "traffic_policies" {
  type = map(object({
    name            = string
    comment         = optional(string)
    document        = string
    version_comment = optional(string)
  }))
  description = "Map of Route53 traffic policies"
  default     = {}
}

variable "vpc_dns_resolution" {
  type = map(object({
    vpc_id           = string
    vpc_region       = optional(string)
    associated_zones = list(string)
  }))
  description = "Map of VPC associations for private hosted zones"
  default     = {}
}

variable "tags" {
  type        = map(string)
  description = "Common tags to apply to all resources"
  default     = {}
}