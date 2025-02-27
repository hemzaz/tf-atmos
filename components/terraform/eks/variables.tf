variable "region" {
  type        = string
  description = "AWS region"
}

variable "clusters" {
  type        = any
  description = "Map of EKS cluster configurations"
  default     = {}
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs for the EKS clusters"
}

variable "default_kubernetes_version" {
  type        = string
  description = "Default Kubernetes version for EKS clusters"
  default     = "1.28"
}

variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the OIDC provider for the EKS cluster"
  default     = ""
}

variable "tags" {
  type        = map(string)
  description = "Common tags to apply to all resources"
  default     = {}
}