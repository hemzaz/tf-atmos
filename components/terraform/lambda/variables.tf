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

# Statements in the shape of this repo's stepfunctions iam_policies. Cloud
# Posse's aws-lambda takes iam-policy module documents (iam_policy) instead;
# statements suffice here, and let one instance combine grants on resources
# read from several instances' state, which a single custom_policy document
# (one !terraform.state output) cannot.
variable "iam_policies" {
  type = list(object({
    sid       = optional(string)
    effect    = optional(string, "Allow")
    actions   = list(string)
    resources = list(string)
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })), [])
  }))
  description = "Extra statements for the execution role, in one inline policy (<Environment>-<function_name>-iam-policies) beside custom_policy, for example a DynamoDB read grant and its key's kms:Decrypt scoped by kms:ViaService. conditions is optional per statement"
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for s in var.iam_policies : contains(["Allow", "Deny"], coalesce(s.effect, "Allow"))])
    error_message = "Each iam_policies statement's effect must be Allow or Deny."
  }

  validation {
    condition     = alltrue([for s in var.iam_policies : length(s.actions) > 0 && length(s.resources) > 0])
    error_message = "Each iam_policies statement needs at least one action and one resource."
  }

  validation {
    condition     = alltrue([for s in var.iam_policies : coalesce(s.effect, "Allow") != "Allow" || alltrue([for a in s.actions : a != "*"])])
    error_message = "An Allow statement in iam_policies may not use the \"*\" action."
  }

  validation {
    condition = alltrue([
      for s in var.iam_policies : alltrue([
        for c in coalesce(s.conditions, []) : trimspace(c.test) != "" && trimspace(c.variable) != "" && length(c.values) > 0
      ])
    ])
    error_message = "Each iam_policies condition needs a non-empty test, variable and at least one value."
  }

  # Two conditions with the same test and variable would render as duplicate
  # object keys in the policy document.
  validation {
    condition = alltrue([
      for s in var.iam_policies :
      length(distinct([for c in coalesce(s.conditions, []) : "${c.test}|${c.variable}"])) == length(coalesce(s.conditions, []))
    ])
    error_message = "Each iam_policies statement may list a (test, variable) pair only once; merge the values."
  }
}

variable "api_gateway_source_arn" {
  type        = string
  description = "ARN of the API Gateway that invokes the Lambda function"
  default     = null
}

variable "s3_source_arn" {
  type        = string
  description = "ARN of the S3 bucket that invokes the Lambda function (a bucket in this account: the permission also pins source_account)"
  default     = null

  validation {
    condition     = var.s3_source_arn == null || can(regex("^arn:aws[a-z-]*:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.s3_source_arn))
    error_message = "s3_source_arn must be an S3 bucket ARN (arn:aws:s3:::<bucket>), no wildcard or object key."
  }
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
  description = "Customer managed KMS key ARN of the SQS queues / SNS topics in on_success_destination, on_failure_destination, dead_letter_target_arn and each event_source_mappings destination_config.on_failure.destination_arn; the execution role gets kms:GenerateDataKey and kms:Decrypt on it (the role always gets sqs:SendMessage / sns:Publish on those ARNs)"
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

# Poll-based triggers (aws_lambda_event_source_mapping), keyed by mapping
# name. One generic map for SQS, Kinesis and DynamoDB streams: a deliberate
# deviation from Cloud Posse's aws-lambda component, whose sqs_notifications
# covers SQS only. The source service is read from event_source_arn, and the
# execution role's read grant is derived from the same ARNs (main.tf).
variable "event_source_mappings" {
  type = map(object({
    event_source_arn                   = string
    enabled                            = optional(bool, true)
    batch_size                         = optional(number)
    maximum_batching_window_in_seconds = optional(number)
    starting_position                  = optional(string)
    starting_position_timestamp        = optional(string)
    function_response_types            = optional(list(string), [])
    filter_criteria = optional(object({
      filter = list(object({
        pattern = string
      }))
    }))
    scaling_config = optional(object({
      maximum_concurrency = number
    }))
    destination_config = optional(object({
      on_failure = object({
        destination_arn = string
      })
    }))
    maximum_retry_attempts         = optional(number)
    maximum_record_age_in_seconds  = optional(number)
    bisect_batch_on_function_error = optional(bool)
    parallelization_factor         = optional(number)
    tumbling_window_in_seconds     = optional(number)
  }))
  description = "Event source mappings (SQS queues, Kinesis streams or stream consumers, DynamoDB streams) keyed by mapping name; arguments mirror aws_lambda_event_source_mapping. starting_position is required for Kinesis/DynamoDB and forbidden for SQS; scaling_config is SQS-only; destination_config, maximum_retry_attempts, maximum_record_age_in_seconds, bisect_batch_on_function_error, parallelization_factor and tumbling_window_in_seconds are stream-only; filter_criteria takes up to 5 patterns (AWS default quota). The execution role gets read access to exactly these sources, and sqs:SendMessage / sns:Publish on each on_failure destination."
  default     = {}

  validation {
    condition = alltrue([
      for m in values(var.event_source_mappings) :
      can(regex("^arn:aws[a-z-]*:sqs:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]+(\\.fifo)?$", m.event_source_arn))
      || can(regex("^arn:aws[a-z-]*:kinesis:[a-z0-9-]+:[0-9]{12}:stream/[A-Za-z0-9_.-]+(/consumer/[A-Za-z0-9_.-]+:[0-9]+)?$", m.event_source_arn))
      || can(regex("^arn:aws[a-z-]*:dynamodb:[a-z0-9-]+:[0-9]{12}:table/[A-Za-z0-9_.-]+/stream/[0-9TZ:.-]+$", m.event_source_arn))
    ])
    error_message = "event_source_mappings: each event_source_arn must be an SQS queue ARN, a Kinesis stream (or stream consumer) ARN, or a DynamoDB stream ARN (arn:aws:dynamodb:<region>:<account>:table/<table>/stream/<label>), with no wildcards."
  }

  validation {
    condition = alltrue([
      for m in values(var.event_source_mappings) :
      try(split(":", m.event_source_arn)[2], "") == "sqs" ? m.starting_position == null : contains(["TRIM_HORIZON", "LATEST", "AT_TIMESTAMP"], coalesce(m.starting_position, "-"))
    ])
    error_message = "event_source_mappings: starting_position (TRIM_HORIZON, LATEST or AT_TIMESTAMP) is required for a Kinesis or DynamoDB stream and must not be set for an SQS queue."
  }

  validation {
    condition = alltrue([
      for m in values(var.event_source_mappings) :
      m.starting_position == "AT_TIMESTAMP" ? (try(split(":", m.event_source_arn)[2], "") == "kinesis" && m.starting_position_timestamp != null) : m.starting_position_timestamp == null
    ])
    error_message = "event_source_mappings: starting_position = AT_TIMESTAMP is Kinesis-only and needs starting_position_timestamp (RFC 3339); starting_position_timestamp is not allowed otherwise."
  }

  validation {
    condition = alltrue([
      for m in values(var.event_source_mappings) :
      try(split(":", m.event_source_arn)[2], "") != "sqs" || (
        m.destination_config == null
        && m.maximum_retry_attempts == null
        && m.maximum_record_age_in_seconds == null
        && m.bisect_batch_on_function_error == null
        && m.parallelization_factor == null
        && m.tumbling_window_in_seconds == null
      )
    ])
    error_message = "event_source_mappings: destination_config, maximum_retry_attempts, maximum_record_age_in_seconds, bisect_batch_on_function_error, parallelization_factor and tumbling_window_in_seconds are stream-only (Kinesis, DynamoDB); an SQS mapping retries and dead-letters through the queue's own redrive policy."
  }

  validation {
    condition = alltrue([
      for m in values(var.event_source_mappings) :
      m.scaling_config == null ? true : (
        try(split(":", m.event_source_arn)[2], "") == "sqs"
        && m.scaling_config.maximum_concurrency >= 2
        && m.scaling_config.maximum_concurrency <= 1000
      )
    ])
    error_message = "event_source_mappings: scaling_config.maximum_concurrency is SQS-only and must be between 2 and 1000."
  }

  validation {
    condition = alltrue([
      for m in values(var.event_source_mappings) :
      m.batch_size == null ? true : (
        endswith(m.event_source_arn, ".fifo") ? (m.batch_size >= 1 && m.batch_size <= 10) : (m.batch_size >= 1 && m.batch_size <= 10000)
      )
    ])
    error_message = "event_source_mappings: batch_size must be 1-10 for an SQS FIFO queue and 1-10000 for a standard SQS queue, a Kinesis stream or a DynamoDB stream."
  }

  validation {
    condition = alltrue([
      for m in values(var.event_source_mappings) :
      try(split(":", m.event_source_arn)[2], "") != "sqs" || coalesce(m.batch_size, 10) <= 10 || coalesce(m.maximum_batching_window_in_seconds, 0) >= 1
    ])
    error_message = "event_source_mappings: an SQS batch_size above 10 needs maximum_batching_window_in_seconds of at least 1."
  }

  validation {
    condition = alltrue([
      for m in values(var.event_source_mappings) :
      m.maximum_batching_window_in_seconds == null ? true : (
        m.maximum_batching_window_in_seconds >= 0
        && m.maximum_batching_window_in_seconds <= 300
        && !(endswith(m.event_source_arn, ".fifo") && m.maximum_batching_window_in_seconds > 0)
      )
    ])
    error_message = "event_source_mappings: maximum_batching_window_in_seconds must be 0-300, and an SQS FIFO queue takes no batching window."
  }

  validation {
    condition = alltrue([
      for m in values(var.event_source_mappings) : alltrue([
        m.maximum_retry_attempts == null ? true : (m.maximum_retry_attempts >= -1 && m.maximum_retry_attempts <= 10000),
        m.maximum_record_age_in_seconds == null ? true : (m.maximum_record_age_in_seconds == -1 || (m.maximum_record_age_in_seconds >= 60 && m.maximum_record_age_in_seconds <= 604800)),
        m.parallelization_factor == null ? true : (m.parallelization_factor >= 1 && m.parallelization_factor <= 10),
        m.tumbling_window_in_seconds == null ? true : (m.tumbling_window_in_seconds >= 0 && m.tumbling_window_in_seconds <= 900),
      ])
    ])
    error_message = "event_source_mappings: maximum_retry_attempts must be -1 to 10000, maximum_record_age_in_seconds -1 or 60-604800, parallelization_factor 1-10, tumbling_window_in_seconds 0-900."
  }

  validation {
    condition = alltrue([
      for m in values(var.event_source_mappings) :
      alltrue([for t in m.function_response_types : t == "ReportBatchItemFailures"])
    ])
    error_message = "event_source_mappings: the only function_response_types value is ReportBatchItemFailures."
  }

  validation {
    condition = alltrue([
      for m in values(var.event_source_mappings) :
      m.filter_criteria == null ? true : (length(m.filter_criteria.filter) >= 1 && length(m.filter_criteria.filter) <= 5)
    ])
    error_message = "event_source_mappings: filter_criteria.filter takes 1-5 patterns (the AWS default quota per mapping; up to 10 needs a Service Quotas increase and a change to this cap)."
  }

  validation {
    condition = alltrue([
      for m in values(var.event_source_mappings) :
      m.destination_config == null ? true : can(regex("^arn:aws[a-z-]*:(sqs|sns):[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_.-]+$", m.destination_config.on_failure.destination_arn))
    ])
    error_message = "event_source_mappings: destination_config.on_failure.destination_arn must be an SQS queue or SNS topic ARN, with no wildcards."
  }
}

# One list for the whole component rather than a per-mapping kms_key_arn:
# aws_lambda_event_source_mapping already has a kms_key_arn argument with a
# different meaning (the key that encrypts the mapping's filter criteria), so
# a per-mapping attribute of that name would be misread; and one key commonly
# encrypts several sources. Mirrors delivery_kms_key_arn above.
variable "event_source_kms_key_arns" {
  type        = list(string)
  description = "Customer managed KMS key ARNs encrypting the event_source_mappings sources (an SSE-KMS queue, a KMS-encrypted Kinesis stream); the execution role gets kms:Decrypt on exactly these keys. Leave empty for sources on AWS managed or owned keys."
  default     = []

  validation {
    condition     = alltrue([for k in var.event_source_kms_key_arns : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f-]+$", k))])
    error_message = "event_source_kms_key_arns must be KMS key ARNs (arn:aws:kms:<region>:<account>:key/<id>), not aliases or wildcards."
  }

  # The grant lives in the event_sources policy, which only exists with at
  # least one mapping; without one these keys would be silently ignored.
  validation {
    condition     = length(var.event_source_kms_key_arns) == 0 || length(var.event_source_mappings) > 0
    error_message = "event_source_kms_key_arns is only used with event_source_mappings; set a mapping or leave it empty."
  }
}