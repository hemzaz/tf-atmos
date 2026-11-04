# House copy of Cloud Posse's aws-config-bucket component
# (github.com/cloudposse-terraform-components/aws-config-bucket, src/ at v1.535.1),
# with Cloud Posse's account-map-bypass providers and account-verification mixins
# (cloudposse-terraform-components/mixins v0.5.0, copied unchanged).
#
# Deviations from upstream (owner decision 2026-11-04, E5a3):
#   - The bucket is encrypted with a customer managed KMS key: sse_algorithm is
#     "aws:kms" and kms_master_key_arn is a required input. Upstream hardcodes
#     sse_algorithm = "AES256" (SSE-S3) and has no key input, so the vendored
#     component could not take a key and trivy's AWS-0132 could not be resolved.
#   - enable_glacier_transition is passed through (upstream declares it but never
#     wires it; the module's default is the same true).
#   - Upstream's acl input is dropped: config-storage hardcodes acl "private" and
#     upstream never read it.
# Everything else (inputs, defaults, outputs, naming from the null-label context)
# is upstream's. Keep it close to upstream: diff against the tag before a refresh.
module "config_bucket" {
  #checkov:skip=CKV_TF_1:Cloud Posse's registry module pinned to an exact version, as upstream calls it
  source  = "cloudposse/config-storage/aws"
  version = "1.0.2"

  enable_glacier_transition          = var.enable_glacier_transition
  expiration_days                    = var.expiration_days
  force_destroy                      = false
  glacier_transition_days            = var.glacier_transition_days
  kms_master_key_arn                 = var.kms_master_key_arn
  lifecycle_rule_enabled             = var.lifecycle_rule_enabled
  noncurrent_version_expiration_days = var.noncurrent_version_expiration_days
  noncurrent_version_transition_days = var.noncurrent_version_transition_days
  sse_algorithm                      = "aws:kms"
  standard_transition_days           = var.standard_transition_days
  access_log_bucket_name             = var.access_log_bucket_name

  context = module.this.context
}
