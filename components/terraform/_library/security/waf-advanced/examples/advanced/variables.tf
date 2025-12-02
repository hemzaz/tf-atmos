variable "aws_region" {
  type        = string
  description = "AWS region for resources"
  default     = "us-east-1"
}

variable "name_prefix" {
  type        = string
  description = "Prefix for resource names"
  default     = "example-advanced"
}

variable "resource_arns" {
  type        = list(string)
  description = "List of resource ARNs to protect (ALB, API Gateway, etc.)"
  default     = []
}

variable "enable_bot_control" {
  type        = bool
  description = "Enable bot control (adds significant cost)"
  default     = false
}

variable "enable_geo_blocking" {
  type        = bool
  description = "Enable geographic blocking"
  default     = false
}

variable "geo_block_countries" {
  type        = list(string)
  description = "Countries to block (ISO 3166-1 alpha-2 codes)"
  default     = ["CN", "RU", "KP"]
}
