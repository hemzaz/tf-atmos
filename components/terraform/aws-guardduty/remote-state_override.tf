# House override of the vendored Cloud Posse aws-guardduty v3.0.2 (vendor.yaml)
# remote-state.tf. Terraform merges these arguments into its module block;
# account_map is untouched (upstream bypasses it with !var.account_map_enabled,
# which the account-map-bypass abstract sets false).
#
# guardduty_delegated_detector (E5c, owner decision OQ-W, OQ-E precedent):
# upstream reads step 1's detector through Atmos remote state of the delegated
# administrator's stack, live at plan time and invisible to the house
# state-read checks, in root and org-settings alike. Bypassed, the module
# returns these defaults: the detector detector_house.tf looks up in this
# account and region. The module exists only where main.tf reads it,
# org-settings (create_org_configuration); root and step 1 have none. Pointing
# the module at a local house module instead needs `version = null`, which
# Atmos's terraform-config-inspect pre-parse rejects. Upstream ask: a
# delegated_detector_id input in place of the read.
module "guardduty_delegated_detector" {
  #checkov:skip=CKV_TF_1:an override block sets no source; its source is the vendored remote-state.tf registry module, pinned exactly there
  #checkov:skip=CKV_TF_2:an override block sets no source; its source is the vendored remote-state.tf registry module, pinned exactly there
  count  = local.create_org_configuration ? 1 : 0
  bypass = true
  defaults = {
    guardduty_detector_id  = one(data.aws_guardduty_detector.delegated[*].id)
    guardduty_detector_arn = one(data.aws_guardduty_detector.delegated[*].arn)
  }
}
