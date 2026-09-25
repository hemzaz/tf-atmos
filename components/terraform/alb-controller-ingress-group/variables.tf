variable "region" {
  type        = string
  description = "AWS region"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "The region must be a valid AWS region name (e.g., us-east-1, eu-west-1)."
  }
}

variable "assume_role_arn" {
  type        = string
  description = "ARN of the IAM role to assume"
  default     = null

  validation {
    condition     = var.assume_role_arn == null || can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", var.assume_role_arn))
    error_message = "The assume_role_arn must be a valid IAM role ARN or null."
  }
}

variable "enabled" {
  type        = bool
  description = "Whether to create the resources. Set to false to avoid creating resources"
  default     = true
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name (eks output eks_cluster_id): the kubernetes provider's token comes from data aws_eks_cluster_auth against it, and the ALB lookup filters on its elbv2.k8s.aws/cluster tag"
  default     = ""
}

variable "host" {
  type        = string
  description = "API endpoint of var.cluster_name (eks output eks_cluster_endpoint), used by the kubernetes provider"
  default     = ""
}

variable "cluster_ca_certificate" {
  type        = string
  description = "Base64 CA certificate of var.cluster_name (eks output eks_cluster_certificate_authority_data)"
  default     = ""
}

variable "vpc_id" {
  type        = string
  description = "VPC ID the ALB's frontend security group is created in"
  default     = ""
}

variable "kubernetes_namespace" {
  type        = string
  description = "Namespace the IngressGroup scaffold's Ingress is created in"
  default     = "default"
}

variable "group_name" {
  type        = string
  description = "The IngressGroup name (alb.ingress.kubernetes.io/group.name). Every Ingress naming this group shares one ALB; this component's data aws_lb lookup filters on it too (the controller's ingress.k8s.aws/stack tag)"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.group_name))
    error_message = "group_name must be a valid IngressGroup name: lowercase alphanumeric and hyphens, 1-63 characters."
  }
}

variable "admit_security_group_ids" {
  type        = list(string)
  description = "Security groups admitted as a source on the ALB's listener ports. Never a CIDR block: this repo forbids inbound 0.0.0.0/0 and ::/0, and the ALB's frontend security group has no other way in. Typically the API Gateway VPC link's security group"
  default     = []

  validation {
    condition     = alltrue([for s in var.admit_security_group_ids : can(regex("^sg-[a-f0-9]+$", s))])
    error_message = "admit_security_group_ids must be security group IDs (sg-...)."
  }

  validation {
    condition     = length(var.admit_security_group_ids) > 0
    error_message = "admit_security_group_ids must name at least one security group; the ALB refuses inbound 0.0.0.0/0 and has no other way in."
  }
}

variable "certificate_arn" {
  type        = string
  description = "ACM certificate ARN for an HTTPS (443) listener. Null (default) creates an HTTP-only (80) ALB"
  default     = null

  validation {
    condition     = var.certificate_arn == null || can(regex("^arn:aws:acm:[a-z0-9-]+:[0-9]{12}:certificate/.+$", var.certificate_arn))
    error_message = "certificate_arn must be a valid ACM certificate ARN or null."
  }
}

variable "ssl_policy" {
  type        = string
  description = "TLS security policy for the HTTPS listener; ignored unless certificate_arn is set"
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "wait_for_load_balancer" {
  type        = bool
  description = "Whether kubernetes_ingress_v1 waits for the controller to provision the ALB before `apply` returns. The data aws_lb / aws_lb_listener lookups below depend on the Ingress either way; this only controls how long `apply` blocks for it"
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to add to all resources. Environment is required because it is the name prefix for every resource this component creates"
  default     = {}

  validation {
    condition     = trimspace(lookup(var.tags, "Environment", "")) != ""
    error_message = "tags must include a non-empty Environment value."
  }
}
