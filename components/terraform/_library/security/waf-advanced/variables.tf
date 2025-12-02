##############################################
# Required Variables
##############################################

variable "name_prefix" {
  type        = string
  description = <<-EOT
    Prefix to use for all resource names. This should follow the pattern: tenant-environment-stage.
    Example: "acme-prod-web" or "fnx-dev-api"
  EOT

  validation {
    condition     = length(var.name_prefix) > 0 && length(var.name_prefix) <= 50
    error_message = "The name_prefix must be between 1 and 50 characters."
  }
}

variable "scope" {
  type        = string
  description = <<-EOT
    The scope of the WAF deployment. Valid values are:
    - "CLOUDFRONT" - For use with CloudFront distributions (must be in us-east-1)
    - "REGIONAL" - For use with ALB, API Gateway, AppSync, or Cognito
  EOT
  default     = "REGIONAL"

  validation {
    condition     = contains(["CLOUDFRONT", "REGIONAL"], var.scope)
    error_message = "The scope must be either 'CLOUDFRONT' or 'REGIONAL'."
  }
}

##############################################
# Managed Rule Groups
##############################################

variable "enable_aws_managed_rules" {
  type        = bool
  description = <<-EOT
    Enable AWS Managed Rule Groups. These are pre-configured rule sets maintained by AWS
    that provide protection against common threats. Recommended for production use.
    Default: true
  EOT
  default     = true
}

variable "enable_core_rule_set" {
  type        = bool
  description = <<-EOT
    Enable AWS Managed Core Rule Set (CRS). Provides protection against OWASP Top 10 vulnerabilities
    including SQL injection, XSS, and other common attacks. This is the foundational managed rule set.
    Cost: Included with base WAF pricing.
    Default: true
  EOT
  default     = true
}

variable "enable_known_bad_inputs" {
  type        = bool
  description = <<-EOT
    Enable AWS Managed Known Bad Inputs rule set. Blocks requests with patterns known to be exploited
    in vulnerabilities or that are generally anomalous. Reduces false positives compared to CRS.
    Cost: Included with base WAF pricing.
    Default: true
  EOT
  default     = true
}

variable "enable_sql_database_protection" {
  type        = bool
  description = <<-EOT
    Enable AWS Managed SQL Database protection rule set. Provides enhanced protection against
    SQL injection attacks beyond the Core Rule Set.
    Cost: Included with base WAF pricing.
    Default: false (use CRS unless you need extra SQL injection protection)
  EOT
  default     = false
}

variable "enable_linux_os_protection" {
  type        = bool
  description = <<-EOT
    Enable AWS Managed Linux Operating System protection. Blocks requests containing exploits
    targeting Linux-specific vulnerabilities. Enable if your backend runs on Linux.
    Cost: Included with base WAF pricing.
    Default: false
  EOT
  default     = false
}

variable "enable_unix_os_protection" {
  type        = bool
  description = <<-EOT
    Enable AWS Managed Unix Operating System protection. Blocks requests containing exploits
    targeting Unix-specific vulnerabilities. Enable if your backend runs on Unix systems.
    Cost: Included with base WAF pricing.
    Default: false
  EOT
  default     = false
}

variable "enable_windows_os_protection" {
  type        = bool
  description = <<-EOT
    Enable AWS Managed Windows Operating System protection. Blocks requests containing exploits
    targeting Windows-specific vulnerabilities. Enable if your backend runs on Windows.
    Cost: Included with base WAF pricing.
    Default: false
  EOT
  default     = false
}

variable "enable_php_application_protection" {
  type        = bool
  description = <<-EOT
    Enable AWS Managed PHP Application protection. Blocks requests with PHP-specific exploits.
    Enable if your application is built with PHP.
    Cost: Included with base WAF pricing.
    Default: false
  EOT
  default     = false
}

variable "enable_wordpress_protection" {
  type        = bool
  description = <<-EOT
    Enable AWS Managed WordPress Application protection. Blocks requests targeting WordPress
    vulnerabilities. Enable if you're running WordPress.
    Cost: Included with base WAF pricing.
    Default: false
  EOT
  default     = false
}

##############################################
# Bot Control
##############################################

variable "enable_bot_control" {
  type        = bool
  description = <<-EOT
    Enable AWS Managed Bot Control. Provides intelligent bot detection and mitigation.
    This is a paid add-on with additional per-request charges.
    Cost: $10/month + $1 per 1M requests analyzed.
    Default: false (due to cost)
  EOT
  default     = false
}

variable "bot_control_level" {
  type        = string
  description = <<-EOT
    Bot Control protection level when bot control is enabled:
    - "COMMON" - Basic bot protection (lower cost)
    - "TARGETED" - Enhanced bot protection with ML-based detection (higher cost)
    Default: "COMMON"
  EOT
  default     = "COMMON"

  validation {
    condition     = contains(["COMMON", "TARGETED"], var.bot_control_level)
    error_message = "The bot_control_level must be either 'COMMON' or 'TARGETED'."
  }
}

##############################################
# Rate Limiting
##############################################

variable "enable_rate_limiting" {
  type        = bool
  description = <<-EOT
    Enable rate limiting rules to prevent abuse and DDoS attacks.
    Limits the number of requests from a single IP address within a time window.
    Default: true
  EOT
  default     = true
}

variable "rate_limit_per_ip" {
  type        = number
  description = <<-EOT
    Maximum number of requests allowed from a single IP address within the rate_limit_window.
    Requests exceeding this limit will be blocked. Common values:
    - 2000 = ~33 requests per minute (lenient)
    - 1000 = ~16 requests per minute (moderate)
    - 500 = ~8 requests per minute (strict)
    Default: 2000
  EOT
  default     = 2000

  validation {
    condition     = var.rate_limit_per_ip >= 100 && var.rate_limit_per_ip <= 20000000
    error_message = "The rate_limit_per_ip must be between 100 and 20,000,000."
  }
}

variable "rate_limit_window" {
  type        = number
  description = <<-EOT
    Time window in seconds for rate limiting. Valid values: 60, 120, 300, 600.
    - 60 = 1 minute
    - 120 = 2 minutes
    - 300 = 5 minutes (recommended)
    - 600 = 10 minutes
    Default: 300
  EOT
  default     = 300

  validation {
    condition     = contains([60, 120, 300, 600], var.rate_limit_window)
    error_message = "The rate_limit_window must be one of: 60, 120, 300, or 600 seconds."
  }
}

##############################################
# IP Reputation and Geo-Blocking
##############################################

variable "enable_ip_reputation" {
  type        = bool
  description = <<-EOT
    Enable AWS Managed IP Reputation list. Blocks requests from IP addresses known for malicious activity.
    Cost: Included with base WAF pricing.
    Default: true
  EOT
  default     = true
}

variable "enable_anonymous_ip_list" {
  type        = bool
  description = <<-EOT
    Enable AWS Managed Anonymous IP list. Blocks requests from VPNs, proxies, Tor exit nodes,
    and hosting providers that are commonly used to hide identity.
    Cost: Included with base WAF pricing.
    Default: false (may block legitimate VPN users)
  EOT
  default     = false
}

variable "enable_geo_blocking" {
  type        = bool
  description = <<-EOT
    Enable geographic blocking based on the geo_block_countries list.
    Useful for blocking traffic from countries where you don't operate.
    Default: false
  EOT
  default     = false
}

variable "geo_block_countries" {
  type        = list(string)
  description = <<-EOT
    List of ISO 3166-1 alpha-2 country codes to block when geo_blocking is enabled.
    Examples: ["CN", "RU", "KP"] blocks China, Russia, and North Korea.
    See: https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2
    Default: []
  EOT
  default     = []

  validation {
    condition     = alltrue([for code in var.geo_block_countries : length(code) == 2])
    error_message = "All country codes must be 2-character ISO 3166-1 alpha-2 codes."
  }
}

variable "geo_allow_countries" {
  type        = list(string)
  description = <<-EOT
    List of ISO 3166-1 alpha-2 country codes to explicitly allow. When specified,
    all other countries will be blocked. Mutually exclusive with geo_block_countries.
    Example: ["US", "CA", "GB"] allows only USA, Canada, and UK.
    Default: [] (no allow list)
  EOT
  default     = []

  validation {
    condition     = alltrue([for code in var.geo_allow_countries : length(code) == 2])
    error_message = "All country codes must be 2-character ISO 3166-1 alpha-2 codes."
  }
}

##############################################
# Custom Rules
##############################################

variable "custom_rules" {
  type = list(object({
    name     = string
    priority = number
    action   = string
    statement = object({
      byte_match_statement = optional(object({
        positional_constraint = string
        search_string         = string
        field_to_match = object({
          uri_path = optional(bool)
          body     = optional(bool)
        })
        text_transformation = list(string)
      }))
      size_constraint_statement = optional(object({
        comparison_operator = string
        size                = number
        field_to_match = object({
          uri_path = optional(bool)
          body     = optional(bool)
        })
        text_transformation = list(string)
      }))
    })
  }))
  description = <<-EOT
    List of custom WAF rules to add to the Web ACL. Each rule must have a unique priority.
    Lower priority numbers are evaluated first. Custom rules are evaluated after managed rules.
    Example:
    [
      {
        name     = "block-admin-path"
        priority = 100
        action   = "BLOCK"
        statement = {
          byte_match_statement = {
            positional_constraint = "STARTS_WITH"
            search_string        = "/admin"
            field_to_match = {
              uri_path = true
            }
            text_transformation = ["LOWERCASE"]
          }
        }
      }
    ]
    Default: []
  EOT
  default     = []
}

##############################################
# Logging Configuration
##############################################

variable "enable_logging" {
  type        = bool
  description = <<-EOT
    Enable logging for the WAF. Logs can be sent to S3, CloudWatch Logs, or Kinesis Data Firehose.
    Logging helps with debugging, compliance, and threat analysis.
    Cost: S3 storage or CloudWatch log ingestion charges apply.
    Default: true
  EOT
  default     = true
}

variable "log_destination_type" {
  type        = string
  description = <<-EOT
    Destination type for WAF logs:
    - "s3" - Log to S3 bucket (most cost-effective for long-term storage)
    - "cloudwatch" - Log to CloudWatch Logs (better for real-time monitoring)
    - "kinesis" - Log to Kinesis Data Firehose (for streaming analysis)
    Default: "s3"
  EOT
  default     = "s3"

  validation {
    condition     = contains(["s3", "cloudwatch", "kinesis"], var.log_destination_type)
    error_message = "The log_destination_type must be 's3', 'cloudwatch', or 'kinesis'."
  }
}

variable "log_destination_arn" {
  type        = string
  description = <<-EOT
    ARN of the logging destination (S3 bucket, CloudWatch log group, or Kinesis Firehose).
    If not provided and logging is enabled, a new S3 bucket or CloudWatch log group will be created.
    Note: S3 bucket name must start with 'aws-waf-logs-'
    Default: "" (auto-create)
  EOT
  default     = ""
}

variable "log_retention_days" {
  type        = number
  description = <<-EOT
    Number of days to retain WAF logs. Applies to CloudWatch Logs and S3 lifecycle policy.
    Common values: 7, 14, 30, 60, 90, 180, 365
    Default: 30
  EOT
  default     = 30

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "The log_retention_days must be a valid CloudWatch Logs retention period."
  }
}

##############################################
# Default Action
##############################################

variable "default_action" {
  type        = string
  description = <<-EOT
    Default action for requests that don't match any rules:
    - "ALLOW" - Allow all requests by default (recommended for most use cases)
    - "BLOCK" - Block all requests by default (use with caution)
    Default: "ALLOW"
  EOT
  default     = "ALLOW"

  validation {
    condition     = contains(["ALLOW", "BLOCK"], var.default_action)
    error_message = "The default_action must be either 'ALLOW' or 'BLOCK'."
  }
}

##############################################
# Resource Association
##############################################

variable "resource_arns" {
  type        = list(string)
  description = <<-EOT
    List of AWS resource ARNs to associate with this Web ACL.
    - For REGIONAL scope: ALB, API Gateway, AppSync, or Cognito User Pool ARNs
    - For CLOUDFRONT scope: CloudFront distribution ARNs
    Example: ["arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/my-alb/abc123"]
    Default: [] (no automatic association)
  EOT
  default     = []

  validation {
    condition     = alltrue([for arn in var.resource_arns : can(regex("^arn:aws:", arn))])
    error_message = "All resource ARNs must be valid AWS ARNs starting with 'arn:aws:'."
  }
}

##############################################
# Tagging
##############################################

variable "tags" {
  type        = map(string)
  description = <<-EOT
    Additional tags to apply to all WAF resources. These tags will be merged with default tags.
    Example:
      {
        Environment = "production"
        CostCenter  = "security"
        Compliance  = "pci-dss"
      }
    Default: {}
  EOT
  default     = {}
}
