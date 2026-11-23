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
# GitHub Actions OIDC CI roles (all optional; off unless github_oidc_enabled)
# ---------------------------------------------------------------------------
variable "github_oidc_enabled" {
  type        = bool
  description = "Create the GitHub Actions OIDC CI roles"
  default     = false
}

variable "github_oidc_repository" {
  type        = string
  description = "GitHub repository (\"<org>/<repo>\") whose OIDC tokens may assume the CI roles"
  default     = null

  validation {
    condition     = var.github_oidc_repository == null || can(regex("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$", var.github_oidc_repository))
    error_message = "github_oidc_repository must be \"<org>/<repo>\"; a wildcard would let any repository assume the CI roles."
  }

  validation {
    condition     = !var.github_oidc_enabled || var.github_oidc_repository != null
    error_message = "github_oidc_repository is required when github_oidc_enabled is true."
  }
}

variable "github_oidc_default_branch" {
  type        = string
  description = "Branch whose ref the plan role trusts (drift-detection and disaster-recovery run there)"
  default     = "main"

  validation {
    condition     = can(regex("^[A-Za-z0-9._/-]+$", var.github_oidc_default_branch))
    error_message = "github_oidc_default_branch must be a branch name with no wildcard."
  }
}

variable "github_oidc_create_provider" {
  type        = bool
  description = "Create the token.actions.githubusercontent.com OIDC provider. Leave false when the account already has one and set github_oidc_provider_arn instead."
  default     = false
}

variable "github_oidc_provider_arn" {
  type        = string
  description = "ARN of an existing GitHub Actions OIDC provider to trust"
  default     = null

  validation {
    condition     = var.github_oidc_provider_arn == null || can(regex("^arn:aws:iam::\\d{12}:oidc-provider/token\\.actions\\.githubusercontent\\.com$", var.github_oidc_provider_arn))
    error_message = "github_oidc_provider_arn must be an arn:aws:iam::<account>:oidc-provider/token.actions.githubusercontent.com ARN."
  }

  validation {
    condition = !var.github_oidc_enabled || (
      var.github_oidc_create_provider && var.github_oidc_provider_arn == null
      ) || (
      !var.github_oidc_create_provider && var.github_oidc_provider_arn != null
    )
    error_message = "Set exactly one of github_oidc_create_provider = true or github_oidc_provider_arn when github_oidc_enabled is true."
  }
}

variable "ci_role_name_prefix" {
  type        = string
  description = "Name prefix for the CI roles: the plan role is \"<prefix>-plan\" and the apply role \"<prefix>-apply\""
  default     = null

  validation {
    # 64 minus the longest "-apply" suffix
    condition     = var.ci_role_name_prefix == null || can(regex("^[\\w+=,.@-]{1,58}$", var.ci_role_name_prefix))
    error_message = "ci_role_name_prefix must be 1-58 characters of alphanumerics or +=,.@_-."
  }

  validation {
    condition     = !var.github_oidc_enabled || var.ci_role_name_prefix != null
    error_message = "ci_role_name_prefix is required when github_oidc_enabled is true."
  }
}

variable "ci_plan_role_subjects" {
  type        = list(string)
  description = "Exact GitHub OIDC `sub` claims the plan role trusts. Null derives repo:<repository>:pull_request and repo:<repository>:ref:refs/heads/<default branch>."
  default     = null

  validation {
    condition = var.ci_plan_role_subjects == null || (
      length(coalesce(var.ci_plan_role_subjects, [])) > 0 && alltrue([
        for subject in coalesce(var.ci_plan_role_subjects, []) :
        can(regex("^repo:[A-Za-z0-9._-]+/[A-Za-z0-9._-]+:[A-Za-z0-9._/:-]+$", subject))
      ])
    )
    error_message = "Each ci_plan_role_subjects entry must be a fully qualified subject (repo:<org>/<repo>:<claim>), non-empty and free of wildcards; an unbounded sub lets any repository assume the role."
  }
}

variable "ci_plan_policy_arns" {
  type        = list(string)
  description = "Managed policy ARNs attached to the plan role. Must stay read-only: plans run pull-request code."
  default     = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]

  validation {
    condition     = alltrue([for arn in var.ci_plan_policy_arns : can(regex("^arn:aws:iam::(aws|\\d{12}):policy/", arn))])
    error_message = "Each ci_plan_policy_arns entry must be an IAM policy ARN."
  }

  validation {
    condition     = !anytrue([for arn in var.ci_plan_policy_arns : endswith(arn, "/AdministratorAccess") || endswith(arn, "/PowerUserAccess")])
    error_message = "The plan role is assumed by pull-request workflows, so AdministratorAccess and PowerUserAccess must not be attached to it."
  }
}

variable "ci_apply_role_enabled" {
  type        = bool
  description = "Also create the apply role, assumable only from the branch-pinned repositories in ci_apply_role_trusted_github_repos"
  default     = false
}

variable "ci_apply_role_trusted_github_repos" {
  type        = list(string)
  description = <<-EOT
    GitHub repositories whose OIDC tokens may assume the apply role, each "<org>/<repo>:<branch>".
    Shape of Cloud Posse's `trusted_github_repos` (cloudposse/terraform-aws-components,
    modules/account-map/modules/team-assume-role-policy/github-assume-role-policy.mixin.tf), which
    turns "<org>/<repo>:<branch>" into the subject "repo:<org>/<repo>:ref:refs/heads/<branch>".
    Unlike upstream, the branch is required and matched with StringEquals: upstream's branch-less
    form ("repo:<org>/<repo>:*") would also admit pull_request and environment subjects.
  EOT
  default     = []

  validation {
    # org/repo:branch - no "*", no extra ":" (so no environment:<name> or ref: forms)
    condition = alltrue(flatten([
      for repo in var.ci_apply_role_trusted_github_repos : [
        can(regex("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+:[A-Za-z0-9._/-]+$", repo)),
        !strcontains(repo, "*"),
        !strcontains(repo, "environment:"),
        !endswith(repo, ":pull_request"),
      ]
    ]))
    error_message = "Each ci_apply_role_trusted_github_repos entry must be \"<org>/<repo>:<branch>\" with an exact branch: wildcards, pull_request and environment:<name> subjects are rejected (deploy credentials must never reach PR-controlled code)."
  }

  validation {
    condition     = !var.ci_apply_role_enabled || length(var.ci_apply_role_trusted_github_repos) > 0
    error_message = "ci_apply_role_trusted_github_repos must name at least one \"<org>/<repo>:<branch>\" when ci_apply_role_enabled is true; an empty list would leave the apply role with no subject condition."
  }
}

variable "ci_apply_policy_arns" {
  type        = list(string)
  description = "Managed policy ARNs attached to the apply role. No default: only the caller knows what its stacks deploy."
  default     = []

  validation {
    condition     = alltrue([for arn in var.ci_apply_policy_arns : can(regex("^arn:aws:iam::(aws|\\d{12}):policy/", arn))])
    error_message = "Each ci_apply_policy_arns entry must be an IAM policy ARN."
  }

  validation {
    condition     = !var.ci_apply_role_enabled || length(var.ci_apply_policy_arns) > 0
    error_message = "ci_apply_policy_arns must be set when ci_apply_role_enabled is true."
  }
}

variable "ci_backend_read_role_arns" {
  type        = list(string)
  description = "ARNs of the state backend's READ-only access roles the plan role may assume: its own stage's (backend role fnx-terraform-backend-read-role for dev/staging, fnx-terraform-backend-prod-read-role for prod). Empty skips the grant."
  default     = []

  validation {
    condition     = alltrue([for arn in var.ci_backend_read_role_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[\\w+=,.@/-]+$", arn))])
    error_message = "Each ci_backend_read_role_arns entry must be an IAM role ARN."
  }
}

variable "ci_backend_write_role_arn" {
  type        = string
  description = "ARN of the state backend's read/write access role for this role's stage (fnx-terraform-backend-role for dev/staging, fnx-terraform-backend-prod-role for prod); the apply role gets sts:AssumeRole on it and on nothing else in the backend. Null skips the grant."
  default     = null

  validation {
    condition     = var.ci_backend_write_role_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[\\w+=,.@/-]+$", var.ci_backend_write_role_arn))
    error_message = "ci_backend_write_role_arn must be an IAM role ARN."
  }
}

variable "ci_apply_kms_key_aliases" {
  type        = list(string)
  description = "KMS alias(es) (with the \"alias/\" prefix, e.g. kms/main's alias_name) the apply role deploys resources against: grants kms:DescribeKey/CreateGrant/ListGrants/RevokeGrant/Encrypt/Decrypt/ReEncrypt*/GenerateDataKey*, scoped via a kms:ResourceAliases condition rather than a key ARN. This component's iam/ci instance plans and applies in the layer BEFORE kms/main (workflows/deploy-full-stack.yaml), so a key ARN is not known yet -- a !terraform.state read of kms/main here would make iam depend on kms while kms/main already depends on iam (allow_autoscaling_ebs's service-linked role), a cycle. AWS derives kms:ResourceAliases from the KMS key the operation actually acts on, regardless of how the request named it, so scoping by alias on resources = [\"*\"] is still an exact-match grant, not a wildcard one."
  default     = null

  validation {
    condition     = var.ci_apply_kms_key_aliases == null || alltrue([for a in var.ci_apply_kms_key_aliases : can(regex("^alias/", a))])
    error_message = "ci_apply_kms_key_aliases entries must include the \"alias/\" prefix."
  }
}

variable "lambda_uploader_trusted_github_repos" {
  type        = list(string)
  description = <<-EOT
    Application repositories whose CI may upload Lambda packages to this stage's s3/lambda-artifacts
    bucket through the "<ci_role_name_prefix>-lambda-uploader" role, each "<org>/<repo>:<branch>"
    (the shape of ci_apply_role_trusted_github_repos; sub "repo:<org>/<repo>:ref:refs/heads/<branch>",
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
  description = "Alias (\"alias/...\") of the key encrypting the s3/lambda-artifacts bucket (kms/main's alias_name). The uploader role may use it only through S3 in var.region (kms:ViaService). An alias, not a key ARN, for the same layer-order reason as ci_apply_kms_key_aliases."
  default     = null

  validation {
    condition     = var.lambda_uploader_kms_key_alias == null || can(regex("^alias/[A-Za-z0-9/_-]+$", var.lambda_uploader_kms_key_alias))
    error_message = "lambda_uploader_kms_key_alias must be an \"alias/<name>\" KMS alias."
  }
}

variable "ci_role_max_session_duration" {
  type        = number
  description = "Maximum session duration in seconds for the CI roles"
  default     = 3600

  validation {
    condition     = var.ci_role_max_session_duration >= 3600 && var.ci_role_max_session_duration <= 43200
    error_message = "ci_role_max_session_duration must be between 3600 and 43200 seconds."
  }
}

variable "ci_runner_pool_names" {
  type        = list(string)
  description = "Auto Scaling groups of this stack's self-hosted runner pools (github-runners' autoscaling_group_name, <Environment>-<name>): the CI roles may execute their start policies only, to start runners (ci-runner-pools.tf). Empty grants nothing"
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for n in var.ci_runner_pool_names : can(regex("^[A-Za-z0-9._-]{1,255}$", n))])
    error_message = "ci_runner_pool_names must be Auto Scaling group names (letters, digits, '.', '_', '-'; no wildcards)."
  }
}
