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
    condition     = var.event_bus_dlq_arn == null || can(regex("^arn:aws[a-z-]*:sqs:[a-z0-9-]+:[0-9]{12}:.+$", var.event_bus_dlq_arn))
    error_message = "event_bus_dlq_arn must be an SQS queue ARN (arn:aws:sqs:<region>:<account>:<queue-name>)."
  }
}
