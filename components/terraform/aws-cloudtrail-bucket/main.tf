module "cloudtrail_s3_bucket" {
  source  = "cloudposse/cloudtrail-s3-bucket/aws"
  version = "0.33.0"

  acl                                = var.acl
  expiration_days                    = var.expiration_days
  force_destroy                      = var.force_destroy
  glacier_transition_days            = var.glacier_transition_days
  lifecycle_rule_enabled             = var.lifecycle_rule_enabled
  noncurrent_version_expiration_days = var.noncurrent_version_expiration_days
  noncurrent_version_transition_days = var.noncurrent_version_transition_days
  object_lock_enabled                = var.object_lock_enabled
  object_lock_configuration          = var.object_lock_configuration
  policy                             = var.policy
  sse_algorithm                      = var.sse_algorithm
  standard_transition_days           = var.standard_transition_days
  versioning_enabled                 = var.versioning_enabled
  create_access_log_bucket           = var.create_access_log_bucket
  access_log_bucket_name             = var.create_access_log_bucket ? null : var.access_log_bucket_name

  context = module.this.context
}
