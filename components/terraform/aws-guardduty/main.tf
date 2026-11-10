locals {
  enabled     = module.this.enabled
  account_map = module.account_map.outputs.full_account_map

  current_account_id                     = one(data.aws_caller_identity.this[*].account_id)
  member_account_id_list                 = [for a in keys(local.account_map) : (local.account_map[a]) if local.account_map[a] != local.current_account_id && local.account_map[a] != local.org_management_account_id]
  org_delegated_administrator_account_id = local.account_map[var.delegated_administrator_account_name]
  org_management_account_id              = var.organization_management_account_name == null ? local.account_map[module.account_map.outputs.root_account_account_name] : local.account_map[var.organization_management_account_name]
  is_org_delegated_administrator_account = local.current_account_id == local.org_delegated_administrator_account_id
  is_org_management_account              = local.current_account_id == local.org_management_account_id

  create_sns_topic = local.enabled && var.create_sns_topic
  # Only create the detector in the delegated administrator account during Step 1
  # The management account (root) should ONLY delegate, not create a detector
  create_guardduty_collector = local.enabled && local.is_org_delegated_administrator_account && !var.admin_delegated
  create_org_delegation      = local.enabled && local.is_org_management_account
  create_org_configuration   = local.enabled && local.is_org_delegated_administrator_account && var.admin_delegated

  # SNS/SQS/CloudWatch configuration
  sqs_enabled               = local.create_sns_topic
  enable_cloudwatch         = local.create_sns_topic && var.cloudwatch_enabled
  enable_notifications      = local.enable_cloudwatch
  findings_notification_arn = local.create_sns_topic ? module.sns_topic[0].sns_topic.arn : var.findings_notification_arn
  sqs_subscribe = local.sqs_enabled ? {
    sqs = {
      protocol               = "sqs"
      endpoint               = module.sqs[0].queue_arn
      endpoint_auto_confirms = true
      raw_message_delivery   = false
    }
  } : {}
}

data "aws_caller_identity" "this" {
  count = local.enabled ? 1 : 0
}

# Get organization data to establish dependencies and verify trusted access
data "aws_organizations_organization" "this" {
  count = local.enabled ? 1 : 0
}

# If we are are in the AWS Org management account, delegate GuardDuty to the org administrator account
# (usually the security account)
resource "aws_guardduty_organization_admin_account" "this" {
  count = local.create_org_delegation ? 1 : 0

  admin_account_id = local.org_delegated_administrator_account_id

  # Ensure the organization has guardduty.amazonaws.com in its enabled service access principals
  # This should be configured by the account component, but we verify it here
  lifecycle {
    precondition {
      condition     = contains(data.aws_organizations_organization.this[0].aws_service_access_principals, "guardduty.amazonaws.com")
      error_message = "GuardDuty trusted access (guardduty.amazonaws.com) must be enabled in AWS Organizations before delegating administration."
    }
  }
}

# If we are are in the AWS Org designated administrator account, enable the GuardDuty detector and optionally create an
# SNS topic for notifications and CloudWatch event rules for findings.
#
# NOTE: We set create_sns_topic=false in the module and create our own SNS topic instead.
# This is because of https://github.com/cloudposse/terraform-aws-guardduty/issues/10
# The module's SNS topic encryption doesn't grant EventBridge permission to decrypt messages.
module "guardduty" {
  count   = local.create_guardduty_collector ? 1 : 0
  source  = "cloudposse/guardduty/aws"
  version = "1.0.0"

  finding_publishing_frequency                    = var.finding_publishing_frequency
  create_sns_topic                                = false # We create our own SNS topic due to issue #10
  findings_notification_arn                       = var.findings_notification_arn
  subscribers                                     = var.subscribers
  enable_cloudwatch                               = var.cloudwatch_enabled
  cloudwatch_event_rule_pattern_detail_type       = var.cloudwatch_event_rule_pattern_detail_type
  s3_protection_enabled                           = var.s3_protection_enabled
  kubernetes_audit_logs_enabled                   = var.kubernetes_audit_logs_enabled
  malware_protection_scan_ec2_ebs_volumes_enabled = var.malware_protection_scan_ec2_ebs_volumes_enabled
  lambda_network_logs_enabled                     = var.lambda_network_logs_enabled
  runtime_monitoring_enabled                      = var.runtime_monitoring_enabled
  eks_runtime_monitoring_enabled                  = var.eks_runtime_monitoring_enabled
  runtime_monitoring_additional_config            = var.runtime_monitoring_additional_config

  context = module.this.context
}

# If we are in the AWS Org designated administrator account, set the AWS Org-wide GuardDuty configuration by
# configuring all other accounts to send their GuardDuty findings to the detector in this account.
#
# This also configures the various Data Sources.
resource "awsutils_guardduty_organization_settings" "this" {
  count = local.create_org_configuration ? 1 : 0

  member_accounts = local.member_account_id_list
  detector_id     = module.guardduty_delegated_detector[0].outputs.guardduty_detector_id
}

resource "aws_guardduty_organization_configuration" "this" {
  count = local.create_org_configuration ? 1 : 0

  auto_enable_organization_members = var.auto_enable_organization_members
  detector_id                      = module.guardduty_delegated_detector[0].outputs.guardduty_detector_id

  # Note: The datasources block is deprecated in favor of aws_guardduty_organization_configuration_feature resources
  # See: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_organization_configuration_feature

  # Ensure the organization has GuardDuty trusted access enabled
  # This is required for the delegated administrator to configure organization-wide settings
  depends_on = [
    awsutils_guardduty_organization_settings.this
  ]

  lifecycle {
    precondition {
      condition     = contains(data.aws_organizations_organization.this[0].aws_service_access_principals, "guardduty.amazonaws.com")
      error_message = <<-EOT
        GuardDuty trusted access must be enabled in AWS Organizations before configuring organization settings.
      EOT
    }
  }
}

# Configure organization-wide GuardDuty features
# This replaces the deprecated datasources block in aws_guardduty_organization_configuration
# See: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_organization_configuration_feature

resource "aws_guardduty_organization_configuration_feature" "s3_data_events" {
  count = local.create_org_configuration && var.s3_protection_enabled ? 1 : 0

  detector_id = module.guardduty_delegated_detector[0].outputs.guardduty_detector_id
  name        = "S3_DATA_EVENTS"
  auto_enable = var.auto_enable_organization_members

  depends_on = [
    aws_guardduty_organization_configuration.this
  ]
}

resource "aws_guardduty_organization_configuration_feature" "eks_audit_logs" {
  count = local.create_org_configuration && var.kubernetes_audit_logs_enabled ? 1 : 0

  detector_id = module.guardduty_delegated_detector[0].outputs.guardduty_detector_id
  name        = "EKS_AUDIT_LOGS"
  auto_enable = var.auto_enable_organization_members

  depends_on = [
    aws_guardduty_organization_configuration.this
  ]
}

resource "aws_guardduty_organization_configuration_feature" "ebs_malware_protection" {
  count = local.create_org_configuration && var.malware_protection_scan_ec2_ebs_volumes_enabled ? 1 : 0

  detector_id = module.guardduty_delegated_detector[0].outputs.guardduty_detector_id
  name        = "EBS_MALWARE_PROTECTION"
  auto_enable = var.auto_enable_organization_members

  depends_on = [
    aws_guardduty_organization_configuration.this
  ]
}

resource "aws_guardduty_organization_configuration_feature" "lambda_network_logs" {
  count = local.create_org_configuration && var.lambda_network_logs_enabled ? 1 : 0

  detector_id = module.guardduty_delegated_detector[0].outputs.guardduty_detector_id
  name        = "LAMBDA_NETWORK_LOGS"
  auto_enable = var.auto_enable_organization_members

  depends_on = [
    aws_guardduty_organization_configuration.this
  ]
}

resource "aws_guardduty_organization_configuration_feature" "runtime_monitoring" {
  count = local.create_org_configuration && var.runtime_monitoring_enabled ? 1 : 0

  detector_id = module.guardduty_delegated_detector[0].outputs.guardduty_detector_id
  name        = "RUNTIME_MONITORING"
  auto_enable = var.auto_enable_organization_members

  # Use dynamic blocks with explicit list ordering to avoid order-based drift
  # AWS returns these in this specific order: ECS, EC2, EKS (based on observed API behavior)
  dynamic "additional_configuration" {
    for_each = [
      {
        name        = "ECS_FARGATE_AGENT_MANAGEMENT"
        auto_enable = var.runtime_monitoring_additional_config.ecs_fargate_agent_management_enabled ? var.auto_enable_organization_members : "NONE"
      },
      {
        name        = "EC2_AGENT_MANAGEMENT"
        auto_enable = var.runtime_monitoring_additional_config.ec2_agent_management_enabled ? var.auto_enable_organization_members : "NONE"
      },
      {
        name        = "EKS_ADDON_MANAGEMENT"
        auto_enable = var.runtime_monitoring_additional_config.eks_addon_management_enabled ? var.auto_enable_organization_members : "NONE"
      },
    ]

    content {
      name        = additional_configuration.value.name
      auto_enable = additional_configuration.value.auto_enable
    }
  }

  depends_on = [
    aws_guardduty_organization_configuration.this
  ]

  lifecycle {
    precondition {
      condition     = !(var.runtime_monitoring_enabled && var.eks_runtime_monitoring_enabled)
      error_message = "Cannot enable both RUNTIME_MONITORING and EKS_RUNTIME_MONITORING. Runtime Monitoring already includes threat detection for Amazon EKS resources."
    }
  }
}

resource "aws_guardduty_organization_configuration_feature" "eks_runtime_monitoring" {
  count = local.create_org_configuration && var.eks_runtime_monitoring_enabled ? 1 : 0

  detector_id = module.guardduty_delegated_detector[0].outputs.guardduty_detector_id
  name        = "EKS_RUNTIME_MONITORING"
  auto_enable = var.auto_enable_organization_members

  # EKS Runtime Monitoring only supports EKS_ADDON_MANAGEMENT
  additional_configuration {
    name        = "EKS_ADDON_MANAGEMENT"
    auto_enable = var.runtime_monitoring_additional_config.eks_addon_management_enabled ? var.auto_enable_organization_members : "NONE"
  }

  depends_on = [
    aws_guardduty_organization_configuration.this
  ]

  lifecycle {
    precondition {
      condition     = !(var.runtime_monitoring_enabled && var.eks_runtime_monitoring_enabled)
      error_message = "Cannot enable both RUNTIME_MONITORING and EKS_RUNTIME_MONITORING. Runtime Monitoring already includes threat detection for Amazon EKS resources."
    }
  }
}

# Additional organization-wide detector features configured via flexible map
# Note: This uses aws_guardduty_organization_configuration_feature for organization-wide settings (Step 3)
# Do not confuse with aws_guardduty_detector_feature which is for individual detector configuration (Step 1 - in nested module)
resource "aws_guardduty_organization_configuration_feature" "additional" {
  for_each = { for k, v in var.detector_features : k => v if local.create_org_configuration }

  detector_id = module.guardduty_delegated_detector[0].outputs.guardduty_detector_id
  name        = each.value.feature_name
  auto_enable = var.auto_enable_organization_members

  dynamic "additional_configuration" {
    for_each = each.value.additional_configuration
    content {
      name        = additional_configuration.value.addon_name
      auto_enable = var.auto_enable_organization_members
    }
  }

  depends_on = [
    aws_guardduty_organization_configuration.this
  ]
}
