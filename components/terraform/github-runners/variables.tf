variable "region" {
  type        = string
  description = "AWS region"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "The region must be a valid AWS region name (e.g., us-east-1, eu-west-1)."
  }
}

# Required on purpose: a `default = {}` here makes every resource look untagged to
# tflint/checkov, which run per-component without stack vars. Keep it required.
variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources; must include Environment (used in resource names)"

  validation {
    condition     = trimspace(lookup(var.tags, "Environment", "")) != ""
    error_message = "tags must include a non-empty Environment value."
  }
}

variable "enabled" {
  type        = bool
  description = "Set to false to prevent the component from creating any resources"
  default     = true
}

variable "name" {
  type        = string
  description = "Short name; resources are <Environment>-<name>"
  default     = "github-runners"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,30}$", var.name))
    error_message = "name must be 1-31 lowercase letters, digits or hyphens."
  }
}

# Cloud Posse reads these from its vpc component's remote state.
variable "vpc_id" {
  type        = string
  description = "VPC the runners run in: the one whose private EKS endpoints they must reach"

  validation {
    condition     = can(regex("^vpc-[a-f0-9]+$", var.vpc_id))
    error_message = "vpc_id must be a VPC ID (vpc-...)."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets for the runners (a vpc instance's .private_subnet_ids); they need a NAT path to GitHub"

  validation {
    condition     = length(var.subnet_ids) > 0 && alltrue([for s in var.subnet_ids : can(regex("^subnet-[a-f0-9]+$", s))])
    error_message = "subnet_ids must be one or more subnet IDs (subnet-...)."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "Customer managed key (kms/main) that encrypts the runners' root volumes, the JIT configuration parameters and the jit function's log group. The App's private key is on this component's own key instead"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN."
  }
}

# Cloud Posse aws-github-runners' inputs, as typed as theirs.
variable "github_scope" {
  type        = string
  description = "Scope the runners register to: owner/repository (repository runners) or an organization (Cloud Posse's github_scope)"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,38}(/[A-Za-z0-9._-]{1,100})?$", var.github_scope))
    error_message = "github_scope must be owner/repository or an organization name."
  }
}

variable "runner_labels" {
  type        = list(string)
  description = "Labels the runners register with besides self-hosted, linux and x64 (which the jit function adds). CI routes a stack's jobs by its full id, <tenant>-<environment>-<stage>"

  validation {
    condition     = length(var.runner_labels) > 0 && alltrue([for l in var.runner_labels : can(regex("^[A-Za-z0-9._-]{1,100}$", l))])
    error_message = "runner_labels needs at least one label of letters, digits, '.', '_' or '-' (no commas or spaces)."
  }
}

# Cloud Posse's runner_group names the group; the JIT API takes its ID.
variable "runner_group_id" {
  type        = number
  description = "Runner group ID the JIT runners join. 1 is the Default group, the only one a repository has"
  default     = 1

  validation {
    condition     = var.runner_group_id >= 1 && floor(var.runner_group_id) == var.runner_group_id
    error_message = "runner_group_id must be a positive integer."
  }
}

variable "runner_version" {
  type        = string
  description = "GitHub Actions runner release (e.g. 2.337.0). Pinned, unlike Cloud Posse's install of the latest release; bump it, with runner_sha256, before GitHub stops accepting the release"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.runner_version))
    error_message = "runner_version must be a release number such as 2.329.0, without a leading v."
  }
}

variable "runner_sha256" {
  type        = string
  description = "SHA-256 of actions-runner-linux-x64-<runner_version>.tar.gz, from the release notes; the bootstrap refuses any other file"

  validation {
    condition     = can(regex("^[a-f0-9]{64}$", var.runner_sha256))
    error_message = "runner_sha256 must be 64 lowercase hex characters."
  }
}

variable "idle_timeout_seconds" {
  type        = number
  description = "A runner that gets no job within this many seconds of starting terminates itself"
  default     = 900

  validation {
    condition     = var.idle_timeout_seconds >= 300 && var.idle_timeout_seconds <= 7200
    error_message = "idle_timeout_seconds must be between 300 and 7200."
  }
}

# Not in Cloud Posse aws-github-runners, which reads a registration token (or
# PAT) from ssm_path/ssm_path_key (see README): here the jit function
# authenticates as a GitHub App and hands each instance a single-use JIT
# runner configuration.
variable "github_app_id" {
  type        = string
  description = "GitHub App ID (the App's settings page, \"App ID\"); not a secret"

  validation {
    condition     = can(regex("^[0-9]+$", var.github_app_id))
    error_message = "github_app_id must be the App's numeric ID."
  }
}

variable "github_app_installation_id" {
  type        = string
  description = "GitHub App installation ID (the number at the end of the installation's settings URL); not a secret"

  validation {
    condition     = can(regex("^[0-9]+$", var.github_app_installation_id))
    error_message = "github_app_installation_id must be the installation's numeric ID."
  }
}

variable "github_app_private_key_parameter_name" {
  type        = string
  description = "SSM SecureString holding the App's private key (PEM, or base64 of the PEM), written by hand with this pool's app key (.app_key_kms_key_alias); null for /github/runners/<name>/app-private-key. Never in the state: only the jit function reads it"
  default     = null

  validation {
    condition     = var.github_app_private_key_parameter_name == null || can(regex("^/[A-Za-z0-9_./-]+$", coalesce(var.github_app_private_key_parameter_name, "-")))
    error_message = "github_app_private_key_parameter_name must be an absolute SSM parameter path."
  }
}

variable "jit_parameter_prefix" {
  type        = string
  description = "SSM path under which the jit function writes each instance's JIT configuration (<prefix>/<instance id>); null for /github/runners/<name>/jit, so two pools in one account never share a path (or the IAM scopes on it)"
  default     = null

  validation {
    condition     = var.jit_parameter_prefix == null || can(regex("^/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$", coalesce(var.jit_parameter_prefix, "-")))
    error_message = "jit_parameter_prefix must be an absolute SSM path without a trailing slash."
  }
}

variable "allowed_refs" {
  type        = list(string)
  description = "When non-empty, a runner also fails any job whose GITHUB_REF is not one of these refs before its first step (the runner's job-started hook, files/job-started.sh, which always enforces the fork guard and which a workflow cannot change). A production pool sets [\"refs/heads/master\"]: its runners then serve master's push, dispatch and schedule runs only, whatever a pull request's workflow asks for. Empty: any job with the pool's labels"
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for r in var.allowed_refs : can(regex("^refs/(heads|tags)/[A-Za-z0-9._/-]+$", r))])
    error_message = "allowed_refs must be full refs such as refs/heads/master (letters, digits, '.', '_', '/', '-')."
  }
}

variable "lifecycle_heartbeat_timeout" {
  type        = number
  description = "Seconds the launch hook holds an instance for the jit function before abandoning (terminating) it"
  default     = 300

  validation {
    condition     = var.lifecycle_heartbeat_timeout >= 30 && var.lifecycle_heartbeat_timeout <= 7200
    error_message = "lifecycle_heartbeat_timeout must be between 30 and 7200."
  }
}

variable "alarm_sns_topic_arns" {
  type        = list(string)
  description = "SNS topics the jit function's error alarm notifies (e.g. a monitoring instance's .sns_topic_arn); empty for an alarm without actions"
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for a in var.alarm_sns_topic_arns : can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]+$", a))])
    error_message = "alarm_sns_topic_arns must be SNS topic ARNs."
  }
}

variable "log_retention_days" {
  type        = number
  description = "Days the jit function's log group keeps its logs"
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a CloudWatch Logs retention value (1, 3, 5, 7, 14, 30, 60, 90, ...)."
  }
}

variable "instance_type" {
  type        = string
  description = "Instance type of the runners"
  default     = "t3.medium"
}

variable "min_size" {
  type        = number
  description = "Minimum runners. 0: CI starts them with the +1 start policy"
  default     = 0

  validation {
    condition     = var.min_size >= 0
    error_message = "min_size must not be negative."
  }
}

variable "max_size" {
  type        = number
  description = "Maximum runners (concurrent jobs, when ephemeral)"
  default     = 4

  validation {
    condition     = var.max_size >= 1 && var.max_size >= var.min_size
    error_message = "max_size must be at least 1 and at least min_size."
  }
}

variable "max_instance_lifetime" {
  type        = number
  description = "Seconds an instance may live (0 or 86400-31536000); a backstop for runners that never leave. Null for none"
  default     = 86400

  validation {
    condition     = var.max_instance_lifetime == null || try(var.max_instance_lifetime == 0 || (var.max_instance_lifetime >= 86400 && var.max_instance_lifetime <= 31536000), false)
    error_message = "max_instance_lifetime must be null, 0, or between 86400 and 31536000 seconds."
  }
}

variable "root_volume_size" {
  type        = number
  description = "Root volume size in GiB (gp3): the atmos image, provider plugins and Terraform working directories"
  default     = 40

  validation {
    condition     = var.root_volume_size >= 20 && var.root_volume_size <= 1000
    error_message = "root_volume_size must be between 20 and 1000 GiB."
  }
}

variable "ami_ssm_parameter_name" {
  type        = string
  description = "Public SSM parameter naming the AMI (the latest Amazon Linux 2023). Cloud Posse looks the AMI up with ami_filter/ami_owners instead"
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

variable "userdata_pre_install" {
  type        = string
  description = "Shell run before the runner is installed (Cloud Posse's userdata_pre_install)"
  default     = ""
}

variable "userdata_post_install" {
  type        = string
  description = "Shell run after the runner is configured, before it starts (Cloud Posse's userdata_post_install)"
  default     = ""
}

variable "runner_role_additional_policy_arns" {
  type        = list(string)
  description = "Managed policies attached to the runners' instance role besides the defaults (Cloud Posse's input). Terraform jobs need none: they assume the stack's iam/ci roles through GitHub OIDC"
  default     = []
}
