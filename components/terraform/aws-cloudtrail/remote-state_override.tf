# House override of the vendored Cloud Posse aws-cloudtrail v1.539.0
# (vendor.yaml) remote-state.tf. Terraform merges these arguments into its
# module blocks.
#
# version: remote-state.tf pins cloudposse/stack-config 1.8.0, which requires
# cloudposse/utils < 2.0.0, while the account-map-bypass providers mixin
# sources the vendored account-map iam-roles module (v1.537.3), whose
# stack-config 2.0.1 requires utils >= 2.0.0: no utils release satisfies both
# and init fails. The blocks take the same inputs at 2.0.1 (the version the
# dns components and iam-roles use). Drop the version lines when upstream
# bumps stack-config.
#
# cloudtrail_bucket bypass (E5b, owner decision OQ-E): upstream reads the
# audit account's cloudtrail-bucket through Atmos remote state, which needs the
# Atmos config and that stack's live state at plan time and is invisible to
# the house state-read checks. Bypassed, the module returns these defaults:
# the bucket's null-label id, computed the way the cloudtrail-bucket instance
# names it (catalog/aws-cloudtrail-bucket: <tenant>-<environment>-<stage>-
# cloudtrail, vars.name "cloudtrail", the vendored label order) from this
# trail's tenant and its cloudtrail_bucket_environment_name/_stage_name. No
# bucket name is typed anywhere; the catalog sets the environment and stage of
# the residency's audit stack, and check-data-residency.py polices them.
module "cloudtrail_bucket" {
  #checkov:skip=CKV_TF_1:an override block sets no source; its source is the vendored remote-state.tf registry module, pinned exactly here
  #checkov:skip=CKV_TF_2:an override block sets no source; its source is the vendored remote-state.tf registry module, pinned exactly here
  version = "2.0.1"

  bypass = true
  defaults = {
    cloudtrail_bucket_id = format("%s-%s-%s-cloudtrail",
    module.this.tenant, var.cloudtrail_bucket_environment_name, var.cloudtrail_bucket_stage_name)
    cloudtrail_bucket_arn = format("arn:%s:s3:::%s-%s-%s-cloudtrail", join("", data.aws_partition.current[*].partition),
    module.this.tenant, var.cloudtrail_bucket_environment_name, var.cloudtrail_bucket_stage_name)
  }
}

# account_map keeps upstream's bypass (!var.account_map_enabled; the
# account-map-bypass abstract sets it false) and its static defaults.
module "account_map" {
  #checkov:skip=CKV_TF_1:an override block sets no source; its source is the vendored remote-state.tf registry module, pinned exactly here
  #checkov:skip=CKV_TF_2:an override block sets no source; its source is the vendored remote-state.tf registry module, pinned exactly here
  version = "2.0.1"
}
