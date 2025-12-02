variable "region" {
  type        = string
  description = "AWS region"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources"
}

# GuardDuty Variables
variable "enable_guardduty" {
  type        = bool
  description = "Enable GuardDuty threat detection"
  default     = true
}

variable "enable_s3_protection" {
  type        = bool
  description = "Enable GuardDuty S3 protection"
  default     = true
}

variable "enable_eks_protection" {
  type        = bool
  description = "Enable GuardDuty EKS protection"
  default     = true
}

variable "enable_malware_protection" {
  type        = bool
  description = "Enable GuardDuty malware protection for EC2"
  default     = true
}

variable "guardduty_finding_frequency" {
  type        = string
  description = "GuardDuty finding publishing frequency"
  default     = "FIFTEEN_MINUTES"
  validation {
    condition     = contains(["FIFTEEN_MINUTES", "ONE_HOUR", "SIX_HOURS"], var.guardduty_finding_frequency)
    error_message = "GuardDuty finding frequency must be FIFTEEN_MINUTES, ONE_HOUR, or SIX_HOURS"
  }
}

variable "guardduty_finding_threshold" {
  type        = number
  description = "Threshold for GuardDuty high severity findings alarm"
  default     = 0
}

# Security Hub Variables
variable "enable_security_hub" {
  type        = bool
  description = "Enable AWS Security Hub"
  default     = true
}

variable "enable_default_standards" {
  type        = bool
  description = "Enable default Security Hub standards"
  default     = true
}

variable "auto_enable_controls" {
  type        = bool
  description = "Automatically enable new Security Hub controls"
  default     = true
}

variable "enable_cis_standard" {
  type        = bool
  description = "Enable CIS AWS Foundations Benchmark"
  default     = true
}

variable "enable_fsbp_standard" {
  type        = bool
  description = "Enable AWS Foundational Security Best Practices"
  default     = true
}

variable "enable_pci_standard" {
  type        = bool
  description = "Enable PCI-DSS standard"
  default     = false
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

variable "slack_webhook_url" {
  type        = string
  description = "Slack webhook URL for security alerts"
  default     = null
  sensitive   = true
}

variable "pagerduty_integration_key" {
  type        = string
  description = "PagerDuty integration key for security alerts"
  default     = null
  sensitive   = true
}

# Encryption Variables
variable "kms_key_id" {
  type        = string
  description = "KMS key ID for encrypting SNS topics and logs"
  default     = null
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
