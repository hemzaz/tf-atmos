# House override of the vendored Cloud Posse aws-organizational-unit
# (vendor.yaml), which has no lifecycle guard: Terraform merges this lifecycle
# block into main.tf's resource. A plan that destroys or replaces an OU (a
# changed parent_id forces a new OU, enabled set to false, the instance
# removed) fails instead of applying, so accounts and SCP attachments never
# lose their OU to a refactor. Move accounts out and drop this guard in its
# own reviewed PR first.
resource "aws_organizations_organizational_unit" "this" {
  lifecycle {
    prevent_destroy = true
  }
}
