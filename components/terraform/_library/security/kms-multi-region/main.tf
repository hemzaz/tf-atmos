##############################################
# KMS Key (Primary)
##############################################

resource "aws_kms_key" "main" {
  description              = var.description
  key_usage                = var.key_usage
  customer_master_key_spec = var.customer_master_key_spec != null ? var.customer_master_key_spec : var.key_spec
  deletion_window_in_days  = var.deletion_window_in_days
  is_enabled               = true
  enable_key_rotation      = var.enable_key_rotation && var.key_spec == "SYMMETRIC_DEFAULT"
  multi_region             = var.is_multi_region

  # Use custom policy if provided, otherwise use default
  policy = local.use_custom_policy ? var.key_policy : local.default_policy

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-key"
    }
  )
}

##############################################
# KMS Key Alias
##############################################

resource "aws_kms_alias" "main" {
  count = var.create_alias ? 1 : 0

  name          = local.key_alias_name
  target_key_id = aws_kms_key.main.id
}

##############################################
# KMS Replica Keys (Multi-Region)
##############################################

resource "aws_kms_replica_key" "replicas" {
  for_each = var.is_multi_region ? toset(var.replica_regions) : []

  description             = "${var.description} (Replica in ${each.value})"
  primary_key_arn         = aws_kms_key.main.arn
  deletion_window_in_days = var.replica_deletion_window_in_days
  enabled                 = true

  # Replicas inherit policy from primary key
  policy = local.use_custom_policy ? var.key_policy : local.default_policy

  tags = merge(
    local.common_tags,
    {
      Name    = "${var.name_prefix}-key-replica"
      Region  = each.value
      Primary = "false"
    }
  )

  # Use alternate provider for each region
  provider = aws
}

##############################################
# KMS Grants
##############################################

resource "aws_kms_grant" "grants" {
  for_each = { for idx, grant in var.grants : grant.name => grant }

  name              = each.value.name
  key_id            = aws_kms_key.main.id
  grantee_principal = each.value.grantee_principal
  operations        = each.value.operations

  dynamic "constraints" {
    for_each = each.value.constraints != null ? [each.value.constraints] : []
    content {
      encryption_context_equals = constraints.value.encryption_context_equals
      encryption_context_subset = constraints.value.encryption_context_subset
    }
  }
}
