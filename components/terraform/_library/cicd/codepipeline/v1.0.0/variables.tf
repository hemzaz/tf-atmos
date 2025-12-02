################################################################################
# General Configuration
################################################################################

variable "name" {
  description = "Name of the pipeline"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,98}[a-zA-Z0-9]$", var.name))
    error_message = "Pipeline name must be 1-100 characters, alphanumeric, hyphens, and underscores only."
  }
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
  description = "Whether to create a new IAM role for the pipeline"
  type        = bool
  default     = true
}

variable "role_arn" {
  description = "ARN of existing IAM role to use for pipeline (if create_role is false)"
  type        = string
  default     = null
}

variable "role_permissions_boundary" {
  description = "ARN of permissions boundary to attach to IAM role"
  type        = string
  default     = null
}

################################################################################
# Artifact Store Configuration
################################################################################

variable "artifact_bucket_name" {
  description = "Name of S3 bucket for pipeline artifacts (will be created if not exists)"
  type        = string
}

variable "artifact_encryption_key_id" {
  description = "KMS key ID for encrypting artifacts (if not provided, uses AWS managed key)"
  type        = string
  default     = null
}

variable "artifact_bucket_force_destroy" {
  description = "Force destroy artifact bucket even if it contains objects"
  type        = bool
  default     = false
}

################################################################################
# Source Stage Configuration
################################################################################

variable "source_provider" {
  description = "Source provider type (CodeCommit, GitHub, S3, ECR)"
  type        = string

  validation {
    condition     = contains(["CodeCommit", "GitHub", "S3", "ECR"], var.source_provider)
    error_message = "Source provider must be one of: CodeCommit, GitHub, S3, ECR."
  }
}

variable "source_configuration" {
  description = "Source stage configuration (provider-specific)"
  type = object({
    repository_name      = optional(string) # CodeCommit/GitHub repo name
    branch_name          = optional(string) # Branch to track (default: main)
    connection_arn       = optional(string) # GitHub connection ARN
    bucket_name          = optional(string) # S3 bucket name
    object_key           = optional(string) # S3 object key
    repository_name_ecr  = optional(string) # ECR repository name
    image_tag            = optional(string) # ECR image tag (default: latest)
    poll_for_changes     = optional(bool)   # Enable polling (default: false)
    detect_changes       = optional(bool)   # Use CloudWatch Events (default: true)
  })
}

variable "source_output_artifact" {
  description = "Name of the source output artifact"
  type        = string
  default     = "SourceOutput"
}

################################################################################
# Build Stage Configuration
################################################################################

variable "enable_build_stage" {
  description = "Whether to include a build stage"
  type        = bool
  default     = true
}

variable "build_project_name" {
  description = "Name of existing CodeBuild project for build stage"
  type        = string
  default     = null
}

variable "build_input_artifact" {
  description = "Name of the build input artifact"
  type        = string
  default     = "SourceOutput"
}

variable "build_output_artifact" {
  description = "Name of the build output artifact"
  type        = string
  default     = "BuildOutput"
}

variable "build_environment_variables" {
  description = "Environment variables to pass to build stage"
  type        = list(object({
    name  = string
    value = string
    type  = optional(string) # PLAINTEXT, PARAMETER_STORE, SECRETS_MANAGER
  }))
  default = []
}

################################################################################
# Test Stage Configuration
################################################################################

variable "enable_test_stage" {
  description = "Whether to include a test stage"
  type        = bool
  default     = false
}

variable "test_project_name" {
  description = "Name of existing CodeBuild project for test stage"
  type        = string
  default     = null
}

variable "test_input_artifact" {
  description = "Name of the test input artifact"
  type        = string
  default     = "BuildOutput"
}

################################################################################
# Manual Approval Configuration
################################################################################

variable "enable_manual_approval" {
  description = "Whether to include a manual approval stage"
  type        = bool
  default     = false
}

variable "approval_sns_topic_arn" {
  description = "SNS topic ARN for manual approval notifications"
  type        = string
  default     = null
}

variable "approval_notification_message" {
  description = "Custom notification message for manual approval"
  type        = string
  default     = "Please review and approve the deployment"
}

################################################################################
# Deploy Stage Configuration
################################################################################

variable "deploy_provider" {
  description = "Deploy provider type (CodeDeploy, ECS, Lambda, CloudFormation, S3)"
  type        = string

  validation {
    condition     = contains(["CodeDeploy", "ECS", "Lambda", "CloudFormation", "S3"], var.deploy_provider)
    error_message = "Deploy provider must be one of: CodeDeploy, ECS, Lambda, CloudFormation, S3."
  }
}

variable "deploy_configuration" {
  description = "Deploy stage configuration (provider-specific)"
  type = object({
    # CodeDeploy
    application_name     = optional(string)
    deployment_group     = optional(string)

    # ECS
    cluster_name         = optional(string)
    service_name         = optional(string)
    file_name            = optional(string) # imagedefinitions.json

    # Lambda
    function_name        = optional(string)

    # CloudFormation
    stack_name           = optional(string)
    template_path        = optional(string)
    capabilities         = optional(list(string))
    role_arn             = optional(string)
    parameter_overrides  = optional(map(string))

    # S3
    bucket_name          = optional(string)
    extract              = optional(bool)
    object_key           = optional(string)
  })
}

variable "deploy_input_artifact" {
  description = "Name of the deploy input artifact"
  type        = string
  default     = "BuildOutput"
}

################################################################################
# Cross-Account Deployment
################################################################################

variable "enable_cross_account_deployment" {
  description = "Enable cross-account deployment capabilities"
  type        = bool
  default     = false
}

variable "cross_account_role_arns" {
  description = "List of IAM role ARNs in target accounts for cross-account deployment"
  type        = list(string)
  default     = []
}

################################################################################
# Notifications and Monitoring
################################################################################

variable "enable_notifications" {
  description = "Enable CloudWatch Events for pipeline notifications"
  type        = bool
  default     = true
}

variable "notification_events" {
  description = "Pipeline events to trigger notifications"
  type        = list(string)
  default = [
    "codepipeline-pipeline-pipeline-execution-failed",
    "codepipeline-pipeline-pipeline-execution-succeeded"
  ]
}

variable "notification_target_arn" {
  description = "ARN of SNS topic or Lambda function for notifications"
  type        = string
  default     = null
}

################################################################################
# Pipeline Configuration
################################################################################

variable "pipeline_type" {
  description = "Pipeline type (V1 or V2)"
  type        = string
  default     = "V2"

  validation {
    condition     = contains(["V1", "V2"], var.pipeline_type)
    error_message = "Pipeline type must be V1 or V2."
  }
}

variable "execution_mode" {
  description = "Execution mode for V2 pipelines (QUEUED, SUPERSEDED, PARALLEL)"
  type        = string
  default     = "SUPERSEDED"

  validation {
    condition     = contains(["QUEUED", "SUPERSEDED", "PARALLEL"], var.execution_mode)
    error_message = "Execution mode must be QUEUED, SUPERSEDED, or PARALLEL."
  }
}

variable "enable_pipeline" {
  description = "Enable or disable the pipeline"
  type        = bool
  default     = true
}
