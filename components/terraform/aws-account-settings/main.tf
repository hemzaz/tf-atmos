locals {
  enabled = module.this.enabled
}

resource "aws_iam_account_alias" "this" {
  count = local.enabled && var.account_alias_enabled ? 1 : 0

  account_alias = coalesce(var.account_alias, module.this.id)
}

resource "aws_s3_account_public_access_block" "this" {
  count = local.enabled && var.s3_block_public_access_enabled ? 1 : 0

  block_public_acls       = var.s3_block_public_acls
  block_public_policy     = var.s3_block_public_policy
  ignore_public_acls      = var.s3_ignore_public_acls
  restrict_public_buckets = var.s3_restrict_public_buckets
}

resource "aws_ebs_encryption_by_default" "this" {
  count = local.enabled && var.ebs_default_encryption_enabled ? 1 : 0

  enabled = true
}

resource "aws_ebs_default_kms_key" "this" {
  count = local.enabled && var.ebs_default_encryption_enabled && var.ebs_default_kms_key_arn != null ? 1 : 0

  key_arn = var.ebs_default_kms_key_arn
}

resource "aws_account_alternate_contact" "billing" {
  count = local.enabled && var.billing_contact != null ? 1 : 0

  alternate_contact_type = "BILLING"
  name                   = var.billing_contact.name
  title                  = var.billing_contact.title
  email_address          = var.billing_contact.email_address
  phone_number           = var.billing_contact.phone_number
}

resource "aws_account_alternate_contact" "operations" {
  count = local.enabled && var.operations_contact != null ? 1 : 0

  alternate_contact_type = "OPERATIONS"
  name                   = var.operations_contact.name
  title                  = var.operations_contact.title
  email_address          = var.operations_contact.email_address
  phone_number           = var.operations_contact.phone_number
}

resource "aws_account_alternate_contact" "security" {
  count = local.enabled && var.security_contact != null ? 1 : 0

  alternate_contact_type = "SECURITY"
  name                   = var.security_contact.name
  title                  = var.security_contact.title
  email_address          = var.security_contact.email_address
  phone_number           = var.security_contact.phone_number
}

resource "aws_ssm_document" "session_manager_prefs" {
  count = local.enabled && var.ssm_session_preferences_enabled ? 1 : 0

  name            = "SSM-SessionManagerRunShell"
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Managed by Terraform"
    sessionType   = "Standard_Stream"
    inputs = {
      idleSessionTimeout = tostring(var.ssm_session_idle_timeout_minutes)
    }
  })

  tags = module.this.tags
}

resource "aws_ebs_snapshot_block_public_access" "this" {
  count = local.enabled && var.ebs_snapshot_block_public_access_enabled ? 1 : 0

  state = var.ebs_snapshot_block_public_access_state
}

resource "aws_ec2_instance_metadata_defaults" "this" {
  count = local.enabled && var.ec2_instance_metadata_defaults_enabled ? 1 : 0

  http_endpoint               = var.ec2_instance_metadata_http_endpoint
  http_tokens                 = var.ec2_instance_metadata_http_tokens
  http_put_response_hop_limit = var.ec2_instance_metadata_http_put_response_hop_limit
  instance_metadata_tags      = var.ec2_instance_metadata_tags
}

resource "aws_ec2_image_block_public_access" "this" {
  count = local.enabled && var.ec2_image_block_public_access_enabled ? 1 : 0

  state = var.ec2_image_block_public_access_state
}

resource "aws_emr_block_public_access_configuration" "this" {
  count = local.enabled && var.emr_block_public_access_enabled ? 1 : 0

  block_public_security_group_rules = var.emr_block_public_security_group_rules

  dynamic "permitted_public_security_group_rule_range" {
    for_each = var.emr_permitted_public_security_group_rule_ranges
    content {
      min_range = permitted_public_security_group_rule_range.value.min_range
      max_range = permitted_public_security_group_rule_range.value.max_range
    }
  }
}

resource "aws_ssm_service_setting" "block_public_document_sharing" {
  count         = local.enabled && var.ssm_block_public_document_sharing ? 1 : 0
  setting_id    = "/ssm/documents/console/public-sharing-permission"
  setting_value = "Disable"
}
