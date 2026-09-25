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
  description = "Short name. The state machine, its execution role and log group are named <Environment>-<name>"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,60}$", var.name))
    error_message = "name must be 1-60 characters of letters, digits, underscore or hyphen (the state machine name, <Environment>-<name>, is capped at 80 by AWS)."
  }
}

variable "type" {
  type        = string
  description = "State machine type: STANDARD or EXPRESS"
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "EXPRESS"], var.type)
    error_message = "type must be STANDARD or EXPRESS."
  }
}

variable "definition" {
  type        = any
  description = "Amazon States Language definition, as an object; the component jsonencodes it. ARNs referenced in it (Lambda functions, SNS topics, ...) should come from !terraform.state so they never go stale"

  validation {
    condition     = can(keys(var.definition)) && length(keys(var.definition)) > 0
    error_message = "definition must be a non-empty object."
  }
}

variable "logging_configuration" {
  type = object({
    level                  = optional(string, "ALL")
    include_execution_data = optional(bool, true)
  })
  description = "CloudWatch Logs level (ALL, ERROR, FATAL or OFF) and whether execution data (Task input/output payloads) is included. The log group is always created; defaults to full execution history logging (level ALL, include_execution_data true). OFF stops the state machine writing to it; set include_execution_data to false for workflows whose Task input/output may carry sensitive data"
  # Spelled out rather than relying on the optional() defaults above: static
  # scanners (Checkov) evaluate a variable's top-level default literally and
  # do not walk the type constraint's optional() defaults, so an empty {}
  # here reads as include_execution_data = null (fails CKV_AWS_285) even
  # though Terraform itself would apply the optional() default correctly.
  default = {
    level                  = "ALL"
    include_execution_data = true
  }
  nullable = false

  validation {
    condition     = contains(["ALL", "ERROR", "FATAL", "OFF"], coalesce(var.logging_configuration.level, "OFF"))
    error_message = "logging_configuration.level must be ALL, ERROR, FATAL or OFF."
  }
}

variable "tracing_enabled" {
  type        = bool
  description = "Enable AWS X-Ray tracing for the state machine (the execution role is granted the X-Ray write permissions this requires). Defaults to true"
  default     = true
}

variable "log_retention_days" {
  type        = number
  description = "Number of days to retain the state machine's CloudWatch log group"
  default     = 90

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a CloudWatch Logs retention value (1, 3, 5, 7, 14, 30, 60, 90, ...)."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "Customer managed KMS key ARN that encrypts the state machine definition/execution history and its CloudWatch log group. Its policy must allow logs.<region>.amazonaws.com (kms allow_cloudwatch_logs)"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>)."
  }
}

# CP-style statements (Cloud Posse's aws-step-functions takes an existing
# execution role instead of creating one, so it has no equivalent input; this
# is the identity-policy counterpart of, for example, this repo's sqs
# component's resource-policy iam_policy). No principals: the role is fixed
# (the one this component creates), only what it may do is configurable.
variable "iam_policies" {
  type = list(object({
    sid       = optional(string)
    effect    = optional(string, "Allow")
    actions   = list(string)
    resources = list(string)
  }))
  description = "Extra statements merged into one inline policy on the execution role, for whatever the definition's Tasks call directly (for example lambda:InvokeFunction on a function it invokes, sns:Publish on a topic it publishes to). A Task calling another service through a resource policy instead (an SQS queue, another state machine invoked by EventBridge, ...) does not need a statement here"
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
}

variable "events_role_enabled" {
  type        = bool
  description = "Create an IAM role trusted by events.amazonaws.com and allowed states:StartExecution on this state machine only (output as events_role_arn), for use as an eventbridge instance's target role_arn"
  default     = false
}
