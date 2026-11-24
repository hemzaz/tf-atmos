variable "region" {
  type        = string
  description = "AWS region"
  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "The region must be a valid AWS region name (e.g., us-east-1, eu-west-1)."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to the IAM resources"
  default     = {}
}

# ---------------------------------------------------------------------------
# The GitHub Actions OIDC Lambda uploader role (off unless github_oidc_enabled). The CI plan and
# apply roles are the vendored aws-iam-role's (stacks/catalog/aws-iam-role/ci.yaml, E6a4).
# ---------------------------------------------------------------------------
variable "github_oidc_enabled" {
  type        = bool
  description = "Allow the GitHub Actions OIDC Lambda uploader role (created when lambda_uploader_trusted_github_repos is set)"
  default     = false
}

variable "github_oidc_provider_arn" {
  type        = string
  description = "ARN of the account's GitHub Actions OIDC provider (the vendored aws-github-oidc-provider's) that the uploader role trusts"
  default     = null

  validation {
    condition     = var.github_oidc_provider_arn == null || can(regex("^arn:aws:iam::\\d{12}:oidc-provider/token\\.actions\\.githubusercontent\\.com$", var.github_oidc_provider_arn))
    error_message = "github_oidc_provider_arn must be an arn:aws:iam::<account>:oidc-provider/token.actions.githubusercontent.com ARN."
  }

  validation {
    condition     = !var.github_oidc_enabled || var.github_oidc_provider_arn != null
    error_message = "github_oidc_provider_arn is required when github_oidc_enabled is true: the uploader role trusts the account's aws-github-oidc-provider."
  }
}

variable "ci_role_name_prefix" {
  type        = string
  description = "Name prefix of the Lambda uploader role, \"<prefix>-lambda-uploader\" (lambda-uploader.tf checks the 64-character limit)"
  default     = null

  validation {
    condition     = var.ci_role_name_prefix == null || can(regex("^[\\w+=,.@-]{1,58}$", var.ci_role_name_prefix))
    error_message = "ci_role_name_prefix must be 1-58 characters of alphanumerics or +=,.@_-."
  }

  validation {
    condition     = !var.github_oidc_enabled || var.ci_role_name_prefix != null
    error_message = "ci_role_name_prefix is required when github_oidc_enabled is true."
  }
}

variable "lambda_uploader_trusted_github_repos" {
  type        = list(string)
  description = <<-EOT
    Application repositories whose CI may upload Lambda packages to this stage's s3/lambda-artifacts
    bucket through the "<ci_role_name_prefix>-lambda-uploader" role, each "<org>/<repo>:<branch>"
    (Cloud Posse's branch-pinned trusted_github_repos shape; sub "repo:<org>/<repo>:ref:refs/heads/<branch>",
    StringEquals). Empty (the default) creates no role. Requires github_oidc_enabled.
  EOT
  default     = []

  validation {
    condition = alltrue(flatten([
      for repo in var.lambda_uploader_trusted_github_repos : [
        can(regex("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+:[A-Za-z0-9._/-]+$", repo)),
        !strcontains(repo, "*"),
        !strcontains(repo, "environment:"),
        !endswith(repo, ":pull_request"),
      ]
    ]))
    error_message = "Each lambda_uploader_trusted_github_repos entry must be \"<org>/<repo>:<branch>\" with an exact org, repo and branch: wildcards, pull_request and environment:<name> subjects are rejected."
  }

  validation {
    condition     = length(var.lambda_uploader_trusted_github_repos) == 0 || var.lambda_uploader_kms_key_alias != null
    error_message = "lambda_uploader_kms_key_alias is required when lambda_uploader_trusted_github_repos is set: the bucket is SSE-KMS."
  }

  validation {
    condition     = length(var.lambda_uploader_trusted_github_repos) == 0 || var.github_oidc_enabled
    error_message = "lambda_uploader_trusted_github_repos needs github_oidc_enabled = true: the uploader role trusts this instance's GitHub OIDC provider, so without it no role would be created."
  }
}

variable "lambda_uploader_kms_key_alias" {
  type        = string
  description = "Alias (\"alias/...\") of the key encrypting the s3/lambda-artifacts bucket (kms/main's alias_name). The uploader role may use it only through S3 in var.region (kms:ViaService). An alias, not a key ARN, because iam/ci applies in the iam layer, before kms/main exists."
  default     = null

  validation {
    condition     = var.lambda_uploader_kms_key_alias == null || can(regex("^alias/[A-Za-z0-9/_-]+$", var.lambda_uploader_kms_key_alias))
    error_message = "lambda_uploader_kms_key_alias must be an \"alias/<name>\" KMS alias."
  }
}

variable "ci_role_max_session_duration" {
  type        = number
  description = "Maximum session duration in seconds for the Lambda uploader role"
  default     = 3600

  validation {
    condition     = var.ci_role_max_session_duration >= 3600 && var.ci_role_max_session_duration <= 43200
    error_message = "ci_role_max_session_duration must be between 3600 and 43200 seconds."
  }
}

