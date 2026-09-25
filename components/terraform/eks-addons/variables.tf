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

variable "default_tags" {
  type        = map(string)
  description = "Default tags to apply to all resources"
  default     = {}

  validation {
    condition     = length(var.default_tags) > 0 ? contains(keys(var.default_tags), "Environment") : true
    error_message = "If default_tags is provided, it must contain an 'Environment' key."
  }
}

variable "clusters" {
  type = map(object({
    # The cluster's name and OIDC provider default to the top-level
    # cluster_name / oidc_provider_arn / oidc_provider_url: the connection the
    # kubernetes and helm providers use.
    cluster_name      = optional(string)
    oidc_provider_arn = optional(string)
    oidc_provider_url = optional(string)
    # Not read: the providers connect through the top-level host and
    # cluster_ca_certificate.
    kubernetes_host        = optional(string)
    cluster_ca_certificate = optional(string)

    # Optional fields
    service_account_token_path = optional(string)
    # Read by main.tf; undeclared, the object type dropped them, so a stack's
    # `enabled: false` still processed the cluster. Defaults live here because
    # lookup() on a declared-but-null attribute returns null, not its default.
    enabled                   = optional(bool, true)
    wait_for_cluster_duration = optional(string, "45s")

    # Add-on switches (addons.tf). Each installs a pinned Helm chart and, if
    # the add-on calls AWS, an IRSA role scoped to its own service account.
    enable_aws_load_balancer_controller = optional(bool, false)
    enable_cluster_autoscaler           = optional(bool, false)
    enable_external_dns                 = optional(bool, false)
    enable_cert_manager                 = optional(bool, false)
    enable_metrics_server               = optional(bool, false)
    # Container Insights (container-insights.tf): the
    # amazon-cloudwatch-observability EKS add-on, i.e. the CloudWatch agent
    # (metrics) and Fluent Bit (container logs), with an IRSA role and
    # KMS-encrypted log groups. Replaces enable_aws_cloudwatch_metrics and
    # enable_aws_for_fluentbit.
    enable_container_insights = optional(bool, false)
    # enable_karpenter, enable_keda and enable_istio used to sit here, read by
    # nothing. Install those through helm_releases below. External Secrets
    # (enable_external_secrets) is its own component: external-secrets.

    # Add-on settings
    # The VPC the load balancer controller manages (the vpc output vpc_id).
    vpc_id = optional(string)
    # The PUBLIC hosted zone IDs external-dns and cert-manager may change,
    # picked from the dns component's zone_ids output. Their IAM policies
    # allow record changes on exactly these zones; leave private zones out.
    dns_zone_ids                   = optional(list(string), [])
    external_dns_domain_filters    = optional(list(string), [])
    cert_manager_letsencrypt_email = optional(string)
    # ACME directory of the letsencrypt ClusterIssuer: Let's Encrypt
    # production by default, its staging directory for non-production.
    cert_manager_acme_server = optional(string, "https://acme-v02.api.letsencrypt.org/directory")
    # Extra Helm values per add-on, keyed by add-on name
    # (aws-load-balancer-controller, cluster-autoscaler, metrics-server,
    # external-dns, cert-manager), applied after the component's own.
    addon_chart_values = optional(any, {})

    # Container Insights settings. The log groups
    # /aws/containerinsights/<cluster>/{application,dataplane,host,performance}
    # are encrypted with this key (kms/main, whose policy lets CloudWatch Logs
    # use it through allow_cloudwatch_logs).
    container_insights_kms_key_arn        = optional(string)
    container_insights_log_retention_days = optional(number, 90)
    # The EKS add-on version; null takes EKS's default version for the
    # cluster's Kubernetes version.
    container_insights_addon_version = optional(string)
    additional_namespaces            = optional(list(string), [])

    # karpenter_provisioner_config and istio_config used to sit here as
    # map(any). Nothing in this component or any stack ever read either one, so
    # a stack could write a whole Karpenter provisioner spec and have it go
    # nowhere. They are gone rather than left looking configurable; pass
    # Karpenter and Istio settings through helm_releases below, which main.tf
    # does read.

    # Resources consumed by main.tf (flattened per cluster); previously undeclared,
    # so the object type silently dropped them
    addons               = optional(any, {})
    helm_releases        = optional(any, {})
    kubernetes_manifests = optional(any, {})

    # Tags
    tags = optional(map(string), {})
  }))
  description = "Map of cluster configurations: add-on switches, EKS addons, Helm releases, and Kubernetes manifests"
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.clusters : !v.enabled || (
        trimspace(coalesce(v.cluster_name, var.cluster_name, " ")) != "" &&
        trimspace(coalesce(v.oidc_provider_arn, var.oidc_provider_arn, " ")) != "" &&
        trimspace(coalesce(v.oidc_provider_url, var.oidc_provider_url, " ")) != ""
      )
    ])
    error_message = "Every enabled cluster needs cluster_name, oidc_provider_arn and oidc_provider_url, on the entry or at the top level."
  }

  validation {
    condition = alltrue([
      for k, v in var.clusters : !v.enabled || !(
        v.enable_aws_load_balancer_controller || v.enable_cluster_autoscaler || v.enable_external_dns ||
        v.enable_cert_manager || v.enable_metrics_server || v.enable_container_insights
      ) || coalesce(v.cluster_name, var.cluster_name, " ") == var.cluster_name
    ])
    error_message = "The enable_* add-ons install into var.cluster_name, the cluster the kubernetes/helm providers connect to; a clusters entry that switches one on must be that cluster."
  }

  validation {
    condition = alltrue([
      for k, v in var.clusters : !v.enabled || !v.enable_aws_load_balancer_controller || can(regex("^vpc-[0-9a-f]+$", v.vpc_id))
    ])
    error_message = "enable_aws_load_balancer_controller needs vpc_id (vpc-...)."
  }

  validation {
    condition = alltrue([
      for k, v in var.clusters : !v.enabled || !(v.enable_external_dns || v.enable_cert_manager) || length(v.dns_zone_ids) > 0
    ])
    error_message = "enable_external_dns and enable_cert_manager need dns_zone_ids: their IAM policies are scoped to those hosted zones."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.clusters : [for id in v.dns_zone_ids : can(regex("^Z[0-9A-Z]{1,31}$", id))]
    ]))
    error_message = "dns_zone_ids values must be Route 53 hosted zone IDs (Z..., without /hostedzone/)."
  }

  validation {
    condition = alltrue([
      for k, v in var.clusters :
      !v.enabled || !v.enable_cert_manager || can(regex("^[^@]+@[^@]+\\.[^@]+$", v.cert_manager_letsencrypt_email))
    ])
    error_message = "When cert_manager is enabled, cert_manager_letsencrypt_email must be a valid email address."
  }

  validation {
    condition = alltrue([
      for k, v in var.clusters : !v.enabled || !v.enable_container_insights ||
      can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/", v.container_insights_kms_key_arn))
    ])
    error_message = "enable_container_insights needs container_insights_kms_key_arn, the ARN of a KMS key (kms/main key_arn)."
  }

  validation {
    condition = alltrue([
      for k, v in var.clusters : contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], v.container_insights_log_retention_days)
    ])
    error_message = "container_insights_log_retention_days must be a CloudWatch Logs retention value (1, 3, 5, 7, 14, 30, 60, 90, ...)."
  }

  validation {
    condition = alltrue([
      for k, v in var.clusters : contains([
        "https://acme-v02.api.letsencrypt.org/directory",
        "https://acme-staging-v02.api.letsencrypt.org/directory",
      ], v.cert_manager_acme_server)
    ])
    error_message = "cert_manager_acme_server must be the Let's Encrypt production or staging directory."
  }
}

# Connection to the cluster the kubernetes and helm providers use
variable "cluster_name" {
  type        = string
  description = "EKS cluster the kubernetes and helm providers connect to (eks output eks_cluster_id); the default cluster_name of clusters entries"
  default     = ""
}

variable "host" {
  type        = string
  description = "API endpoint of var.cluster_name (eks output eks_cluster_endpoint), used by the kubernetes and helm providers"
  default     = ""
}

variable "cluster_ca_certificate" {
  type        = string
  description = "Base64 CA certificate of var.cluster_name (eks output eks_cluster_certificate_authority_data)"
  default     = ""
}

variable "oidc_provider_arn" {
  type        = string
  description = "IRSA OIDC provider ARN of var.cluster_name (eks output eks_cluster_identity_oidc_issuer_arn); the default of clusters entries"
  default     = ""

  validation {
    condition     = var.oidc_provider_arn == "" || can(regex("^arn:aws:iam::[0-9]{12}:oidc-provider/", var.oidc_provider_arn))
    error_message = "OIDC provider ARN must be in a valid format (e.g., arn:aws:iam::123456789012:oidc-provider/...)."
  }
}

variable "oidc_provider_url" {
  type        = string
  description = "OIDC issuer URL of var.cluster_name (eks output eks_cluster_identity_oidc_issuer); the default of clusters entries"
  default     = ""

  validation {
    condition     = var.oidc_provider_url == "" || can(regex("^https://", var.oidc_provider_url))
    error_message = "OIDC provider URL must start with https://."
  }
}

variable "tags" {
  type        = map(string)
  description = "Common tags to apply to all resources"
  default     = {}

  validation {
    condition     = trimspace(lookup(var.tags, "Environment", "")) != ""
    error_message = "tags must include a non-empty Environment value."
  }
}

# -------------------------------------------------------------------------
# Istio gateway configuration
# -------------------------------------------------------------------------
# istio_enabled installs the default gateway chart (charts/istio-gateway-config)
# for domain_name and its TLS secret. Istio itself is installed through
# clusters.<key>.helm_releases; there is no per-cluster Istio switch.
# istio_enable_tracing, kiali_enabled and jaeger_enabled are not variables.
# -------------------------------------------------------------------------

variable "istio_enabled" {
  type        = bool
  description = "Install the default Istio gateway configuration (and its TLS secret) for domain_name; Istio itself comes from helm_releases"
  default     = false
}

# Certificate management variables
variable "domain_name" {
  type        = string
  description = "Domain served by the default Istio gateway (istio_enabled)"
  default     = "example.com"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]\\.[a-zA-Z]{2,}$", var.domain_name))
    error_message = "The domain_name must be a valid domain (e.g., example.com)."
  }
}

variable "acm_certificate_crt" {
  type        = string
  description = "Certificate content from ACM"
  default     = ""
  sensitive   = true
}

variable "acm_certificate_key" {
  type        = string
  description = "Private key content from ACM"
  default     = ""
  sensitive   = true
  ephemeral   = true
}

variable "acm_certificate_revision" {
  type        = number
  description = "Increment to push new acm_certificate_crt/acm_certificate_key content to the write-only Istio TLS secret"
  default     = 1

  validation {
    condition     = var.acm_certificate_revision >= 1 && floor(var.acm_certificate_revision) == var.acm_certificate_revision
    error_message = "acm_certificate_revision must be a positive integer."
  }
}

# Secrets Manager Integration
variable "secrets_manager_secret_path" {
  type        = string
  description = "Path to the secret in AWS Secrets Manager containing the TLS certificate"
  default     = ""
}

variable "use_external_secrets" {
  type        = bool
  description = "Whether to use external-secrets operator to retrieve certificates from Secrets Manager"
  default     = true
}
