variable "region" {
  type        = string
  description = "AWS region"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "The region must be a valid AWS region name (e.g., us-east-1, eu-west-1)."
  }
}

# Required on purpose: a `default = {}` here makes every resource look untagged to
# tflint/checkov, which run per-component without stack vars. Keep it required.
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

# Cloud Posse aws-github-action-token-rotator's inputs.
variable "github_app_id" {
  type        = string
  description = "GitHub App ID (the App's settings page, \"App ID\")"

  validation {
    condition     = can(regex("^[0-9]+$", var.github_app_id))
    error_message = "github_app_id must be the App's numeric ID."
  }
}

variable "github_app_installation_id" {
  type        = string
  description = "GitHub App installation ID (the number at the end of the installation's settings URL)"

  validation {
    condition     = can(regex("^[0-9]+$", var.github_app_installation_id))
    error_message = "github_app_installation_id must be the installation's numeric ID."
  }
}

variable "github_org_name" {
  type        = string
  description = "GitHub organization or user that owns the runners' scope"

  validation {
    condition     = can(regex("^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$", var.github_org_name))
    error_message = "github_org_name must be a GitHub organization or user name."
  }
}

# Not in Cloud Posse's component, which registers organization runners only. A
# repository owned by a user account has no organization runners: set the
# repository and the token registers repository-scoped runners.
variable "github_repository_name" {
  type        = string
  description = "Repository the runners register to (repository-scoped runners); null registers organization runners"
  default     = null

  validation {
    condition     = var.github_repository_name == null || can(regex("^[A-Za-z0-9._-]{1,100}$", coalesce(var.github_repository_name, "-")))
    error_message = "github_repository_name must be a repository name without its owner."
  }
}

variable "parameter_store_private_key_path" {
  type        = string
  description = "SSM SecureString holding the GitHub App's private key (PEM, or base64 of the PEM), written by hand once; the function reads it at run time, so it is never in the Lambda configuration or the Terraform state"

  validation {
    condition     = can(regex("^/[A-Za-z0-9_./-]+$", var.parameter_store_private_key_path))
    error_message = "parameter_store_private_key_path must be an absolute SSM parameter path (e.g. /github/runners/app-private-key)."
  }
}

variable "parameter_store_token_path" {
  type        = string
  description = "SSM SecureString this component creates and the function overwrites with each new runner registration token; github-runners reads it at boot"

  validation {
    condition     = can(regex("^/[A-Za-z0-9_./-]+$", var.parameter_store_token_path))
    error_message = "parameter_store_token_path must be an absolute SSM parameter path (e.g. /github/runners/registration-token)."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "Customer managed key that encrypts the token parameter, the function's environment and its log group; the private key parameter should use it too (the function may decrypt with it through SSM only)"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN."
  }
}

variable "schedule_expression" {
  type        = string
  description = "How often the token is rotated. A registration token is valid for an hour, so this must be more often"
  default     = "rate(30 minutes)"

  validation {
    condition     = can(regex("^(rate\\((1|[1-9][0-9]*) minutes?\\)|cron\\(.+\\))$", var.schedule_expression))
    error_message = "schedule_expression must be an EventBridge rate(N minutes) or cron(...) expression."
  }
}

variable "memory_size" {
  type        = number
  description = "Function memory in MB (Cloud Posse's memory_size)"
  default     = 128

  validation {
    condition     = var.memory_size >= 128 && var.memory_size <= 10240
    error_message = "memory_size must be between 128 and 10240."
  }
}

variable "log_retention_days" {
  type        = number
  description = "Days the function's log group keeps its logs"
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a CloudWatch Logs retention value (1, 3, 5, 7, 14, 30, 60, 90, ...)."
  }
}
