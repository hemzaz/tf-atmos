# Core backend configuration variables
variable "tenant" {
  type        = string
  description = "Tenant name for resource naming"
  default     = "" # Will be set by Atmos
}

variable "account_id" {
  type        = string
  description = "AWS Account ID for resource policies"
  default     = "" # Will be set by Atmos

  validation {
    condition     = var.account_id == "" || can(regex("^[0-9]{12}$", var.account_id))
    error_message = "Account ID must be a 12-digit number."
  }
}

variable "bucket_name" {
  type        = string
  description = "Name of the S3 bucket for Terraform state (the -logs and -access-logs buckets derive from it)"

  validation {
    # 63-character S3 limit minus the 12-character "-access-logs" suffix
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,49}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be a DNS-compliant S3 bucket name of 3-51 characters."
  }
}

variable "region" {
  type        = string
  description = "AWS region"
  default     = "" # Will be set by Atmos

  validation {
    condition     = var.region == "" || can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "Must be a valid AWS region format."
  }
}

variable "access_roles" {
  type = map(object({
    role_name              = string
    write_enabled          = bool
    allowed_principal_arns = optional(list(string), [])
    object_key_patterns    = optional(list(string), ["*"])
  }))
  description = <<-EOT
    State access roles, after the `access_roles` input of Cloud Posse's aws-tfstate-backend
    component. One IAM role per entry, named `role_name`. Every role may list the bucket, read the
    state objects matching `object_key_patterns` (S3 object-key patterns, `*` wildcards, appended to
    the bucket ARN; default every object) and decrypt with the state key; `write_enabled` also
    allows writing and deleting those objects (state and `.tflock` lock files) and encrypting with
    the key. A read-only role may also list object versions and read the bucket's versioning and
    replication settings (the disaster-recovery checks, workflows/scripts/dr).
    `allowed_principal_arns` are the exact IAM role/user ARNs that may assume the role (trusted
    through an `aws:PrincipalArn` condition, so they need not exist yet); the principal running
    Terraform is always added, as upstream, so an empty list (upstream's default) trusts only
    that caller. By convention the keys are `read`, `prod_read`, `write`, `prod_write` and
    `root_write`, which the backend_read_role_arn, backend_prod_read_role_arn, backend_role_arn,
    backend_prod_role_arn and backend_root_role_arn outputs expose.
  EOT

  validation {
    condition = alltrue(flatten([
      for role in values(var.access_roles) : [
        length(role.object_key_patterns) > 0,
        [for p in role.object_key_patterns : can(regex("^[A-Za-z0-9*._/-]+$", p)) && !startswith(p, "/")],
      ]
    ]))
    error_message = "Each access_roles object_key_patterns must be a non-empty list of S3 object-key patterns ([A-Za-z0-9*._/-], no leading \"/\")."
  }

  validation {
    condition     = length(var.access_roles) > 0
    error_message = "access_roles must define at least one role: every stack's backend configuration assumes one."
  }

  validation {
    condition     = alltrue([for role in values(var.access_roles) : can(regex("^[\\w+=,.@-]{1,64}$", role.role_name))])
    error_message = "Each access_roles role_name must be 1-64 characters from [A-Za-z0-9+=,.@_-]."
  }

  validation {
    condition     = length(distinct([for role in values(var.access_roles) : role.role_name])) == length(var.access_roles)
    error_message = "access_roles role_name values must be unique."
  }

  validation {
    # An IAM role or user ARN with an account ID and no wildcard. "*" and account roots
    # would trust every principal (in an account); that is what this component replaces.
    condition = alltrue(flatten([
      for role in values(var.access_roles) : [
        for arn in role.allowed_principal_arns :
        can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(role|user)/[\\w+=,.@/-]+$", arn)) && !strcontains(arn, "*")
      ]
    ]))
    error_message = "allowed_principal_arns entries must be exact IAM role or user ARNs (arn:aws:iam::<account>:role/<name>); \"*\", wildcards and account roots (arn:aws:iam::<account>:root) are rejected."
  }
}

# Security and operational features

variable "enable_access_logging" {
  type        = bool
  description = "Create the access logs bucket and enable S3 server access logging for the state buckets"
  default     = true
}

# Common tags
variable "tags" {
  type        = map(string)
  description = "Common tags to apply to all resources"
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.tags :
      length(k) <= 128 && length(v) <= 256
    ])
    error_message = "Tag keys must be <= 128 characters and values <= 256 characters."
  }
}
