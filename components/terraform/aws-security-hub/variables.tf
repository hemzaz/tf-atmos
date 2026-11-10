variable "account_verification_enabled" {
  type        = bool
  description = <<-DOC
  Enable account verification. When true (default), the component verifies that Terraform is executing
  in the correct AWS account by comparing the current account ID against the expected account from the
  account_map based on the component's tenant-stage context.
  DOC
  default     = true
}

variable "account_map_enabled" {
  type        = bool
  description = <<-DOC
  Enable the account map component. When true, the component fetches account mappings from the
  `account-map` component via remote state. When false (default), the component uses the static `account_map` variable instead.
  DOC
  default     = false
}

variable "account_map" {
  type = object({
    full_account_map              = map(string)
    audit_account_account_name    = optional(string, "")
    root_account_account_name     = optional(string, "")
    identity_account_account_name = optional(string, "")
    aws_partition                 = optional(string, "aws")
    iam_role_arn_templates        = optional(map(string), {})
  })
  description = <<-DOC
  Static account map configuration. Only used when `account_map_enabled` is `false`.
  Map keys use `tenant-stage` format (e.g., `core-security`, `core-audit`, `plat-prod`).
  DOC
  default = {
    full_account_map              = {}
    audit_account_account_name    = ""
    root_account_account_name     = ""
    identity_account_account_name = ""
    aws_partition                 = "aws"
    iam_role_arn_templates        = {}
  }
}

variable "account_map_tenant" {
  type        = string
  default     = "core"
  description = "The tenant where the `account_map` component required by remote-state is deployed"
}

variable "account_map_component_name" {
  type        = string
  description = "The name of the account-map component"
  default     = "account-map"
}

variable "admin_delegated" {
  type        = bool
  default     = false
  description = <<DOC
  A flag to indicate if the AWS Organization-wide settings should be created. This can only be done after the Security
  Hub Administrator account has already been delegated from the AWS Org Management account (usually 'root'). See the
  Deployment section of the README for more information.
  DOC
}

variable "auto_enable_organization_members" {
  type        = bool
  default     = true
  description = <<-DOC
  Flag to toggle auto-enablement of Security Hub for new member accounts in the organization.

  For more information, see:
  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/securityhub_organization_configuration#auto_enable
  DOC
}

variable "cloudwatch_event_rule_pattern_detail_type" {
  type        = string
  default     = "Security Hub Findings - Imported"
  description = <<-DOC
  The detail-type pattern used to match events that will be sent to SNS.

  For more information, see:
  https://docs.aws.amazon.com/AmazonCloudWatch/latest/events/CloudWatchEventsandEventPatterns.html
  https://docs.aws.amazon.com/eventbridge/latest/userguide/event-types.html
  DOC
}

variable "finding_severity_labels" {
  type        = list(string)
  default     = []
  description = <<-DOC
  A list of finding severity labels used to filter which Security Hub findings are forwarded to notifications, e.g.
  `["CRITICAL", "HIGH"]`. When empty (the default), findings of all severities matching
  `cloudwatch_event_rule_pattern_detail_type` are forwarded, preserving prior behavior. Requires the underlying
  `cloudposse/security-hub/aws` module `>= 0.13.0`.

  For the list of valid severity labels, see:
  https://docs.aws.amazon.com/securityhub/1.0/APIReference/API_Severity.html
  DOC

  validation {
    condition = alltrue([
      for label in var.finding_severity_labels : contains(["INFORMATIONAL", "LOW", "MEDIUM", "HIGH", "CRITICAL"], label)
    ])
    error_message = "finding_severity_labels may only contain: INFORMATIONAL, LOW, MEDIUM, HIGH, CRITICAL."
  }
}

variable "create_sns_topic" {
  type        = bool
  default     = false
  description = <<-DOC
  Flag to indicate whether an SNS topic should be created for notifications. If you want to send findings to a new SNS
  topic, set this to true and provide a valid configuration for subscribers.
  DOC
}

variable "default_standards_enabled" {
  description = "Flag to indicate whether default standards should be enabled"
  type        = bool
  default     = true
}

variable "delegated_administrator_account_name" {
  type        = string
  default     = "core-security"
  description = "The name of the account that is the AWS Organization Delegated Administrator account"
}

variable "enabled_standards" {
  description = <<DOC
  A list of standards to enable in the account.

  For example:
  - standards/aws-foundational-security-best-practices/v/1.0.0
  - ruleset/cis-aws-foundations-benchmark/v/1.2.0
  - standards/pci-dss/v/3.2.1
  - standards/cis-aws-foundations-benchmark/v/1.4.0
  DOC
  type        = set(string)
  default     = []
}

variable "finding_aggregation_region" {
  description = "If finding aggregation is enabled, the region that collects findings"
  type        = string
  default     = "us-east-1"
}

variable "finding_aggregator_enabled" {
  description = <<-DOC
  Flag to indicate whether a finding aggregator should be created

  If you want to aggregate findings from one region, set this to `true`.

  For more information, see:
  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/securityhub_finding_aggregator
  DOC

  type    = bool
  default = true
}

variable "finding_aggregator_linking_mode" {
  description = <<-DOC
  Linking mode to use for the finding aggregator.

  The possible values are:
    - `ALL_REGIONS` - Aggregate from all regions
    - `ALL_REGIONS_EXCEPT_SPECIFIED` - Aggregate from all regions except those specified in `var.finding_aggregator_regions`
    - `SPECIFIED_REGIONS` - Aggregate from regions specified in `var.finding_aggregator_regions`
  DOC
  type        = string
  default     = "ALL_REGIONS"
}

variable "finding_aggregator_regions" {
  description = <<-DOC
  A list of regions to aggregate findings from.

  This is only used if `finding_aggregator_enabled` is `true`.
  DOC
  type        = any
  default     = null
}

variable "findings_notification_arn" {
  default     = null
  type        = string
  description = <<-DOC
  The ARN for an SNS topic to send findings notifications to. This is only used if create_sns_topic is false.
  If you want to send findings to an existing SNS topic, set this to the ARN of the existing topic and set
  create_sns_topic to false.
  DOC
}

variable "global_environment" {
  type        = string
  default     = "gbl"
  description = "Global environment name"
}

variable "organizations_resource_policy_enabled" {
  type        = bool
  description = <<-DOC
  Enable creation of the Organizations resource-based delegation policy for Security Hub. When true (default),
  the component creates an `aws_organizations_resource_policy` in the management account (Step 2) that grants the
  delegated administrator permissions to manage Security Hub policies via Organizations APIs.

  Set to `false` if the Organizations resource policy is managed elsewhere (e.g., by another component or service).
  Note: `aws_organizations_resource_policy` is an organization-wide singleton — only one can exist per organization.
  If other services (e.g., AWS Backup, Inspector) need delegation policies, their statements must be combined into
  a single policy managed by one component.
  DOC
  default     = true
}

variable "organization_management_account_name" {
  type        = string
  default     = null
  description = "The name of the AWS Organization management account"
}

variable "privileged" {
  type        = bool
  default     = false
  description = "true if the default provider already has access to the backend"
}

variable "region" {
  type        = string
  description = "AWS Region"
}

variable "root_account_stage" {
  type        = string
  default     = "root"
  description = <<-DOC
  The stage name for the Organization root (management) account. This is used to lookup account IDs from account names
  using the `account-map` component.
  DOC
}

variable "subscribers" {
  type = map(object({
    protocol               = string
    endpoint               = string
    endpoint_auto_confirms = bool
    raw_message_delivery   = bool
  }))
  default     = {}
  description = <<-DOC
  A map of subscription configurations for SNS topics

  For more information, see:
  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription#argument-reference

  protocol:
    The protocol to use. The possible values for this are: sqs, sms, lambda, application. (http or https are partially
    supported, see link) (email is an option but is unsupported in terraform, see link).
  endpoint:
    The endpoint to send data to, the contents will vary with the protocol. (see link for more information)
  endpoint_auto_confirms:
    Boolean indicating whether the end point is capable of auto confirming subscription e.g., PagerDuty. Default is
    false.
  raw_message_delivery:
    Boolean indicating whether or not to enable raw message delivery (the original message is directly passed, not
    wrapped in JSON with the original message in the message property). Default is false.
  DOC
}

variable "disabled_control_finding_reasons" {
  type = map(object({
    control_id      = string
    reason_code     = optional(string)
    disabled_reason = string
    rule_order      = optional(number, 1)
  }))
  default     = {}
  description = <<-DOC
  A map of Security Hub automation rules to suppress specific control findings.
  Each entry creates an automation rule (in the delegated administrator account) that sets
  matching findings to `SUPPRESSED`.

  - control_id:      The Security Hub control ID (e.g., "Config.1"). This is the only field
                     used for matching; the rule fires on every FAILED/ACTIVE finding for the
                     given control.
  - reason_code:     Optional label appended to the rule name (e.g., "CONFIG_RECORDER_CUSTOM_ROLE").
                     Documentation/traceability only — Security Hub's automation rule API does
                     not support filtering on `Compliance.StatusReasons[].ReasonCode`, so the
                     suppression applies to all FAILED findings for `control_id`, regardless of
                     the underlying reason.
  - disabled_reason: Human-readable justification for the suppression, stored as the rule
                     description and as the note on suppressed findings.
  - rule_order:      Optional rule precedence (1–1000, lower runs first). Defaults to 1. Only
                     relevant when multiple rules could match the same finding; rules are
                     terminal, so the first match wins.

  Rules only deploy when running in the delegated administrator account with
  `admin_delegated = true` (i.e., the same gate as `aws_securityhub_organization_configuration`).
  DOC

  validation {
    condition = alltrue([
      for v in values(var.disabled_control_finding_reasons) :
      length(trimspace(v.control_id)) > 0
    ])
    error_message = "Each disabled_control_finding_reasons entry must set a non-empty control_id."
  }

  validation {
    condition = alltrue([
      for v in values(var.disabled_control_finding_reasons) :
      length(trimspace(v.disabled_reason)) > 0
    ])
    error_message = "Each disabled_control_finding_reasons entry must set a non-empty disabled_reason."
  }

  validation {
    condition = alltrue([
      for v in values(var.disabled_control_finding_reasons) :
      v.rule_order >= 1 && v.rule_order <= 1000
    ])
    error_message = "Each rule_order must be between 1 and 1000."
  }
}

variable "product_subscriptions" {
  type = object({
    guardduty        = optional(bool, true)
    inspector        = optional(bool, true)
    macie            = optional(bool, false)
    config           = optional(bool, true)
    access_analyzer  = optional(bool, true)
    firewall_manager = optional(bool, false)
  })
  description = <<-DOC
  Map of AWS service product subscriptions to enable in Security Hub.
  Product subscriptions allow Security Hub to receive findings from AWS security services.

  Default values:
  - guardduty: true (enable GuardDuty findings integration)
  - inspector: true (enable Inspector findings integration)
  - macie: false (disabled by default - enable if using Macie)
  - config: true (enable Config findings integration)
  - access_analyzer: true (enable Access Analyzer findings integration)
  - firewall_manager: false (disabled by default - enable if using Firewall Manager)

  Note: Product subscriptions can be enabled even if the source service is not yet deployed.
  The subscription will simply wait for findings once the service is enabled.

  For more information, see:
  https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-findings-providers.html
  DOC
  default     = {}
}
