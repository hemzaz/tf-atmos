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
  description = "Tags to apply to all resources"

  validation {
    condition     = trimspace(lookup(var.tags, "Environment", "")) != ""
    error_message = "tags must include a non-empty Environment value."
  }
}

# GuardDuty and Security Hub are owned by the guardduty and securityhub
# components. Stacks pass their outputs in with !terraform.state; null turns
# the matching finding route off.
variable "guardduty_detector_id" {
  type        = string
  description = "ID of the GuardDuty detector owned by the guardduty component (its `detector_id` output). Null disables GuardDuty finding routing."
  default     = null

  validation {
    condition     = var.guardduty_detector_id == null || can(regex("^[a-z0-9]{1,300}$", var.guardduty_detector_id))
    error_message = "guardduty_detector_id must be a GuardDuty detector ID (lowercase letters and digits), or null."
  }
}

variable "require_guardduty_route" {
  type        = bool
  description = "Fail the plan when guardduty_detector_id is null, instead of silently planning without the GuardDuty finding route (e.g. guardduty/main not applied yet)"
  default     = true
}

variable "securityhub_account_arn" {
  type        = string
  description = "ARN of the Security Hub hub owned by the securityhub component (its `account_arn` output). Null disables Security Hub finding routing."
  default     = null

  validation {
    condition     = var.securityhub_account_arn == null || can(regex("^arn:aws[a-z-]*:securityhub:[a-z0-9-]+:[0-9]{12}:hub/default$", var.securityhub_account_arn))
    error_message = "securityhub_account_arn must be a Security Hub hub ARN (arn:aws:securityhub:<region>:<account>:hub/default), or null."
  }
}

variable "require_securityhub_route" {
  type        = bool
  description = "Fail the plan when securityhub_account_arn is null, instead of silently planning without the Security Hub finding route (e.g. securityhub/main not applied yet)"
  default     = true
}

variable "cloudtrail_log_group_name" {
  type        = string
  description = "CloudWatch log group the account trail delivers to (the cloudtrail component's `cloudtrail_logs_log_group_name` output). The CIS metric filters and their four CloudTrailMetrics alarms are created on it"
  default     = null

  validation {
    condition     = var.cloudtrail_log_group_name == null || can(regex("^[.\\-_/#A-Za-z0-9]{1,512}$", var.cloudtrail_log_group_name))
    error_message = "cloudtrail_log_group_name must be a CloudWatch log group name, or null."
  }
}

variable "require_cloudtrail_route" {
  type        = bool
  description = "Fail the plan when cloudtrail_log_group_name is null, instead of silently planning without the CIS CloudTrail metric filters and alarms (e.g. cloudtrail/main not applied yet)"
  default     = true
}

# Inspector Variables
variable "enable_inspector" {
  type        = bool
  description = "Enable AWS Inspector V2"
  default     = true
}

variable "inspector_resource_types" {
  type        = list(string)
  description = "Resource types to scan with Inspector"
  default     = ["EC2", "ECR", "LAMBDA"]
}

# Alert Variables
variable "security_email_subscriptions" {
  type        = list(string)
  description = "Email addresses for security alert notifications"
  default     = []
}

variable "enable_alert_enrichment" {
  type        = bool
  description = "Enable Lambda function for alert enrichment and routing"
  default     = false
}

# Not ephemeral: the value is passed to a Lambda environment variable, which is not a
# write-only argument and is stored in state.
variable "slack_webhook_url" {
  type        = string
  description = "Slack webhook URL for security alerts"
  default     = null
  sensitive   = true
}

# Not ephemeral: the value is passed to a Lambda environment variable, which is not a
# write-only argument and is stored in state.
variable "pagerduty_integration_key" {
  type        = string
  description = "PagerDuty integration key for security alerts"
  default     = null
  sensitive   = true
}

# Encryption Variables
variable "kms_key_id" {
  type        = string
  description = "KMS key ARN (kms/main's key_arn) encrypting the alert SNS topic and the enrichment log group. Its key policy must let events.amazonaws.com and cloudwatch.amazonaws.com use it (kms allow_eventbridge and allow_cloudwatch_alarms). Null leaves the topic unencrypted"
  default     = null

  validation {
    condition     = var.kms_key_id == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[a-zA-Z0-9-]+$", var.kms_key_id))
    error_message = "kms_key_id must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>), or null."
  }
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch log retention in days"
  default     = 90
}

# Alarm Thresholds
variable "unauthorized_api_threshold" {
  type        = number
  description = "Threshold for unauthorized API calls alarm"
  default     = 5
}

variable "iam_changes_threshold" {
  type        = number
  description = "Threshold for IAM policy changes alarm"
  default     = 1
}

variable "sg_changes_threshold" {
  type        = number
  description = "Threshold for security group changes alarm"
  default     = 5
}
