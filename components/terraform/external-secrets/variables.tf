variable "region" {
  type        = string
  description = "AWS region"
}

variable "assume_role_arn" {
  type        = string
  description = "ARN of the IAM role to assume"
  default     = null
}

variable "enabled" {
  type        = bool
  description = "Whether the component is enabled"
  default     = true
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name"
}

variable "host" {
  type        = string
  description = "Kubernetes host"
}

variable "cluster_ca_certificate" {
  type        = string
  description = "Kubernetes cluster CA certificate"
}

variable "oidc_provider_arn" {
  type        = string
  description = "OIDC provider ARN for the EKS cluster"
}

variable "oidc_provider_url" {
  type        = string
  description = "OIDC provider URL for the EKS cluster"
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace to install external-secrets"
  default     = "external-secrets"
}

variable "create_namespace" {
  type        = bool
  description = "Whether to create the namespace"
  default     = true
}

variable "service_account_name" {
  type        = string
  description = "Name of the service account for external-secrets"
  default     = "external-secrets"
}

variable "chart_version" {
  type        = string
  description = "Version of the external-secrets Helm chart"
  default     = "0.9.9"
}

variable "certificate_secret_path_template" {
  type        = string
  description = "Template for certificate secrets path in Secrets Manager"
  default     = "certificates/{name}"
}

variable "create_default_cluster_secret_store" {
  type        = bool
  description = "Whether to create the default cluster secret store"
  default     = true
}

variable "create_certificate_secret_store" {
  type        = bool
  description = "Whether to create a dedicated secret store for certificates"
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
  default     = {}
}