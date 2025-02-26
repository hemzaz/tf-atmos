variable "bucket_name" {
  type        = string
  description = "Name of the S3 bucket for Terraform state"
  default     = ""  # Will be set by Atmos
}

variable "dynamodb_table_name" {
  type        = string
  description = "Name of the DynamoDB table for Terraform state locking"
  default     = ""  # Will be set by Atmos
}

variable "region" {
  type        = string
  description = "AWS region"
  default     = ""  # Will be set by Atmos
}

variable "state_file_key" {
  type        = string
  description = "Key for the state file in S3 bucket"
  default     = "terraform.tfstate"
}

variable "iam_role_name" {
  type        = string
  description = "Name of the IAM role to assume for Terraform execution"
  default     = ""  # Will be set by Atmos
}

variable "iam_role_arn" {
  type        = string
  description = "ARN of the IAM role to assume for Terraform execution"
}