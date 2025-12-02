################################################################################
# General Configuration
################################################################################

variable "name" {
  description = "Name of the CodeBuild project"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9\\-_]{1,254}$", var.name))
    error_message = "Project name must be 2-255 characters, alphanumeric, hyphens, and underscores only."
  }
}

variable "description" {
  description = "Description of the CodeBuild project"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

################################################################################
# IAM Configuration
################################################################################

variable "create_role" {
  description = "Whether to create a new IAM role for the project"
  type        = bool
  default     = true
}

variable "role_arn" {
  description = "ARN of existing IAM role to use (if create_role is false)"
  type        = string
  default     = null
}

variable "role_permissions_boundary" {
  description = "ARN of permissions boundary to attach to IAM role"
  type        = string
  default     = null
}

variable "additional_policy_arns" {
  description = "List of additional IAM policy ARNs to attach to the service role"
  type        = list(string)
  default     = []
}

################################################################################
# Source Configuration
################################################################################

variable "source_type" {
  description = "Type of source (CODECOMMIT, CODEPIPELINE, GITHUB, GITHUB_ENTERPRISE, BITBUCKET, S3, NO_SOURCE)"
  type        = string
  default     = "CODEPIPELINE"

  validation {
    condition     = contains(["CODECOMMIT", "CODEPIPELINE", "GITHUB", "GITHUB_ENTERPRISE", "BITBUCKET", "S3", "NO_SOURCE"], var.source_type)
    error_message = "Invalid source type specified."
  }
}

variable "source_location" {
  description = "Source location URL (required for CODECOMMIT, GITHUB, GITHUB_ENTERPRISE, BITBUCKET, S3)"
  type        = string
  default     = null
}

variable "source_buildspec" {
  description = "Build specification (inline YAML or path to buildspec file)"
  type        = string
  default     = "buildspec.yml"
}

variable "source_git_clone_depth" {
  description = "Git clone depth (0 for full clone)"
  type        = number
  default     = 1
}

variable "source_git_submodules_config" {
  description = "Whether to fetch Git submodules"
  type        = bool
  default     = false
}

variable "source_auth_type" {
  description = "Authentication type for private repositories (OAUTH, BASIC_AUTH, PERSONAL_ACCESS_TOKEN, CODECONNECTIONS)"
  type        = string
  default     = null
}

variable "source_auth_resource" {
  description = "Resource value for authentication (connection ARN for CODECONNECTIONS)"
  type        = string
  default     = null
}

################################################################################
# Build Environment Configuration
################################################################################

variable "environment_compute_type" {
  description = "Compute type (BUILD_GENERAL1_SMALL, BUILD_GENERAL1_MEDIUM, BUILD_GENERAL1_LARGE, BUILD_GENERAL1_2XLARGE)"
  type        = string
  default     = "BUILD_GENERAL1_SMALL"

  validation {
    condition     = contains(["BUILD_GENERAL1_SMALL", "BUILD_GENERAL1_MEDIUM", "BUILD_GENERAL1_LARGE", "BUILD_GENERAL1_2XLARGE"], var.environment_compute_type)
    error_message = "Invalid compute type specified."
  }
}

variable "environment_image" {
  description = "Docker image to use for the build environment"
  type        = string
  default     = "aws/codebuild/standard:7.0"
}

variable "environment_type" {
  description = "Environment type (LINUX_CONTAINER, LINUX_GPU_CONTAINER, ARM_CONTAINER, WINDOWS_SERVER_2019_CONTAINER)"
  type        = string
  default     = "LINUX_CONTAINER"

  validation {
    condition     = contains(["LINUX_CONTAINER", "LINUX_GPU_CONTAINER", "ARM_CONTAINER", "WINDOWS_SERVER_2019_CONTAINER", "WINDOWS_CONTAINER"], var.environment_type)
    error_message = "Invalid environment type specified."
  }
}

variable "environment_privileged_mode" {
  description = "Enable privileged mode (required for Docker builds)"
  type        = bool
  default     = false
}

variable "environment_image_pull_credentials_type" {
  description = "Type of credentials for pulling images (CODEBUILD, SERVICE_ROLE)"
  type        = string
  default     = "CODEBUILD"

  validation {
    condition     = contains(["CODEBUILD", "SERVICE_ROLE"], var.environment_image_pull_credentials_type)
    error_message = "Invalid image pull credentials type."
  }
}

variable "environment_certificate" {
  description = "ARN of S3 bucket with certificate bundle for private CA"
  type        = string
  default     = null
}

################################################################################
# Environment Variables
################################################################################

variable "environment_variables" {
  description = "Environment variables for the build"
  type = list(object({
    name  = string
    value = string
    type  = optional(string) # PLAINTEXT, PARAMETER_STORE, SECRETS_MANAGER
  }))
  default = []
}

################################################################################
# VPC Configuration
################################################################################

variable "enable_vpc_config" {
  description = "Enable VPC configuration for private resource access"
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC ID for CodeBuild project"
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "List of subnet IDs for CodeBuild project"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "List of security group IDs for CodeBuild project"
  type        = list(string)
  default     = []
}

################################################################################
# Artifacts Configuration
################################################################################

variable "artifacts_type" {
  description = "Artifacts type (CODEPIPELINE, S3, NO_ARTIFACTS)"
  type        = string
  default     = "CODEPIPELINE"

  validation {
    condition     = contains(["CODEPIPELINE", "S3", "NO_ARTIFACTS"], var.artifacts_type)
    error_message = "Invalid artifacts type specified."
  }
}

variable "artifacts_location" {
  description = "S3 bucket name for artifacts (required if artifacts_type is S3)"
  type        = string
  default     = null
}

variable "artifacts_path" {
  description = "Path within S3 bucket for artifacts"
  type        = string
  default     = null
}

variable "artifacts_namespace_type" {
  description = "Namespace type for artifacts (BUILD_ID, NONE)"
  type        = string
  default     = "NONE"

  validation {
    condition     = contains(["BUILD_ID", "NONE"], var.artifacts_namespace_type)
    error_message = "Invalid namespace type specified."
  }
}

variable "artifacts_packaging" {
  description = "Packaging type for artifacts (ZIP, NONE)"
  type        = string
  default     = "NONE"

  validation {
    condition     = contains(["ZIP", "NONE"], var.artifacts_packaging)
    error_message = "Invalid packaging type specified."
  }
}

variable "artifacts_encryption_disabled" {
  description = "Disable encryption for artifacts"
  type        = bool
  default     = false
}

variable "artifacts_override_artifact_name" {
  description = "Override artifact name from buildspec"
  type        = bool
  default     = false
}

################################################################################
# Cache Configuration
################################################################################

variable "cache_type" {
  description = "Cache type (NO_CACHE, S3, LOCAL)"
  type        = string
  default     = "NO_CACHE"

  validation {
    condition     = contains(["NO_CACHE", "S3", "LOCAL"], var.cache_type)
    error_message = "Invalid cache type specified."
  }
}

variable "cache_location" {
  description = "S3 bucket name for cache (required if cache_type is S3)"
  type        = string
  default     = null
}

variable "cache_modes" {
  description = "Local cache modes (LOCAL_SOURCE_CACHE, LOCAL_DOCKER_LAYER_CACHE, LOCAL_CUSTOM_CACHE)"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for mode in var.cache_modes : contains(["LOCAL_SOURCE_CACHE", "LOCAL_DOCKER_LAYER_CACHE", "LOCAL_CUSTOM_CACHE"], mode)
    ])
    error_message = "Invalid cache mode specified."
  }
}

################################################################################
# Logging Configuration
################################################################################

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch Logs for build output"
  type        = bool
  default     = true
}

variable "cloudwatch_logs_group_name" {
  description = "CloudWatch Logs group name (auto-generated if not specified)"
  type        = string
  default     = null
}

variable "cloudwatch_logs_stream_name" {
  description = "CloudWatch Logs stream name"
  type        = string
  default     = null
}

variable "enable_s3_logs" {
  description = "Enable S3 logs for build output"
  type        = bool
  default     = false
}

variable "s3_logs_location" {
  description = "S3 bucket name for build logs"
  type        = string
  default     = null
}

variable "s3_logs_encryption_disabled" {
  description = "Disable encryption for S3 logs"
  type        = bool
  default     = false
}

################################################################################
# Build Configuration
################################################################################

variable "build_timeout" {
  description = "Build timeout in minutes (5-480)"
  type        = number
  default     = 60

  validation {
    condition     = var.build_timeout >= 5 && var.build_timeout <= 480
    error_message = "Build timeout must be between 5 and 480 minutes."
  }
}

variable "queued_timeout" {
  description = "Queued timeout in minutes (5-480)"
  type        = number
  default     = 480

  validation {
    condition     = var.queued_timeout >= 5 && var.queued_timeout <= 480
    error_message = "Queued timeout must be between 5 and 480 minutes."
  }
}

variable "build_batch_config" {
  description = "Build batch configuration for parallel builds"
  type = object({
    service_role                  = string
    combine_artifacts             = optional(bool)
    timeout_in_mins               = optional(number)
    restrictions_max_builds       = optional(number)
    restrictions_compute_types    = optional(list(string))
  })
  default = null
}

################################################################################
# Webhook Configuration (for GitHub/Bitbucket)
################################################################################

variable "enable_webhook" {
  description = "Enable webhook for automatic builds on source changes"
  type        = bool
  default     = false
}

variable "webhook_filter_groups" {
  description = "Webhook filter groups for triggering builds"
  type = list(list(object({
    type                    = string # EVENT, BASE_REF, HEAD_REF, ACTOR_ACCOUNT_ID, FILE_PATH, COMMIT_MESSAGE
    pattern                 = string
    exclude_matched_pattern = optional(bool)
  })))
  default = []
}

variable "webhook_build_type" {
  description = "Webhook build type (BUILD, BUILD_BATCH)"
  type        = string
  default     = "BUILD"

  validation {
    condition     = contains(["BUILD", "BUILD_BATCH"], var.webhook_build_type)
    error_message = "Invalid webhook build type."
  }
}

################################################################################
# Additional Configuration
################################################################################

variable "concurrent_build_limit" {
  description = "Maximum number of concurrent builds (1-100)"
  type        = number
  default     = null

  validation {
    condition     = var.concurrent_build_limit == null || (var.concurrent_build_limit >= 1 && var.concurrent_build_limit <= 100)
    error_message = "Concurrent build limit must be between 1 and 100."
  }
}

variable "file_system_locations" {
  description = "EFS file system locations for build"
  type = list(object({
    identifier    = string
    location      = string # EFS DNS name
    mount_point   = string
    type          = string # EFS
    mount_options = optional(string)
  }))
  default = []
}

variable "secondary_sources" {
  description = "List of secondary source configurations"
  type = list(object({
    type                = string
    location            = string
    source_identifier   = string
    git_clone_depth     = optional(number)
    git_submodules      = optional(bool)
    buildspec           = optional(string)
    insecure_ssl        = optional(bool)
    report_build_status = optional(bool)
  }))
  default = []
}

variable "secondary_artifacts" {
  description = "List of secondary artifact configurations"
  type = list(object({
    artifact_identifier = string
    type                = string
    location            = optional(string)
    path                = optional(string)
    namespace_type      = optional(string)
    packaging           = optional(string)
    encryption_disabled = optional(bool)
  }))
  default = []
}
