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

variable "admin_delegated" {
  type        = bool
  default     = false
  description = <<DOC
  A flag to indicate if the AWS Organization-wide settings should be created. This can only be done after the GuardDuty
  Administrator account has already been delegated from the AWS Org Management account (usually 'root'). See the
  Deployment section of the README for more information.
  DOC
}

variable "auto_enable_organization_members" {
  type        = string
  default     = "NEW"
  description = <<-DOC
  Indicates the auto-enablement configuration of GuardDuty for the member accounts in the organization. Valid values are `ALL`, `NEW`, `NONE`.

  For more information, see:
  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_organization_configuration#auto_enable_organization_members
  DOC

}

variable "cloudwatch_event_rule_pattern_detail_type" {
  type        = string
  default     = "GuardDuty Finding"
  description = <<-DOC
  The detail-type pattern used to match events that will be sent to SNS.

  For more information, see:
  https://docs.aws.amazon.com/AmazonCloudWatch/latest/events/CloudWatchEventsandEventPatterns.html
  https://docs.aws.amazon.com/eventbridge/latest/userguide/event-types.html
  https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_findings_cloudwatch.html
  DOC
}

variable "create_sns_topic" {
  type        = bool
  default     = false
  description = <<-DOC
  Flag to indicate whether an SNS topic should be created for notifications. If you want to send findings to a new SNS
  topic, set this to true and provide a valid configuration for subscribers.
  DOC
}

variable "delegated_administrator_component_name" {
  type        = string
  default     = "aws-guardduty/delegated-administrator"
  description = "The name of the component that created the GuardDuty detector."
}

variable "delegated_administrator_account_name" {
  type        = string
  default     = "core-security"
  description = "The name of the account that is the AWS Organization Delegated Administrator account"
}

variable "cloudwatch_enabled" {
  type        = bool
  default     = false
  description = <<-DOC
  Flag to indicate whether CloudWatch logging should be enabled for GuardDuty
  DOC
}

variable "finding_publishing_frequency" {
  type        = string
  default     = null
  description = <<-DOC
  The frequency of notifications sent for finding occurrences. If the detector is a GuardDuty member account, the value
  is determined by the GuardDuty master account and cannot be modified, otherwise it defaults to SIX_HOURS.

  For standalone and GuardDuty master accounts, it must be configured in Terraform to enable drift detection.
  Valid values for standalone and master accounts: FIFTEEN_MINUTES, ONE_HOUR, SIX_HOURS."

  For more information, see:
  https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_findings_cloudwatch.html#guardduty_findings_cloudwatch_notification_frequency
  DOC
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

variable "kubernetes_audit_logs_enabled" {
  type        = bool
  default     = false
  description = <<-DOC
  If `true`, enables Kubernetes audit logs as a data source for Kubernetes protection.

  For more information, see:
  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_detector#audit_logs
  DOC
}

variable "malware_protection_scan_ec2_ebs_volumes_enabled" {
  type        = bool
  default     = false
  description = <<-DOC
  Configure whether Malware Protection is enabled as data source for EC2 instances EBS Volumes in GuardDuty.

  For more information, see:
  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_detector#malware-protection
  DOC
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

variable "s3_protection_enabled" {
  type        = bool
  default     = true
  description = <<-DOC
  If `true`, enables S3 protection.

  For more information, see:
  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_detector#s3-logs
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

variable "detector_features" {
  type = map(object({
    feature_name = string
    status       = string
    additional_configuration = optional(list(object({
      addon_name = string
      status     = string
    })), [])
  }))
  default     = {}
  nullable    = false
  description = <<-DOC
  A map of detector features for streaming foundational data sources to detect communication with known malicious domains and IP addresses and identify anomalous behavior.

  For more information, see:
  https://docs.aws.amazon.com/guardduty/latest/ug/guardduty-features-activation-model.html#guardduty-features

  feature_name:
    The name of the detector feature. Possible values include: S3_DATA_EVENTS, EKS_AUDIT_LOGS, EBS_MALWARE_PROTECTION, RDS_LOGIN_EVENTS, EKS_RUNTIME_MONITORING, LAMBDA_NETWORK_LOGS, RUNTIME_MONITORING. Specifying both EKS Runtime Monitoring (EKS_RUNTIME_MONITORING) and Runtime Monitoring (RUNTIME_MONITORING) will cause an error. You can add only one of these two features because Runtime Monitoring already includes the threat detection for Amazon EKS resources. For more information, see: https://docs.aws.amazon.com/guardduty/latest/APIReference/API_DetectorFeatureConfiguration.html.
  status:
    The status of the detector feature. Valid values include: ENABLED or DISABLED.
  additional_configuration:
    Optional list of additional configurations for a feature in your GuardDuty account. For more information, see: https://docs.aws.amazon.com/guardduty/latest/APIReference/API_DetectorAdditionalConfiguration.html.
  addon_name:
    The name of the add-on for which the configuration applies. Possible values include: EKS_ADDON_MANAGEMENT, ECS_FARGATE_AGENT_MANAGEMENT, and EC2_AGENT_MANAGEMENT. For more information, see: https://docs.aws.amazon.com/guardduty/latest/APIReference/API_DetectorAdditionalConfiguration.html.
  status:
    The status of the add-on. Valid values include: ENABLED or DISABLED.
  DOC
}

variable "account_map_component_name" {
  type        = string
  description = "The name of the account-map component"
  default     = "account-map"
}

variable "lambda_network_logs_enabled" {
  type        = bool
  default     = false
  description = <<-DOC
  If `true`, enables Lambda network logs as a data source for Lambda protection.

  For more information, see:
  https://docs.aws.amazon.com/guardduty/latest/ug/lambda-protection.html
  DOC
}

variable "runtime_monitoring_enabled" {
  type        = bool
  default     = false
  description = <<-DOC
  If `true`, enables Runtime Monitoring for EC2, ECS, and EKS resources.
  Note: Runtime Monitoring already includes threat detection for Amazon EKS resources, so you should not enable both
  RUNTIME_MONITORING and EKS_RUNTIME_MONITORING features.

  For more information, see:
  https://docs.aws.amazon.com/guardduty/latest/ug/runtime-monitoring.html
  DOC
}

variable "eks_runtime_monitoring_enabled" {
  type        = bool
  default     = false
  description = <<-DOC
  If `true`, enables EKS Runtime Monitoring.
  Note: Do not enable both EKS_RUNTIME_MONITORING and RUNTIME_MONITORING as Runtime Monitoring already includes
  threat detection for Amazon EKS resources.

  For more information, see:
  https://docs.aws.amazon.com/guardduty/latest/ug/eks-runtime-monitoring.html
  DOC
}

variable "runtime_monitoring_additional_config" {
  type = object({
    eks_addon_management_enabled         = optional(bool, false)
    ecs_fargate_agent_management_enabled = optional(bool, false)
    ec2_agent_management_enabled         = optional(bool, false)
  })
  default     = {}
  nullable    = false
  description = <<-DOC
  Additional configuration for Runtime Monitoring features.

  eks_addon_management_enabled: Enable EKS add-on management
  ecs_fargate_agent_management_enabled: Enable ECS Fargate agent management
  ec2_agent_management_enabled: Enable EC2 agent management

  For more information, see:
  https://docs.aws.amazon.com/guardduty/latest/ug/runtime-monitoring.html
  DOC
}
