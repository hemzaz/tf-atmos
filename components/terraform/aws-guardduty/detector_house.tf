# House file in the vendored Cloud Posse aws-guardduty v3.0.2 (vendor.yaml),
# allowlisted in scripts/check-vendor.py HOUSE_FILE_ALLOWLIST: an override file
# cannot add a block, and this data source is new (E5c, owner decision OQ-W).
#
# The delegated administrator's detector, looked up where CP's org-settings
# step runs: the security account, in the region step 1 created the detector
# in, its only detector there. remote-state_override.tf hands it to main.tf in
# place of upstream's live remote-state read. Only org-settings reads it:
# step 1 creates the detector and root delegates without one.
data "aws_guardduty_detector" "delegated" {
  count = local.create_org_configuration ? 1 : 0

  lifecycle {
    postcondition {
      condition     = self.status == "ENABLED"
      error_message = "The GuardDuty detector ${self.id} is ${self.status}: apply ${var.delegated_administrator_component_name} (step 1) in this account and region before org-settings."
    }
  }
}
