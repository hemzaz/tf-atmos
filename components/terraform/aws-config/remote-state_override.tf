# House override of the vendored Cloud Posse aws-config v3.1.1 (vendor.yaml)
# remote-state.tf. Terraform merges these arguments into its module blocks;
# account_map is untouched (upstream already bypasses it with
# !var.account_map_enabled, which the account-map-bypass abstract sets false).
#
# config_bucket bypass (E5b, owner decision OQ-E): upstream reads the audit
# account's config-bucket through Atmos remote state, which needs the Atmos
# config and that stack's live state at plan time and is invisible to the
# house state-read checks. Bypassed, the module returns these defaults: the
# bucket's name, computed the way the house aws-config-bucket names it
# (module.aws_config_label: the instance's null-label id plus attribute
# "aws-config", so <tenant>-<environment>-<stage>-config-aws-config with
# catalog/aws-config-bucket's vars.name "config" and the vendored label order)
# from config_bucket_tenant (else this recorder's tenant), config_bucket_env
# and config_bucket_stage. No bucket name is typed anywhere; the catalog sets
# the environment and stage of the residency's audit stack, and
# check-data-residency.py polices them.
module "config_bucket" {
  #checkov:skip=CKV_TF_1:an override block sets no source; its source is the vendored remote-state.tf registry module, pinned exactly there
  #checkov:skip=CKV_TF_2:an override block sets no source; its source is the vendored remote-state.tf registry module, pinned exactly there
  bypass = true
  defaults = {
    config_bucket_id = format("%s-%s-%s-config-aws-config",
    var.config_bucket_tenant != "" ? var.config_bucket_tenant : module.this.tenant, var.config_bucket_env, var.config_bucket_stage)
    config_bucket_arn = format("arn:%s:s3:::%s-%s-%s-config-aws-config", local.partition,
    var.config_bucket_tenant != "" ? var.config_bucket_tenant : module.this.tenant, var.config_bucket_env, var.config_bucket_stage)
  }
}

# global_collector_region bypass: outside the global collector region
# upstream reads the collector region's recorder role from the remote state of
# a component named "aws-config-<region code>" (CP's one-instance-per-region
# naming), which the house stacks do not have: each stack's instance is
# aws-config. The catalog variants that record outside the collector region
# set iam_role_arn instead (main-region: !terraform.state of the home stack;
# main-core-region: the role's convention ARN), which main.tf prefers over this
# read, so the read is never needed. The default is that same ARN, null when
# unset: a recorder outside the collector region with no iam_role_arn then fails
# at plan (main.tf joins a null), as upstream's missing-state read would, instead
# of planning role_arn = "" and failing only at apply.
module "global_collector_region" {
  #checkov:skip=CKV_TF_1:an override block sets no source; its source is the vendored remote-state.tf registry module, pinned exactly there
  #checkov:skip=CKV_TF_2:an override block sets no source; its source is the vendored remote-state.tf registry module, pinned exactly there
  bypass = true
  defaults = {
    aws_config_iam_role = var.iam_role_arn
  }
}
