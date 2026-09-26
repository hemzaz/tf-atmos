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
}

variable "enabled" {
  type        = bool
  description = "Whether the component is enabled"
  default     = true
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name (the eks component's eks_cluster_id); also the IAM name prefix"

  # eks outputs a null eks_cluster_id when its instance is disabled.
  validation {
    condition     = var.cluster_name != null
    error_message = "cluster_name is null: the eks instance this reads (eks_cluster_id) is disabled or has no cluster. Set metadata.enabled: false on this external-secrets instance in the stack, or enable the cluster."
  }

  validation {
    condition     = var.cluster_name == null ? true : can(regex("^[0-9A-Za-z][0-9A-Za-z_-]*$", var.cluster_name))
    error_message = "cluster_name must be an EKS cluster name, not an ARN."
  }

  # IAM role names are limited to 64 characters. The role is
  # "<cluster_name>-external-secrets-role", with the Environment prefixed only
  # when cluster_name lacks it, case-insensitively (see local.name_prefix).
  validation {
    condition     = var.cluster_name == null ? true : length("${startswith(lower(var.cluster_name), "${lower(lookup(var.tags, "Environment", ""))}-") ? var.cluster_name : "${lookup(var.tags, "Environment", "")}-${var.cluster_name}"}-external-secrets-role") <= 64
    error_message = "<cluster name>-external-secrets-role must fit IAM's 64-character role name limit."
  }
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
  description = "Tags to apply to resources; must include Environment (used in resource names)"

  validation {
    condition     = trimspace(lookup(var.tags, "Environment", "")) != ""
    error_message = "tags must include a non-empty Environment value."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "ARN of the customer-managed KMS key external-secrets is allowed to decrypt through (this stack's kms/main key, which secretsmanager/defaults also uses as default_kms_key_id). Required only when var.enabled is true; null or empty is accepted on a disabled instance (settings.environment.use_external_secrets: false), which creates no resources that need it."
  # "" rather than null: `atmos terraform lint` runs tflint without stack
  # vars, so this default is what gets interpolated into
  # policies/external-secrets-policy.json.tpl's "${kms_key_arn}"; a null
  # default breaks that string interpolation ("this value is null, but a
  # string is required"), while "" renders (to an invalid, but not crashing,
  # ARN) and is still rejected by the validation below whenever var.enabled
  # is true (the default).
  default = ""

  # Cross-variable validation (Terraform >= 1.9, this repo requires >= 1.16):
  # only enforce "required" when the instance is actually enabled, so a
  # disabled instance's kms/main dependency doesn't have to resolve to a real
  # key for this variable to validate.
  validation {
    condition     = var.enabled == false || (var.kms_key_arn != null && trimspace(var.kms_key_arn) != "")
    error_message = "kms_key_arn is required when var.enabled is true."
  }

  # Accepts both single-region keys (key/<uuid>) and multi-region keys
  # (key/mrk-<32 hex>, no dashes), and any AWS partition (aws, aws-us-gov,
  # aws-cn), e.g. arn:aws-us-gov:kms:us-gov-west-1:123456789012:key/mrk-...
  validation {
    condition     = var.kms_key_arn == null || var.kms_key_arn == "" || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:\\d{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:aws[-us-gov|-cn]:kms:<region>:<account-id>:key/<uuid>, or key/mrk-<32 hex chars> for a multi-region key), or null/empty when var.enabled is false."
  }
}

variable "secret_path_prefixes" {
  type        = list(string)
  description = "Secrets Manager secret-name path prefixes external-secrets may read, matched as a top-level prefix (\"<prefix>/*\"), plus \"<context>/<prefix>/*\" for every entry in var.secret_path_context_prefixes. Defaults cover this repo's certificate secrets (components/terraform/secretsmanager), bastion SSH keys (ec2's \"ssh-key/<Environment>/<name>\"), the app/infra secretsmanager instances (context_name \"app\"/\"infra\", or \"<stage>/app\"/\"<stage>/infra\" in staging and prod), and elasticache's redis AUTH token secrets (\"redis-auth/<Environment>/<cluster_id>\")."
  default     = ["certificates", "ssh-key", "app", "infra", "redis-auth"]

  validation {
    condition     = alltrue([for p in var.secret_path_prefixes : can(regex("^[0-9A-Za-z_.-]+$", p))])
    error_message = "secret_path_prefixes entries must be a single non-empty path segment, without leading/trailing slashes or wildcards."
  }
}

variable "rds_managed_secret_access" {
  type        = bool
  description = "Grant read access to any RDS-managed master-user secret in this account/region (aws_db_instance's manage_master_user_password, secret names \"rds!db-<AWS-generated-id>\"). RDS generates that name itself only after the instance is created, so it cannot be listed ahead of time in secret_path_prefixes -- whose entries may not contain \"!\", the character RDS's fixed naming convention requires. Off by default; a stack whose consumer (e.g. eks-backend-services) reads an RDS-managed secret through this ClusterSecretStore turns it on."
  default     = false
}

variable "ssm_parameter_path_prefixes" {
  type        = list(string)
  description = "SSM Parameter Store path prefixes external-secrets may read, matched as a top-level prefix (\"/<prefix>/*\"), plus \"/<context>/<prefix>/*\" for every entry in var.secret_path_context_prefixes."
  default     = ["certificates"]

  validation {
    condition     = alltrue([for p in var.ssm_parameter_path_prefixes : can(regex("^[0-9A-Za-z_.-]+$", p))])
    error_message = "ssm_parameter_path_prefixes entries must be a single non-empty path segment, without leading/trailing slashes or wildcards."
  }
}

variable "secret_path_context_prefixes" {
  type        = list(string)
  description = "Explicit leading path segment(s) (this stack's context, e.g. its descriptive stage name) that may precede a secret_path_prefixes/ssm_parameter_path_prefixes match one level down, in place of a depth-agnostic \"*/<prefix>/*\" wildcard (which would also match an unrelated secret merely containing \"/<prefix>/\" further down its name, e.g. \"x/y/app/z\"). secretsmanager's full_path nests context_name/environment/path/name (e.g. \"production/app/prod/production/app/credentials\" for context_name \"production/app\"), so the catalog sets this to settings.environment.stage (\"production\"), the descriptive stage name each stack's secretsmanager/app and secretsmanager/infra instances already hardcode as the leading segment of context_name. Empty by default: only the top-level \"<prefix>/*\" match applies unless a stack's catalog configures this."
  default     = []

  validation {
    condition     = alltrue([for c in var.secret_path_context_prefixes : can(regex("^[0-9A-Za-z_.-]+$", c))])
    error_message = "secret_path_context_prefixes entries must be a single non-empty path segment, without leading/trailing slashes or wildcards."
  }
}