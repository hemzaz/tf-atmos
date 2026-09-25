variable "region" {
  type        = string
  description = "AWS region. scope = CLOUDFRONT requires this to be us-east-1"

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

variable "enabled" {
  type        = bool
  description = "Set to false to prevent the component from creating any resources"
  default     = true
}

variable "name" {
  type        = string
  description = "Short name. The web ACL and its log group are named <Environment>-<name> (the log group is aws-waf-logs-<Environment>-<name>)"

  validation {
    condition     = can(regex("^[a-z0-9-]{1,40}$", var.name))
    error_message = "name must be 1-40 characters of lowercase letters, digits or hyphens."
  }
}

variable "scope" {
  type        = string
  description = "REGIONAL (ALB, API Gateway, AppSync, ...) or CLOUDFRONT. A CLOUDFRONT web ACL must be created with region = us-east-1 regardless of where its distribution lives"

  validation {
    condition     = contains(["REGIONAL", "CLOUDFRONT"], var.scope)
    error_message = "scope must be REGIONAL or CLOUDFRONT."
  }

  validation {
    condition     = var.scope != "CLOUDFRONT" || var.region == "us-east-1"
    error_message = "scope = CLOUDFRONT requires region = us-east-1 (CloudFront web ACLs can only be created in us-east-1, even though the distribution itself is global)."
  }
}

variable "default_action" {
  type        = string
  description = "Action for requests that do not match any rule: allow or block"
  default     = "allow"

  validation {
    condition     = contains(["allow", "block"], var.default_action)
    error_message = "default_action must be allow or block."
  }
}

# ---------------------------------------------------------------------------
# Association. A REGIONAL web ACL is attached to one or more resources via
# aws_wafv2_web_acl_association. A CLOUDFRONT web ACL is instead referenced
# directly by the distribution's web_acl_id -- AWS rejects an association
# resource for a CLOUDFRONT-scope ACL -- so this input only makes sense, and
# is only accepted, for scope = REGIONAL.
# ---------------------------------------------------------------------------

variable "association_resource_arns" {
  type        = list(string)
  description = "ARNs to associate this web ACL with (e.g. an ALB ARN or an API Gateway stage ARN). REGIONAL only; must be empty for scope = CLOUDFRONT"
  default     = []
  nullable    = false

  validation {
    condition     = var.scope == "REGIONAL" || length(var.association_resource_arns) == 0
    error_message = "association_resource_arns is only valid for scope = REGIONAL. A CLOUDFRONT web ACL is attached by setting the distribution's web_acl_id to this component's arn output, not via association."
  }
}

# ---------------------------------------------------------------------------
# Rules, as Cloud Posse inputs (cloudposse-terraform-components/aws-waf,
# wrapping cloudposse/terraform-aws-waf).
# ---------------------------------------------------------------------------

variable "managed_rule_group_statement_rules" {
  type = list(object({
    name            = string
    priority        = number
    vendor_name     = optional(string, "AWS")
    override_action = optional(string, "none")
    excluded_rules  = optional(list(string), [])
  }))
  description = "AWS (or AWS Marketplace) managed rule groups, e.g. AWSManagedRulesCommonRuleSet"
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for r in var.managed_rule_group_statement_rules : contains(["none", "count"], r.override_action)])
    error_message = "override_action must be none or count."
  }
}

variable "rate_based_statement_rules" {
  type = list(object({
    name               = string
    priority           = number
    limit              = number
    aggregate_key_type = optional(string, "IP")
    action             = optional(string, "block")
  }))
  description = "Rate-limiting rules (requests per 5-minute window per aggregation key)"
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for r in var.rate_based_statement_rules : contains(["allow", "block", "count"], r.action)])
    error_message = "action must be allow, block or count."
  }

  validation {
    condition     = alltrue([for r in var.rate_based_statement_rules : r.limit >= 100 && r.limit <= 2000000000])
    error_message = "limit must be between 100 and 2,000,000,000."
  }
}

variable "byte_match_statement_rules" {
  type = list(object({
    name                         = string
    priority                     = number
    action                       = optional(string, "block")
    search_string                = string
    positional_constraint        = string
    header_name                  = optional(string) # single_header match; omit for a uri_path match
    text_transformation_priority = optional(number, 0)
    text_transformation_type     = optional(string, "NONE")
  }))
  description = "Byte-match rules, e.g. blocking a request header value. Matches on the named request header (single_header) when header_name is set, otherwise on the URI path"
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for r in var.byte_match_statement_rules : contains(["allow", "block", "count"], r.action)])
    error_message = "action must be allow, block or count."
  }

  validation {
    condition     = alltrue([for r in var.byte_match_statement_rules : contains(["EXACTLY", "STARTS_WITH", "ENDS_WITH", "CONTAINS", "CONTAINS_WORD"], r.positional_constraint)])
    error_message = "positional_constraint must be one of EXACTLY, STARTS_WITH, ENDS_WITH, CONTAINS, CONTAINS_WORD."
  }

  # WAFv2 requires every rule in a web ACL to have a unique priority across
  # all rule types combined, not just within each list. This validation is
  # attached here (rather than as a free-standing check) so it must mention
  # var.byte_match_statement_rules, which Terraform requires of every
  # variable validation.
  validation {
    condition = length(distinct(concat(
      [for r in var.managed_rule_group_statement_rules : r.priority],
      [for r in var.rate_based_statement_rules : r.priority],
      [for r in var.byte_match_statement_rules : r.priority],
    ))) == length(var.managed_rule_group_statement_rules) + length(var.rate_based_statement_rules) + length(var.byte_match_statement_rules)
    error_message = "Rule priorities must be unique across managed_rule_group_statement_rules, rate_based_statement_rules and byte_match_statement_rules."
  }
}

# ---------------------------------------------------------------------------
# Visibility and logging.
# ---------------------------------------------------------------------------

variable "cloudwatch_metrics_enabled" {
  type        = bool
  description = "Enable CloudWatch metrics for the web ACL and every rule"
  default     = true
}

variable "sampled_requests_enabled" {
  type        = bool
  description = "Store a sample of the requests that match each rule"
  default     = true
}

variable "metric_name" {
  type        = string
  description = "CloudWatch metric name for the web ACL itself. Defaults to <Environment>-<name>"
  default     = ""
}

variable "enable_logging" {
  type        = bool
  description = "Create a CloudWatch log group (named aws-waf-logs-<Environment>-<name>, as WAFv2 requires) and a logging configuration for the web ACL"
  default     = true
}

variable "log_group_retention_days" {
  type        = number
  description = "CloudWatch log group retention, in days"
  default     = 365

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_group_retention_days)
    error_message = "log_group_retention_days must be a CloudWatch Logs retention value (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288 or 3653)."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "KMS key ARN to encrypt the log group with. Leave unset for the CloudFront (us-east-1) scope: KMS keys are regional, so a key in this stack's usual region cannot encrypt a us-east-1 log group"
  default     = null
  nullable    = true

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.kms_key_arn))
    error_message = "kms_key_arn must be null or a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>)."
  }
}
