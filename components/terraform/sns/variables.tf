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
  description = "Short name. The topic is named <Environment>-<name> (plus .fifo for a FIFO topic)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,200}$", var.name))
    error_message = "name must be 1-200 characters of letters, digits, underscore or hyphen."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "Customer managed KMS key ARN that encrypts the topic. Services publishing to the topic (EventBridge, ...) need access in its key policy (kms allow_eventbridge)"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>)."
  }
}

# The inputs below are Cloud Posse's aws-sns-topic inputs, with its defaults.

variable "subscribers" {
  type = map(object({
    protocol               = string
    endpoint               = string
    endpoint_auto_confirms = optional(bool, false)
    raw_message_delivery   = optional(bool, false)
    filter_policy          = optional(string)
    filter_policy_scope    = optional(string)
    # Required by the firehose protocol only.
    subscription_role_arn = optional(string)
    # ARN of an SQS queue that keeps messages SNS fails to deliver
    # (the subscription's redrive policy).
    dead_letter_queue_arn = optional(string)
  }))
  description = "Subscriptions to the topic, keyed by a short name. Protocols: sqs, lambda, https, email, email-json, sms, application, firehose (not http: deliveries are encrypted in transit)"
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for s in values(var.subscribers) : contains(["sqs", "lambda", "https", "email", "email-json", "sms", "application", "firehose"], s.protocol)])
    error_message = "Each subscriber protocol must be one of sqs, lambda, https, email, email-json, sms, application or firehose (http is not allowed: use https)."
  }

  validation {
    condition     = alltrue([for s in values(var.subscribers) : s.protocol != "firehose" || s.subscription_role_arn != null])
    error_message = "A firehose subscriber needs subscription_role_arn."
  }

  validation {
    condition     = alltrue([for s in values(var.subscribers) : s.dead_letter_queue_arn == null || can(regex("^arn:aws[a-z-]*:sqs:[a-z0-9-]+:[0-9]{12}:.+$", s.dead_letter_queue_arn))])
    error_message = "dead_letter_queue_arn must be an SQS queue ARN."
  }
}

variable "allowed_aws_services_for_sns_published" {
  type        = list(string)
  description = "AWS service principals (e.g. events.amazonaws.com, cloudwatch.amazonaws.com) allowed to publish to the topic, limited to this account by aws:SourceAccount"
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for s in var.allowed_aws_services_for_sns_published : can(regex("^[a-z0-9.-]+\\.amazonaws\\.com$", s))])
    error_message = "allowed_aws_services_for_sns_published entries must be service principals (<service>.amazonaws.com)."
  }
}

variable "allowed_iam_arns_for_sns_publish" {
  type        = list(string)
  description = "IAM role or user ARNs allowed to publish to the topic (for other accounts; this account's principals only need an IAM policy)"
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for a in var.allowed_iam_arns_for_sns_publish : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(role|user)/.+$", a))])
    error_message = "allowed_iam_arns_for_sns_publish entries must be IAM role or user ARNs."
  }
}

variable "sns_topic_policy_json" {
  type        = string
  description = "A fully formed topic policy (JSON) that replaces the generated one. Empty uses the generated policy"
  default     = ""
  nullable    = false

  validation {
    condition     = var.sns_topic_policy_json == "" || can(jsondecode(var.sns_topic_policy_json))
    error_message = "sns_topic_policy_json must be empty or a JSON document."
  }
}

variable "delivery_policy" {
  type        = string
  description = "The SNS delivery policy as JSON (HTTP/S retry settings)"
  default     = null

  validation {
    condition     = var.delivery_policy == null || can(jsondecode(var.delivery_policy))
    error_message = "delivery_policy must be null or a JSON document."
  }
}

variable "fifo_topic" {
  type        = bool
  description = "Create a FIFO (first-in-first-out) topic"
  default     = false
}

variable "content_based_deduplication" {
  type        = bool
  description = "Enable content-based deduplication. FIFO topics only"
  default     = false

  validation {
    condition     = !var.content_based_deduplication || var.fifo_topic
    error_message = "content_based_deduplication requires fifo_topic."
  }
}
