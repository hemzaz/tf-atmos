# House override of the vendored Cloud Posse aws-guardduty v3.0.2 (vendor.yaml)
# remote-state.tf. Terraform merges these arguments into its module block;
# account_map is untouched (upstream bypasses it with !var.account_map_enabled,
# which the account-map-bypass abstract sets false).
#
# guardduty_delegated_detector (E5c, owner decision OQ-W, OQ-E precedent):
# upstream reads step 1's detector id through Atmos remote state of the
# delegated administrator's stack, live at plan time and invisible to the house
# state-read checks, in root and in org-settings alike. Here the module is the
# house data-source lookup instead (_library/security/guardduty-delegated-detector:
# the detector in this provider's account and region, where step 1 made it),
# and it exists only where main.tf reads it: org-settings
# (create_org_configuration). Root delegates and reads no detector, so it looks
# up nothing; step 1 creates the detector it would read. Upstream ask: a
# delegated_detector_id input in place of the read.
module "guardduty_delegated_detector" {
  #checkov:skip=CKV_TF_1:a local house module (relative source), no registry or git ref to pin
  source  = "../_library/security/guardduty-delegated-detector"
  version = null
  count   = local.create_org_configuration ? 1 : 0
}
