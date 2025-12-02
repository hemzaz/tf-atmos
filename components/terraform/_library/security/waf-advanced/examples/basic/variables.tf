variable "aws_region" {
  type        = string
  description = "AWS region for resources"
  default     = "us-east-1"
}

variable "name_prefix" {
  type        = string
  description = "Prefix for resource names"
  default     = "example-basic"
}

variable "alb_arns" {
  type        = list(string)
  description = "List of Application Load Balancer ARNs to protect"
  default     = []
}
