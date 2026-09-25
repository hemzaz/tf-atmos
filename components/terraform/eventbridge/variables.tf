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
  description = "Short name. Rule, log group and (when created) bus and archive are named <Environment>-<name>"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{1,30}$", var.name))
    error_message = "name must be 1-30 characters of letters, digits, underscore, hyphen or period (the archive name is limited to 48 with the Environment prefix)."
  }
}

# The three inputs below are Cloud Posse's aws-eventbridge inputs, unchanged.

variable "cloudwatch_event_rule_description" {
  type        = string
  description = "Description of the event rule. If empty, defaults to <Environment>-<name>"
  default     = ""
}

variable "cloudwatch_event_rule_pattern" {
  type        = any
  description = "Event pattern of the rule, as an object (it is JSON-encoded)"
  default = {
    "source" = [
      "aws.ec2"
    ]
  }

  validation {
    condition     = can(jsonencode(var.cloudwatch_event_rule_pattern)) && length(keys(var.cloudwatch_event_rule_pattern)) > 0
    error_message = "cloudwatch_event_rule_pattern must be a non-empty object."
  }
}

variable "event_log_retention_in_days" {
  type        = number
  description = "Days to keep the matched events in the rule's CloudWatch log group"
  default     = 3

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.event_log_retention_in_days)
    error_message = "event_log_retention_in_days must be a CloudWatch Logs retention value (1, 3, 5, 7, 14, 30, 60, 90, ...)."
  }
}

# Additions for a custom bus, which the Cloud Posse component does not create
# (its rule always sits on the default bus).

variable "kms_key_arn" {
  type        = string
  description = "Customer managed KMS key ARN for the log group and, when created, the bus and archive. Its policy must allow events.amazonaws.com and logs.<region>.amazonaws.com (kms key_service_users)"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>)."
  }
}

variable "create_event_bus" {
  type        = bool
  description = "Create a custom event bus named <Environment>-<name> and put the rule on it"
  default     = false
}

variable "event_bus_name" {
  type        = string
  description = "Existing bus the rule sits on when create_event_bus is false (another instance's event_bus_name output, or default)"
  default     = "default"

  validation {
    condition     = can(regex("^[a-zA-Z0-9/_.-]{1,256}$", var.event_bus_name))
    error_message = "event_bus_name must be 1-256 characters of letters, digits, slash, underscore, hyphen or period."
  }
}

variable "archive_enabled" {
  type        = bool
  description = "Archive every event on the created bus, for replay. Requires create_event_bus"
  default     = false

  validation {
    condition     = !var.archive_enabled || var.create_event_bus
    error_message = "archive_enabled requires create_event_bus."
  }
}

variable "archive_retention_days" {
  type        = number
  description = "Days to keep archived events; 0 keeps them indefinitely"
  default     = 30

  validation {
    condition     = var.archive_retention_days >= 0
    error_message = "archive_retention_days must be 0 or more."
  }
}

variable "event_bus_dlq_arn" {
  type        = string
  description = "ARN of an SQS queue EventBridge uses as a dead-letter queue for the created bus. AWS strongly recommends one on a CMK-encrypted bus, so failed encrypt/decrypt deliveries (for example after a key-policy change or key disable) are kept, not dropped. Only used when create_event_bus is true"
  default     = null

  validation {
    condition     = var.event_bus_dlq_arn == null || can(regex("^arn:aws[a-z-]*:sqs:[a-z0-9-]+:[0-9]{12}:.+$", var.event_bus_dlq_arn)) && !endswith(coalesce(var.event_bus_dlq_arn, "-"), ".fifo")
    error_message = "event_bus_dlq_arn must be the ARN of a standard (not FIFO) SQS queue (arn:aws:sqs:<region>:<account>:<queue-name>)."
  }
}

# Targets, in the shape of Cloud Posse's cloudwatch-events target inputs
# (cloudwatch_event_target_arn / _role_arn / _id), widened to a map so one rule
# can deliver to several consumers, as terraform-aws-modules/eventbridge does.

variable "targets" {
  type = map(object({
    arn        = string
    role_arn   = optional(string)
    input_path = optional(string)
    input_transformer = optional(object({
      input_paths    = optional(map(string), {})
      input_template = string
    }))
    dead_letter_config = optional(object({
      arn = string
    }))
    retry_policy = optional(object({
      maximum_event_age_in_seconds = optional(number)
      maximum_retry_attempts       = optional(number)
    }))
    # Required by a FIFO queue target, rejected for anything else.
    sqs_message_group_id = optional(string)
    # Required by (and only for) an ECS cluster target: the task to run.
    ecs_target = optional(object({
      task_definition_arn     = string
      task_count              = optional(number, 1)
      launch_type             = optional(string)
      platform_version        = optional(string)
      group                   = optional(string)
      enable_ecs_managed_tags = optional(bool, true)
      enable_execute_command  = optional(bool, false)
      propagate_tags          = optional(string)
      network_configuration = optional(object({
        subnets          = list(string)
        security_groups  = optional(list(string), [])
        assign_public_ip = optional(bool, false)
      }))
    }))
    # Required by (and only for) a Batch job queue target: the job to submit.
    batch_target = optional(object({
      job_definition = string
      job_name       = string
      array_size     = optional(number)
      job_attempts   = optional(number)
    }))
  }))
  description = "Targets the rule delivers to, besides its log group, keyed by target ID. ECS cluster targets take ecs_target (the task to run) and Batch job queue targets batch_target (the job to submit). Lambda functions get an aws_lambda_permission scoped to this rule; SQS queues and SNS topics are reached through their own resource policy (for this repo's sqs component, its iam_policy input), which this component does not create. role_arn is required for targets EventBridge reaches with a role (Step Functions, Kinesis, Firehose, ECS, Batch, another bus, API destinations) and rejected for Lambda, SQS, SNS and CloudWatch Logs"
  default     = {}
  nullable    = false

  # One rule takes 5 targets, and the log group is always one of them.
  validation {
    condition     = length(var.targets) <= 4
    error_message = "targets takes at most 4 entries (EventBridge allows 5 targets per rule, and the log group is one)."
  }

  validation {
    condition     = alltrue([for k in keys(var.targets) : can(regex("^[a-zA-Z0-9_.-]{1,64}$", k)) && k != "cloudwatch-logs"])
    error_message = "targets keys are target IDs: 1-64 letters, digits, underscore, hyphen or period, and not cloudwatch-logs (the log group's target)."
  }

  validation {
    condition     = alltrue([for t in values(var.targets) : can(regex("^arn:aws[a-z-]*:[a-z0-9-]+:[a-z0-9-]*:[0-9]{0,12}:.+$", t.arn))])
    error_message = "Each target arn must be an ARN (arn:aws:<service>:<region>:<account>:<resource>)."
  }

  # EventBridge reaches Lambda, SQS, SNS and CloudWatch Logs through their
  # resource policies; the other services it calls need a role.
  validation {
    condition = alltrue([for t in values(var.targets) :
      contains(["lambda", "sqs", "sns", "logs"], try(split(":", t.arn)[2], ""))
      ? t.role_arn == null
      : (t.role_arn != null || !contains(["states", "kinesis", "firehose", "ecs", "batch", "events"], try(split(":", t.arn)[2], "")))
    ])
    error_message = "role_arn is rejected for Lambda, SQS, SNS and CloudWatch Logs targets (their resource policies grant EventBridge access) and required for Step Functions, Kinesis, Firehose, ECS, Batch and EventBridge (bus or API destination) targets."
  }

  validation {
    condition     = alltrue([for t in values(var.targets) : t.role_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", t.role_arn))])
    error_message = "Each target role_arn must be an IAM role ARN."
  }

  validation {
    condition     = alltrue([for t in values(var.targets) : t.input_path == null || t.input_transformer == null])
    error_message = "A target takes input_path or input_transformer, not both."
  }

  validation {
    condition     = alltrue([for t in values(var.targets) : length(try(t.input_transformer.input_paths, {})) <= 100])
    error_message = "input_transformer.input_paths takes at most 100 entries."
  }

  # EventBridge dead-letter queues must be standard queues.
  validation {
    condition     = alltrue([for t in values(var.targets) : t.dead_letter_config == null || can(regex("^arn:aws[a-z-]*:sqs:[a-z0-9-]+:[0-9]{12}:.+$", t.dead_letter_config.arn)) && !endswith(try(t.dead_letter_config.arn, ""), ".fifo")])
    error_message = "A target's dead_letter_config.arn must be the ARN of a standard (not FIFO) SQS queue."
  }

  # coalesce() stands in for an unset value with one in range.
  validation {
    condition = alltrue([for t in values(var.targets) :
      coalesce(try(t.retry_policy.maximum_event_age_in_seconds, null), 60) >= 60
      && coalesce(try(t.retry_policy.maximum_event_age_in_seconds, null), 60) <= 86400
      && coalesce(try(t.retry_policy.maximum_retry_attempts, null), 0) >= 0
      && coalesce(try(t.retry_policy.maximum_retry_attempts, null), 0) <= 185
    ])
    error_message = "retry_policy.maximum_event_age_in_seconds must be 60-86400 and maximum_retry_attempts 0-185."
  }

  validation {
    condition     = alltrue([for t in values(var.targets) : t.sqs_message_group_id == null || try(split(":", t.arn)[2], "") == "sqs"])
    error_message = "sqs_message_group_id is only for SQS (FIFO queue) targets."
  }

  validation {
    condition     = alltrue([for t in values(var.targets) : !(try(split(":", t.arn)[2], "") == "sqs" && endswith(t.arn, ".fifo")) || t.sqs_message_group_id != null])
    error_message = "A FIFO queue (.fifo) target needs sqs_message_group_id."
  }

  # EventBridge needs to know what to run on an ECS cluster or submit to a
  # Batch job queue, so those targets carry ecs_target / batch_target.
  validation {
    condition = alltrue([for t in values(var.targets) :
      (try(split(":", t.arn)[2], "") == "ecs") == (t.ecs_target != null)
      && (try(split(":", t.arn)[2], "") == "batch") == (t.batch_target != null)
    ])
    error_message = "ecs_target is required for, and only for, ECS cluster targets; batch_target likewise for Batch job queue targets."
  }

  validation {
    condition = alltrue([for t in values(var.targets) : t.ecs_target == null || (
      can(regex("^arn:aws[a-z-]*:ecs:[a-z0-9-]+:[0-9]{12}:task-definition/.+$", t.ecs_target.task_definition_arn))
      && try(t.ecs_target.task_count >= 1 && t.ecs_target.task_count <= 10, false)
      && contains(["FARGATE", "EC2", "EXTERNAL", "-"], coalesce(try(t.ecs_target.launch_type, null), "-"))
      && contains(["TASK_DEFINITION", "-"], coalesce(try(t.ecs_target.propagate_tags, null), "-"))
      && (coalesce(try(t.ecs_target.launch_type, null), "-") != "FARGATE" || try(t.ecs_target.network_configuration, null) != null)
    )])
    error_message = "ecs_target needs a task definition ARN, task_count 1-10, launch_type FARGATE, EC2 or EXTERNAL, propagate_tags TASK_DEFINITION, and network_configuration for FARGATE."
  }

  validation {
    condition = alltrue([for t in values(var.targets) : t.batch_target == null || (
      coalesce(try(t.batch_target.array_size, null), 2) >= 2 && coalesce(try(t.batch_target.array_size, null), 2) <= 10000
      && coalesce(try(t.batch_target.job_attempts, null), 1) >= 1 && coalesce(try(t.batch_target.job_attempts, null), 1) <= 10
    )])
    error_message = "batch_target.array_size must be 2-10000 and job_attempts 1-10."
  }
}
