variable "region" {
  type        = string
  description = "AWS region Inspector is enabled in"

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
  description = "Enable Amazon Inspector for this account and region. Inspector bills per resource scanned, so the catalog leaves it false"
  default     = false

  validation {
    condition     = !var.enabled || var.auto_enable_ec2 || var.auto_enable_ecr || var.auto_enable_lambda
    error_message = "enabled needs at least one resource type: set auto_enable_ec2, auto_enable_ecr or auto_enable_lambda."
  }
}

# Cloud Posse aws-inspector2 input names. There they set the organization's
# auto-enable; here they pick the resource types scanned in this account.
variable "auto_enable_ec2" {
  type        = bool
  description = "Scan EC2 instances (resource type EC2)"
  default     = true
}

variable "auto_enable_ecr" {
  type        = bool
  description = "Scan ECR container images (resource type ECR)"
  default     = true
}

variable "auto_enable_lambda" {
  type        = bool
  description = "Scan Lambda functions' package dependencies (resource type LAMBDA)"
  default     = true
}

variable "auto_enable_lambda_code" {
  type        = bool
  description = "Also scan Lambda function code (resource type LAMBDA_CODE). Needs auto_enable_lambda"
  default     = false

  validation {
    condition     = !var.auto_enable_lambda_code || var.auto_enable_lambda
    error_message = "auto_enable_lambda_code needs auto_enable_lambda: Lambda code scanning builds on Lambda standard scanning."
  }
}
