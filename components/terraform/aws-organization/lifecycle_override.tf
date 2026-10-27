# House override of the vendored Cloud Posse aws-organization (vendor.yaml),
# which has no lifecycle guard: Terraform merges this lifecycle block into
# main.tf's resource. A plan that destroys or replaces the Organization
# (feature_set ALL back to CONSOLIDATED_BILLING forces a new one, enabled set
# to false, the instance removed) fails instead of applying. Deleting an organization is a
# deliberate, manual act: drop this guard in its own reviewed PR first.
resource "aws_organizations_organization" "this" {
  lifecycle {
    prevent_destroy = true
  }
}
