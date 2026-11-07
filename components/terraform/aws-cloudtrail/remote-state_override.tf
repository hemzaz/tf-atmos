# House override of the vendored Cloud Posse aws-cloudtrail v1.539.0
# (vendor.yaml). Its remote-state.tf pins cloudposse/stack-config 1.8.0, which
# requires cloudposse/utils < 2.0.0, while the account-map-bypass providers
# mixin sources the vendored account-map iam-roles module (v1.537.3), whose
# stack-config 2.0.1 requires utils >= 2.0.0: no utils release satisfies both
# and init fails. Terraform merges these version arguments into
# remote-state.tf's module blocks, which take the same inputs at 2.0.1 (the
# version the dns components and iam-roles use). Drop this file when upstream
# bumps stack-config.
module "cloudtrail_bucket" {
  #checkov:skip=CKV_TF_1:an override block carries only version; its source is the vendored remote-state.tf registry module, pinned exactly here
  #checkov:skip=CKV_TF_2:an override block carries only version; its source is the vendored remote-state.tf registry module, pinned exactly here
  version = "2.0.1"
}

module "account_map" {
  #checkov:skip=CKV_TF_1:an override block carries only version; its source is the vendored remote-state.tf registry module, pinned exactly here
  #checkov:skip=CKV_TF_2:an override block carries only version; its source is the vendored remote-state.tf registry module, pinned exactly here
  version = "2.0.1"
}
