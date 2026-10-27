variable "region" {
  type        = string
  description = "AWS Region"
}

variable "account_email" {
  type        = string
  description = "The email address for the AWS account"

  validation {
    condition = can(
      regex(
        "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$",
        var.account_email
      )
    )
    error_message = "account_email must be a valid email address (e.g., name@example.com)."
  }
}

variable "parent_id" {
  type        = string
  description = "The ID of the parent Organizational Unit or organization root"
}

variable "iam_user_access_to_billing" {
  type        = string
  description = "Whether IAM users can access billing. ALLOW or DENY"
  default     = "DENY"

  validation {
    condition     = contains(["ALLOW", "DENY"], var.iam_user_access_to_billing)
    error_message = "iam_user_access_to_billing must be one of: ALLOW, DENY"
  }
}

variable "close_on_deletion" {
  type        = bool
  description = "Whether to close the account on deletion"
  default     = false
}

variable "create_govcloud" {
  type        = bool
  description = "Whether to also create a GovCloud account. The GovCloud account is tied to the main (commercial) account this resource creates"
  default     = false
}

variable "role_name" {
  type        = string
  description = "The name of the IAM role that Organizations creates in the new member account"
  default     = null
}
