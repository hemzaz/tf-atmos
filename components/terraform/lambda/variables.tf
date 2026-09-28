variable "region" {
  type        = string
  description = "AWS region"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "The region must be a valid AWS region name (e.g., us-east-1, eu-west-1)."
  }
}

variable "function_name" {
  type        = string
  description = "Name of the Lambda function"
}

variable "handler" {
  type        = string
  description = "Lambda function handler"
}

variable "runtime" {
  type        = string
  description = "Lambda function runtime"
  default     = "nodejs22.x"
}

variable "filename" {
  type        = string
  description = "Path to the Lambda function's deployment package"
  default     = null
}

variable "source_code_hash" {
  type        = string
  description = "Base64-encoded SHA256 hash of the package file"
  default     = null
}

variable "s3_bucket" {
  type        = string
  description = "S3 bucket containing the Lambda function's deployment package"
  default     = null
}

variable "s3_key" {
  type        = string
  description = "S3 key of the Lambda function's deployment package"
  default     = null
}

variable "s3_object_version" {
  type        = string
  description = "S3 object version of the Lambda function's deployment package"
  default     = null
}

variable "source_dir" {
  type        = string
  description = "A directory under this component (e.g. \"functions/redis-auth-rotation\", resolved relative to path.module) that the component zips itself via the archive_file data source, producing filename/source_code_hash internally -- for small, in-repo function sources (e.g. Secrets Manager rotation functions) that do not warrant an external build pipeline. Mutually exclusive with filename and s3_bucket+s3_key (validated on aws_lambda_function.main): exactly one packaging source is required for package_type = \"Zip\"."
  default     = null
}

variable "layers" {
  type        = list(string)
  description = "List of Lambda layer ARNs to attach"
  default     = []
}

variable "memory_size" {
  type        = number
  description = "Amount of memory in MB for the Lambda function"
  default     = 128
}

variable "timeout" {
  type        = number
  description = "Timeout in seconds for the Lambda function"
  default     = 3
}

variable "publish" {
  type        = bool
  description = "Whether to publish a new Lambda function version"
  default     = false
}

variable "environment_variables" {
  type        = map(string)
  description = "Environment variables for the Lambda function"
  default     = {}
}

variable "kms_key_arn" {
  type        = string
  description = "KMS key ARN for encrypting Lambda environment variables"
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws:kms:", var.kms_key_arn))
    error_message = "KMS key ARN must be a valid AWS KMS key ARN or null."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for Lambda function"
  default     = null
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs for the Lambda function"
  default     = []
}

variable "dead_letter_target_arn" {
  type        = string
  description = "ARN of the SQS queue or SNS topic for the dead letter target"
  default     = null
}

variable "tracing_mode" {
  type        = string
  description = "X-Ray tracing mode (PassThrough or Active)"
  default     = null
}

variable "log_retention_days" {
  type        = number
  description = "Number of days to retain Lambda logs"
  default     = 7
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ID for log encryption"
  default     = null
}

variable "custom_policy" {
  type        = string
  description = "Custom IAM policy for the Lambda function"
  default     = ""
}

variable "api_gateway_source_arn" {
  type        = string
  description = "ARN of the API Gateway that invokes the Lambda function"
  default     = null
}

variable "s3_source_arn" {
  type        = string
  description = "ARN of the S3 bucket that invokes the Lambda function"
  default     = null
}

variable "cloudwatch_source_arn" {
  type        = string
  description = "ARN of the CloudWatch Events rule that invokes the Lambda function"
  default     = null
}

variable "sns_source_arn" {
  type        = string
  description = "ARN of the SNS topic that invokes the Lambda function"
  default     = null
}

variable "secretsmanager_source_arn" {
  type        = string
  description = "ARN of the Secrets Manager secret that invokes this Lambda as its rotation function. Adds a resource-based permission for principal secretsmanager.amazonaws.com, scoped by aws:SourceArn (this secret) and aws:SourceAccount (this account) -- the two conditions AWS's rotation documentation requires so no other secret or account can invoke the function. Pair with rotation_secret_arn set to the SAME secret's ARN to also configure that secret's rotation from this component instance (see rotation_secret_arn's own description for why that must happen here, not on the secretsmanager component, when this function itself reads the secret)."
  default     = null

  validation {
    condition     = var.secretsmanager_source_arn == null || can(regex("^arn:aws[a-z-]*:secretsmanager:[a-z0-9-]+:[0-9]{12}:secret:.+$", var.secretsmanager_source_arn))
    error_message = "secretsmanager_source_arn must be a Secrets Manager secret ARN (arn:aws:secretsmanager:<region>:<account-id>:secret:<name>)."
  }
}

variable "rotation_secret_arn" {
  type        = string
  description = "ARN of the Secrets Manager secret to configure THIS function as the rotation Lambda for (aws_secretsmanager_secret_rotation, depends_on the secretsmanager.amazonaws.com invoke permission and this function's own IAM role policies below). Configuring rotation on the secretsmanager component instead is only safe when that function already exists and is invokable at the SECRET's own apply time -- a function that itself reads the secret (the common case, to scope its own custom_policy) cannot satisfy that on the secret's first apply, because Secrets Manager's RotateSecret API invokes the function -- at minimum running its testSecret step against a temporary AWSPENDING version it creates and then removes -- even when rotate_immediately is false. Configuring it here instead is safe: this Lambda instance already depends on the secret's own component instance (to read this ARN and to scope its own IAM policy), so by the time THIS resource applies, the function, its invoke permission and its IAM policies already exist. Pair with secretsmanager_source_arn set to the SAME secret's ARN (enforced by a precondition), and set the secretsmanager component's own secret entry to rotation_managed_externally = true instead of rotation_lambda_arn/rotation_automatically. For a secret with an external system to update (e.g. the redis-auth-rotation function's ElastiCache replication group), also set rotate_immediately = true here once this resource's own dependency ordering is safe: at rotate_immediately = false, only testSecret runs, against a temporary AWSPENDING version Secrets Manager itself creates for the test, so setSecret -- the step that actually pushes a new value to the external system -- never runs, and this path never performs or verifies a real end-to-end rotation (a testSecret that depends on setSecret's push, like redis-auth-rotation's, is exercised only against the AWSPENDING version's own test-time value, not a value setSecret pushed)."
  default     = null

  validation {
    condition     = var.rotation_secret_arn == null || can(regex("^arn:aws[a-z-]*:secretsmanager:[a-z0-9-]+:[0-9]{12}:secret:.+$", var.rotation_secret_arn))
    error_message = "rotation_secret_arn must be a Secrets Manager secret ARN (arn:aws:secretsmanager:<region>:<account-id>:secret:<name>)."
  }
}

variable "rotation_days" {
  type        = number
  description = "Days between automatic rotations of rotation_secret_arn. Ignored when rotation_secret_arn is null."
  default     = 30

  validation {
    condition     = var.rotation_days >= 1 && var.rotation_days <= 365
    error_message = "rotation_days must be between 1 and 365."
  }
}

variable "rotate_immediately" {
  type        = bool
  description = "Whether configuring rotation on rotation_secret_arn invokes this function right away (the AWS provider's own default for aws_secretsmanager_secret_rotation is true), versus only testing the configuration and waiting for the first scheduled rotation window. Default false, matching the secretsmanager component's own default_rotate_immediately. Ignored when rotation_secret_arn is null. When true, any LATER change to this resource (e.g. rotation_days, or a new rotation_lambda_arn from a function rename/replacement) also re-invokes RotateSecret with RotateImmediately = true, triggering an unscheduled rotation at that apply -- not just the first one."
  default     = false
}

variable "configure_event_invoke" {
  type        = bool
  description = "Whether to configure event invoke settings"
  default     = false
}

variable "maximum_retry_attempts" {
  type        = number
  description = "Maximum number of retry attempts for async invocation"
  default     = 2
}

variable "maximum_event_age_in_seconds" {
  type        = number
  description = "Maximum age of events in seconds"
  default     = 60
}

variable "on_success_destination" {
  type        = string
  description = "ARN of destination resource for successful invocations"
  default     = null
}

variable "on_failure_destination" {
  type        = string
  description = "ARN of destination resource for failed invocations"
  default     = null
}

variable "delivery_kms_key_arn" {
  type        = string
  description = "Customer managed KMS key ARN of the SQS queues / SNS topics in on_success_destination, on_failure_destination and dead_letter_target_arn; the execution role gets kms:GenerateDataKey and kms:Decrypt on it (the role always gets sqs:SendMessage / sns:Publish on those ARNs)"
  default     = null

  validation {
    condition     = var.delivery_kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.delivery_kms_key_arn))
    error_message = "delivery_kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>)."
  }
}

variable "create_alias" {
  type        = bool
  description = "Whether to create an alias for the Lambda function"
  default     = false
}

variable "alias_name" {
  type        = string
  description = "Name of the Lambda function alias"
  default     = "live"
}

variable "alias_description" {
  type        = string
  description = "Description of the Lambda function alias"
  default     = "Live alias"
}

variable "alias_function_version" {
  type        = string
  description = "Version of the Lambda function to use in the alias"
  default     = "$LATEST"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources; must include Environment (used in resource names)"

  validation {
    condition     = trimspace(lookup(var.tags, "Environment", "")) != ""
    error_message = "tags must include a non-empty Environment value."
  }
}

# Performance Optimization Variables
variable "reserved_concurrent_executions" {
  type        = number
  description = "Amount of reserved concurrent executions for the Lambda function"
  default     = null
  validation {
    condition     = var.reserved_concurrent_executions == null || var.reserved_concurrent_executions >= 0
    error_message = "Reserved concurrent executions must be 0 or greater."
  }
}

variable "provisioned_concurrency_config" {
  type = object({
    provisioned_concurrent_executions = number
    qualifier                         = string
  })
  description = "Provisioned concurrency configuration"
  default     = null
}

variable "routing_config" {
  type = object({
    additional_version_weights = map(number)
  })
  description = "Blue/Green deployment routing configuration"
  default     = null
}

variable "telemetry_log_level" {
  type        = string
  description = "Telemetry log level for Lambda function"
  default     = "WARN"
  validation {
    condition     = contains(["TRACE", "DEBUG", "INFO", "WARN", "ERROR", "FATAL"], var.telemetry_log_level)
    error_message = "Telemetry log level must be one of: TRACE, DEBUG, INFO, WARN, ERROR, FATAL."
  }
}

variable "enable_snapstart" {
  type        = bool
  description = "Enable SnapStart for Java Lambda functions"
  default     = false
}

variable "package_type" {
  type        = string
  description = "Lambda deployment package type (Zip or Image)"
  default     = "Zip"
  validation {
    condition     = contains(["Zip", "Image"], var.package_type)
    error_message = "Package type must be either 'Zip' or 'Image'."
  }
}

variable "architectures" {
  type        = list(string)
  description = "Instruction set architectures supported by the function"
  default     = ["x86_64"]
  validation {
    condition     = alltrue([for arch in var.architectures : contains(["x86_64", "arm64"], arch)])
    error_message = "Architectures must be 'x86_64' and/or 'arm64'."
  }
}

# Container Image Configuration
variable "image_command" {
  type        = list(string)
  description = "Parameters that you want to pass in with entry_point"
  default     = []
}

variable "image_entry_point" {
  type        = list(string)
  description = "Entry point to the application"
  default     = []
}

variable "image_working_directory" {
  type        = string
  description = "Working directory for the Lambda function"
  default     = null
}

# EFS Configuration
variable "efs_access_point_arn" {
  type        = string
  description = "EFS access point ARN for Lambda function"
  default     = null
}

variable "efs_local_mount_path" {
  type        = string
  description = "Local mount path for EFS"
  default     = "/mnt/efs"
}

# Enhanced Security Variables
variable "database_port" {
  type        = number
  description = "Database port for security group egress rule"
  default     = null
}

variable "database_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks for database access"
  default     = []
}

variable "additional_security_group_ids" {
  type        = list(string)
  description = "Extra security group IDs to attach to this function's VPC-attached ENI, alongside the one this component creates itself (aws_security_group.lambda). For example, a cache's client security group (e.g. elasticache's client_security_group_id), so that cache's own security group never has to read this function's security group back -- which would create a dependency cycle for a function that already reads the cache's outputs. Ignored when subnet_ids is empty."
  default     = []

  validation {
    condition     = alltrue([for sg in var.additional_security_group_ids : can(regex("^sg-[a-f0-9]+$", sg))])
    error_message = "Each entry must be a valid security group ID (e.g. sg-0123456789abcdef0)."
  }
}

variable "custom_egress_rules" {
  type = list(object({
    description     = string
    from_port       = number
    to_port         = number
    protocol        = string
    cidr_blocks     = optional(list(string))
    security_groups = optional(list(string))
  }))
  description = "Custom egress rules for Lambda security group"
  default     = []
}

# Performance Monitoring Variables
variable "create_performance_alarms" {
  type        = bool
  description = "Whether to create performance monitoring alarms"
  default     = false
}

variable "duration_alarm_threshold" {
  type        = number
  description = "Duration alarm threshold in milliseconds"
  default     = 30000
}

variable "error_rate_alarm_threshold" {
  type        = number
  description = "Error rate alarm threshold"
  default     = 5
}

variable "throttle_alarm_threshold" {
  type        = number
  description = "Throttle alarm threshold"
  default     = 1
}

variable "sns_topic_arn" {
  type        = string
  description = "SNS topic ARN for alarm notifications"
  default     = null
}

# Scheduling Variables
variable "schedule_expression" {
  type        = string
  description = "CloudWatch Events schedule expression"
  default     = null
}

variable "schedule_enabled" {
  type        = bool
  description = "Whether the schedule is enabled"
  default     = true
}

variable "schedule_input" {
  type        = string
  description = "JSON input for scheduled Lambda invocation"
  default     = null
}

# Network Security Variables
variable "vpc_endpoint_prefix_list_ids" {
  type        = list(string)
  description = "VPC endpoint prefix list IDs for egress from a VPC-attached Lambda (replaces 0.0.0.0/0). Empty resolves the region's AWS-managed S3 prefix list; see data.aws_ec2_managed_prefix_list.s3 in main.tf."
  default     = []

  # This variable deliberately has NO validation requiring a non-empty value
  # when subnet_ids is set. It used to, and the result was that every VPC
  # lambda in every stack failed at plan with "Invalid value for variable",
  # because a prefix list id is region-specific and no stack ever set one.
  # Empty is now a resolved default, not a hole: egress is still never
  # 0.0.0.0/0, it is confined to local.vpc_endpoint_prefix_list_ids.

  validation {
    condition     = alltrue([for pl in var.vpc_endpoint_prefix_list_ids : can(regex("^pl-[0-9a-f]+$", pl))])
    error_message = "Each entry must be a prefix list id of the form pl-0123456789abcdef0."
  }
}

variable "allow_http_egress" {
  type        = bool
  description = "Allow HTTP (port 80) egress for package downloads. Not recommended for production."
  default     = false

  validation {
    condition = (
      !var.allow_http_egress ||
      !contains(["prod", "production"], lower(lookup(var.tags, "Environment", "dev")))
    )
    error_message = "HTTP egress is not allowed in production environments. Use HTTPS (port 443) only."
  }
}