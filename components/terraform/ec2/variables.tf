variable "region" {
  type        = string
  description = "AWS region"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where the instances will be created"
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs to launch the instances in"
}

variable "default_ami_id" {
  type        = string
  description = "Default AMI ID to use for instances if not specified"
  default     = ""
}

variable "default_key_name" {
  type        = string
  description = "Default key pair name to use for SSH access if not specified"
  default     = null
}

variable "instances" {
  type        = any
  description = "Map of instance configurations"
  default     = {}
}

variable "tags" {
  type        = map(string)
  description = "Common tags to apply to all resources"
  default     = {}
}
