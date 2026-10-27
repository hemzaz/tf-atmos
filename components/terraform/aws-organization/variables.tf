variable "region" {
  type        = string
  description = "AWS Region"
}

variable "aws_service_access_principals" {
  type        = list(string)
  description = "List of AWS service principal names for which you want to enable integration with your organization"
  default     = []
}

variable "enabled_policy_types" {
  type        = list(string)
  description = "List of Organizations policy types to enable in the Organization Root (e.g., SERVICE_CONTROL_POLICY, TAG_POLICY, BACKUP_POLICY, AISERVICES_OPT_OUT_POLICY)"
  default     = []
}

variable "feature_set" {
  type        = string
  description = "Feature set of the organization. One of 'ALL' or 'CONSOLIDATED_BILLING'"
  default     = "ALL"

  validation {
    condition     = contains(["ALL", "CONSOLIDATED_BILLING"], var.feature_set)
    error_message = "feature_set must be one of: ALL, CONSOLIDATED_BILLING"
  }
}

variable "organization_enabled_features" {
  type        = list(string)
  description = "List of IAM features to enable. Valid values are 'RootCredentialsManagement' and 'RootSessions'. Set to empty list to disable."
  default     = []

  validation {
    condition = alltrue([
      for feature in var.organization_enabled_features :
      contains(["RootCredentialsManagement", "RootSessions"], feature)
    ])
    error_message = "Valid values for organization_enabled_features are 'RootCredentialsManagement' and 'RootSessions'."
  }
}
