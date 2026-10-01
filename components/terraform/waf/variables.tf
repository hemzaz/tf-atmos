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

  # A null entry here almost always means an upstream !terraform.state read
  # resolved to null -- e.g. apigateway's rest_api_stage_arn is null when
  # api_type = "HTTP" (HTTP APIs have no association-eligible stage ARN; WAF
  # can only associate with a REST API stage, an ALB or a CloudFront
  # distribution). Without this check, a null element reaches
  # aws_wafv2_web_acl_association's for_each (via toset()) and fails with an
  # opaque "set includes a null element" provider/core error instead of
  # naming the actual cause.
  validation {
    condition     = alltrue([for arn in var.association_resource_arns : arn != null])
    error_message = "association_resource_arns must not contain a null entry. This usually means an upstream output was null -- e.g. apigateway's rest_api_stage_arn is null when api_type = \"HTTP\" (an HTTP API has no stage ARN WAF can associate with). Fix the upstream api_type, or remove that entry from association_resource_arns."
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
    # AWS's rate_based_statement also allows FORWARDED_IP and CUSTOM_KEYS, but
    # those require a forwarded_ip_config or custom_key block respectively,
    # which this component's rate_based_statement rendering (main.tf) never
    # emits. Either value would pass plan and fail at apply, so restrict to
    # the two aggregate key types this component actually supports until
    # forwarded_ip_config/custom_key inputs are added.
    condition     = alltrue([for r in var.rate_based_statement_rules : contains(["IP", "CONSTANT"], r.aggregate_key_type)])
    error_message = "aggregate_key_type must be IP or CONSTANT: FORWARDED_IP and CUSTOM_KEYS require forwarded_ip_config/custom_key blocks this component does not render."
  }

  validation {
    condition     = alltrue([for r in var.rate_based_statement_rules : r.limit >= 10 && r.limit <= 2000000000])
    error_message = "limit must be between 10 and 2,000,000,000."
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

variable "manage_log_resource_policy" {
  type        = bool
  description = "Create an explicit, account-scoped CloudWatch Logs resource policy granting WAF log delivery to this log group. Each instance that sets this true consumes one of the account/region's 10 CloudWatch Logs resource-policy slots (see main.tf's aws_cloudwatch_log_resource_policy comment). Set to false on an additional instance in a region approaching that quota to fall back to the implicit AWSWAF-LOGS policy PutLoggingConfiguration manages on its own. Ignored when enable_logging is false"
  default     = true
}

variable "redacted_fields" {
  # Cloud Posse's input name and type (cloudposse/terraform-aws-waf). Two
  # deviations, both in main.tf/below: each field becomes its own
  # redacted_fields block (upstream renders a multi-header entry as one block,
  # which AWS rejects), and the default redacts the credential headers instead
  # of nothing.
  type = map(object({
    method        = optional(bool, false)
    uri_path      = optional(bool, false)
    query_string  = optional(bool, false)
    single_header = optional(list(string), null)
  }))
  description = "Request fields WAF keeps out of its logs, keyed by an arbitrary name. Each entry redacts the HTTP method, URI path, query string and/or the named headers. Must always redact the authorization and cookie headers; add entries (e.g. an API-key header) to extend it. Ignored when enable_logging is false"
  default = {
    authorization = { single_header = ["authorization"] }
    cookie        = { single_header = ["cookie"] }
  }
  nullable = false

  # A caller replacing the map (a Terraform default is replaced, not merged)
  # must not silently start logging bearer tokens or session cookies.
  validation {
    condition = alltrue([
      for h in ["authorization", "cookie"] : contains(flatten([
        for v in values(var.redacted_fields) : [for n in coalesce(v.single_header, []) : lower(n)]
      ]), h)
    ])
    error_message = "redacted_fields must redact the authorization and cookie headers (single_header), so credentials never reach the WAF logs. Add entries to extend it; do not drop these two."
  }

  validation {
    condition     = alltrue(flatten([for v in values(var.redacted_fields) : [for n in coalesce(v.single_header, []) : can(regex("^[A-Za-z0-9_-]{1,64}$", n))]]))
    error_message = "redacted_fields[*].single_header entries must be header names: 1-64 letters, digits, hyphens or underscores."
  }

  # Counted as local.redacted_fields renders them: one field per method,
  # query_string, uri_path and header, a field named twice counted once.
  validation {
    condition = length(distinct(flatten([
      for v in values(var.redacted_fields) : concat(
        v.method ? ["method"] : [],
        v.query_string ? ["query_string"] : [],
        v.uri_path ? ["uri_path"] : [],
        [for h in coalesce(v.single_header, []) : "single_header:${lower(h)}"],
      )
    ]))) <= 100
    error_message = "redacted_fields may redact at most 100 fields (the WAF logging configuration limit); each method, query_string, uri_path and header counts as one."
  }
}

variable "logging_filter" {
  # Cloud Posse's input name and type (cloudposse/terraform-aws-waf).
  type = object({
    default_behavior = string
    filter = list(object({
      behavior    = string
      requirement = string
      condition = list(object({
        action_condition = optional(object({
          action = string
        }), null)
        label_name_condition = optional(object({
          label_name = string
        }), null)
      }))
    }))
  })
  description = "Which requests WAF keeps in its logs (by rule action or label); null logs every request. Ignored when enable_logging is false"
  default     = null

  validation {
    condition = var.logging_filter == null || (
      contains(["KEEP", "DROP"], var.logging_filter.default_behavior) &&
      alltrue([for f in var.logging_filter.filter : contains(["KEEP", "DROP"], f.behavior) && contains(["MEETS_ALL", "MEETS_ANY"], f.requirement)])
    )
    error_message = "logging_filter.default_behavior and filter[*].behavior must be KEEP or DROP; filter[*].requirement must be MEETS_ALL or MEETS_ANY."
  }
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
  description = "KMS key ARN to encrypt the log group with. KMS keys are regional: for the CloudFront (us-east-1) scope it must be a us-east-1 key, so a stack in us-east-1 can pass its own key and a stack elsewhere leaves it unset"
  default     = null
  nullable    = true

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.kms_key_arn))
    error_message = "kms_key_arn must be null or a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>)."
  }
}
