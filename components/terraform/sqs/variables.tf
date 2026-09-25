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
  description = "Short name. The queue is named <Environment>-<name> (plus .fifo for a FIFO queue); the DLQ adds -<dlq_name_suffix>"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,60}$", var.name))
    error_message = "name must be 1-60 characters of letters, digits, underscore or hyphen."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "Customer managed KMS key ARN that encrypts the queue and the DLQ. AWS services that send to the queue (SNS, EventBridge) need access in its key policy (kms allow_sns / allow_eventbridge)"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>)."
  }
}

# The inputs below are Cloud Posse's aws-sqs-queue inputs, with its defaults.

variable "visibility_timeout_seconds" {
  type        = number
  description = "The visibility timeout for the queue, 0 to 43200 seconds"
  default     = 30

  validation {
    condition     = var.visibility_timeout_seconds >= 0 && var.visibility_timeout_seconds <= 43200
    error_message = "visibility_timeout_seconds must be between 0 and 43200."
  }
}

variable "message_retention_seconds" {
  type        = number
  description = "Seconds SQS keeps a message, 60 (1 minute) to 1209600 (14 days)"
  default     = 345600

  validation {
    condition     = var.message_retention_seconds >= 60 && var.message_retention_seconds <= 1209600
    error_message = "message_retention_seconds must be between 60 and 1209600."
  }
}

variable "max_message_size" {
  type        = number
  description = "Largest message SQS accepts, 1024 bytes to 1048576 bytes (1 MiB)"
  default     = 262144

  validation {
    condition     = var.max_message_size >= 1024 && var.max_message_size <= 1048576
    error_message = "max_message_size must be between 1024 and 1048576."
  }
}

variable "delay_seconds" {
  type        = number
  description = "Seconds the delivery of every message is delayed, 0 to 900"
  default     = 0

  validation {
    condition     = var.delay_seconds >= 0 && var.delay_seconds <= 900
    error_message = "delay_seconds must be between 0 and 900."
  }
}

variable "receive_wait_time_seconds" {
  type        = number
  description = "Long-polling wait of ReceiveMessage, 0 to 20 seconds (0 returns immediately)"
  default     = 0

  validation {
    condition     = var.receive_wait_time_seconds >= 0 && var.receive_wait_time_seconds <= 20
    error_message = "receive_wait_time_seconds must be between 0 and 20."
  }
}

variable "kms_data_key_reuse_period_seconds" {
  type        = number
  description = "Seconds SQS reuses a data key before calling KMS again, 60 to 86400"
  default     = 300

  validation {
    condition     = var.kms_data_key_reuse_period_seconds >= 60 && var.kms_data_key_reuse_period_seconds <= 86400
    error_message = "kms_data_key_reuse_period_seconds must be between 60 and 86400."
  }
}

variable "fifo_queue" {
  type        = bool
  description = "Create a FIFO queue (and a FIFO DLQ)"
  default     = false
}

variable "content_based_deduplication" {
  type        = bool
  description = "Enable content-based deduplication. FIFO queues only"
  default     = false

  validation {
    condition     = !var.content_based_deduplication || var.fifo_queue
    error_message = "content_based_deduplication requires fifo_queue."
  }
}

variable "deduplication_scope" {
  type        = string
  description = "Whether deduplication happens per messageGroup or per queue. FIFO queues only"
  default     = null

  validation {
    condition     = var.deduplication_scope == null || (var.fifo_queue && contains(["messageGroup", "queue"], coalesce(var.deduplication_scope, "-")))
    error_message = "deduplication_scope must be messageGroup or queue, and requires fifo_queue."
  }
}

variable "fifo_throughput_limit" {
  type        = string
  description = "Whether the FIFO throughput quota applies perQueue or perMessageGroupId. FIFO queues only"
  default     = null

  validation {
    condition     = var.fifo_throughput_limit == null || (var.fifo_queue && contains(["perQueue", "perMessageGroupId"], coalesce(var.fifo_throughput_limit, "-")))
    error_message = "fifo_throughput_limit must be perQueue or perMessageGroupId, and requires fifo_queue."
  }
}

variable "dlq_enabled" {
  type        = bool
  description = "Create a dead-letter queue and redrive failed messages to it after dlq_max_receive_count receives"
  default     = false
}

variable "dlq_name_suffix" {
  type        = string
  description = "Suffix of the dead-letter queue name"
  default     = "dlq"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,10}$", var.dlq_name_suffix))
    error_message = "dlq_name_suffix must be 1-10 characters of letters, digits, underscore or hyphen."
  }
}

variable "dlq_max_receive_count" {
  type        = number
  description = "Receives of a message before it is moved to the dead-letter queue, 1 to 1000"
  default     = 5

  validation {
    condition     = var.dlq_max_receive_count >= 1 && var.dlq_max_receive_count <= 1000
    error_message = "dlq_max_receive_count must be between 1 and 1000."
  }
}

variable "dlq_message_retention_seconds" {
  type        = number
  description = "Seconds the dead-letter queue keeps a message, 60 to 1209600. Default 14 days, so failed messages outlive the source queue's retention"
  default     = 1209600

  validation {
    condition     = var.dlq_message_retention_seconds >= 60 && var.dlq_message_retention_seconds <= 1209600
    error_message = "dlq_message_retention_seconds must be between 60 and 1209600."
  }
}

variable "iam_policy_limit_to_current_account" {
  type        = bool
  description = "Add an aws:SourceAccount = <this account> condition to every Allow statement in iam_policy (Cloud Posse's default; Deny statements are left unnarrowed). Fits service principals (events, sns, s3); set false for statements whose principals are IAM roles"
  default     = true
}

variable "iam_policy" {
  type = list(object({
    policy_id = optional(string, null)
    version   = optional(string, null)
    statements = list(object({
      sid           = optional(string, null)
      effect        = optional(string, null)
      actions       = optional(list(string), null)
      not_actions   = optional(list(string), null)
      resources     = optional(list(string), null)
      not_resources = optional(list(string), null)
      conditions = optional(list(object({
        test     = string
        variable = string
        values   = list(string)
      })), [])
      principals = optional(list(object({
        type        = string
        identifiers = list(string)
      })), [])
      not_principals = optional(list(object({
        type        = string
        identifiers = list(string)
      })), [])
    }))
  }))
  description = "Queue policy, as Cloud Posse's aws-sqs-queue iam_policy (aws_iam_policy_document statements). Every statement is scoped to the queue ARN (resources/not_resources must be unset); Allow statements may not use a \"*\" principal (or one with a wildcard inside it), not_principals or not_actions, and an Allow for a Service principal must pin the caller (iam_policy_limit_to_current_account, or an aws:SourceAccount/SourceArn/SourceOwner/SourceOrgID/PrincipalOrgID/PrincipalAccount/PrincipalArn condition). Example: let events.amazonaws.com sqs:SendMessage with an ArnEquals aws:SourceArn condition on a rule ARN"
  default     = []
  nullable    = false

  validation {
    condition     = length(var.iam_policy) <= 1
    error_message = "iam_policy takes at most one policy document; put every statement in it."
  }

  # A Deny may use actions or not_actions; an Allow needs explicit,
  # non-wildcard actions.
  validation {
    condition = alltrue(flatten([for p in var.iam_policy : [
      for s in p.statements : coalesce(s.effect, "Allow") == "Allow"
      ? length(coalesce(s.actions, [])) > 0 && alltrue([for a in coalesce(s.actions, []) : a != "*" && lower(a) != "sqs:*"])
      : length(coalesce(s.actions, [])) > 0 || length(coalesce(s.not_actions, [])) > 0
    ]]))
    error_message = "Allow statements in iam_policy need actions, and may not use \"*\" or \"sqs:*\"; Deny statements need actions or not_actions."
  }

  # No public queue: an Allow must name its principals, none of them "*" or
  # with a wildcard inside it (arn:aws:iam::*:root).
  validation {
    condition = alltrue(flatten([for p in var.iam_policy : [
      for s in p.statements : coalesce(s.effect, "Allow") != "Allow" || (
        s.not_actions == null
        && length(s.not_principals) == 0
        && length(s.principals) > 0
        && alltrue([for pr in s.principals : alltrue([for i in pr.identifiers : !strcontains(i, "*")])])
      )
    ]]))
    error_message = "Allow statements in iam_policy must name principals, and must not use a \"*\" principal (or one with a wildcard inside it), not_principals or not_actions (no public queue policy)."
  }

  # A service principal acts for whichever account or resource calls it (the
  # confused deputy), so an Allow for one must pin the caller, as sns does for
  # principal "*": iam_policy_limit_to_current_account (aws:SourceAccount), or
  # a condition on aws:SourceAccount, aws:SourceArn, aws:SourceOwner,
  # aws:SourceOrgID, aws:PrincipalOrgID, aws:PrincipalAccount or
  # aws:PrincipalArn (any case), under an operator that is not negated,
  # ...IfExists, Null or ForAllValues:... (each lets a caller without the key
  # through), with no value made only of wildcards. The account limit only
  # counts for a statement it is added to: one without its own
  # aws:SourceAccount condition (see main.tf).
  validation {
    condition = alltrue(flatten([for p in var.iam_policy : [
      for s in p.statements : coalesce(s.effect, "Allow") != "Allow"
      || !anytrue([for pr in s.principals : lower(pr.type) == "service"])
      || (var.iam_policy_limit_to_current_account && !contains([for c in s.conditions : lower(c.variable)], "aws:sourceaccount"))
      || anytrue([for c in s.conditions :
        contains(["aws:sourceaccount", "aws:sourcearn", "aws:sourceowner", "aws:sourceorgid", "aws:principalorgid", "aws:principalaccount", "aws:principalarn"], lower(c.variable))
        && !strcontains(lower(c.test), "not") && !endswith(lower(c.test), "ifexists") && lower(c.test) != "null"
        && !startswith(lower(c.test), "forallvalues:")
        && length(c.values) > 0 && !anytrue([for x in c.values : replace(replace(x, "*", ""), "?", "") == ""])
      ])
    ]]))
    error_message = "An iam_policy Allow for a Service principal must pin the caller: through iam_policy_limit_to_current_account, or with a condition on aws:SourceAccount, aws:SourceArn, aws:SourceOwner, aws:SourceOrgID, aws:PrincipalOrgID, aws:PrincipalAccount or aws:PrincipalArn, under a positive operator (not ...Not..., ...IfExists, Null or ForAllValues:...) and with a value that is not only wildcards."
  }

  validation {
    condition     = alltrue(flatten([for p in var.iam_policy : [for s in p.statements : s.resources == null && s.not_resources == null]]))
    error_message = "Leave resources and not_resources unset in iam_policy statements: every statement is scoped to this queue's ARN."
  }
}
