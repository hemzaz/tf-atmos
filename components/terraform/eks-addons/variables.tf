variable "region" {
  type        = string
  description = "AWS region"
}

variable "clusters" {
  type        = any
  description = "Map of cluster configurations with addons, Helm releases, and Kubernetes manifests"
  default     = {}
}

variable "cluster_name" {
  type        = string
  description = "Default EKS cluster name"
  default     = ""
}

variable "host" {
  type        = string
  description = "Default Kubernetes host"
  default     = ""
}

variable "cluster_ca_certificate" {
  type        = string
  description = "Default Kubernetes cluster CA certificate"
  default     = ""
}

variable "oidc_provider_arn" {
  type        = string
  description = "Default OIDC provider ARN for the EKS cluster"
  default     = ""
}

variable "oidc_provider_url" {
  type        = string
  description = "Default OIDC provider URL for the EKS cluster"
  default     = ""
}

variable "tags" {
  type        = map(string)
  description = "Common tags to apply to all resources"
  default     = {}
}