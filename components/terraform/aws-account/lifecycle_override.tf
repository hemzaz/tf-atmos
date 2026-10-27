# House override of the vendored Cloud Posse aws-account (vendor.yaml), whose
# lifecycle block only ignores iam_user_access_to_billing and role_name:
# Terraform merges this block into main.tf's argument by argument, so both are
# kept. A plan that destroys or replaces an account (a changed email forces a
# new one, enabled set to false, the instance removed) fails instead of
# applying: with close_on_deletion false a destroy removes the account from the
# organization (losing its SCPs and trusted access) and with true it closes it.
# A parent_id change (MoveAccount) or a name change (aws provider 5.100: name
# is not ForceNew) is in place and still applies. Leaving or closing an
# account is a deliberate, manual act: drop this guard in its own reviewed PR
# first.
resource "aws_organizations_account" "this" {
  lifecycle {
    prevent_destroy = true
  }
}
