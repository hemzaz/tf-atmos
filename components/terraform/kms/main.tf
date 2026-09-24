# Thin root component: a single-region customer managed KMS key by default
# (set is_multi_region and replica_regions for replicas).
module "kms" {
  source = "../_library/security/kms-multi-region"

  name_prefix                     = var.name_prefix
  description                     = var.description
  key_spec                        = var.key_spec
  key_usage                       = var.key_usage
  customer_master_key_spec        = var.customer_master_key_spec
  is_multi_region                 = var.is_multi_region
  enable_key_rotation             = var.enable_key_rotation
  rotation_period_in_days         = var.rotation_period_in_days
  deletion_window_in_days         = var.deletion_window_in_days
  key_policy                      = var.key_policy
  enable_default_policy           = var.enable_default_policy
  key_administrators              = var.key_administrators
  key_users                       = var.key_users
  key_service_users               = var.key_service_users
  allow_cloudwatch_logs           = var.allow_cloudwatch_logs
  allow_eventbridge               = var.allow_eventbridge
  allow_cloudwatch_alarms         = var.allow_cloudwatch_alarms
  allow_cloudtrail                = var.allow_cloudtrail
  alias_name                      = var.alias_name
  create_alias                    = var.create_alias
  replica_regions                 = var.replica_regions
  replica_deletion_window_in_days = var.replica_deletion_window_in_days
  grants                          = var.grants
  tags                            = var.tags
}
