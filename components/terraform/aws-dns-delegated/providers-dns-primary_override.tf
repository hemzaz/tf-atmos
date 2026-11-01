# House override of the vendored Cloud Posse aws-dns-delegated (vendor.yaml)
# providers-dns-primary.tf, whose aws.primary assumes iam-roles'
# dns_terraform_role_arn. Under the account-map-bypass providers mixin
# (account_map_enabled false, Cloud Posse Evolution 4) iam-roles is bypassed and
# that ARN is null, so aws.primary would silently reuse the stage account's own
# credentials. Here it assumes the network account's DNS delegation role
# instead: account_map.iam_role_arn_templates["dns-delegation"], the static
# map's role-ARN field (stacks/orgs/fnx/_defaults.yaml static_account_map,
# repeated by catalog/_base/account-map-bypass). A missing entry fails the plan
# (no fallback to ambient credentials). Cloud Posse's own account-map-less
# variant (mixins/providers-dns-primary.tf) uses an Atmos Auth profile instead,
# which waits for CI's move to Atmos auth (after E6a, owner OQ6).
# With account_map_enabled true the upstream behaviour is kept.
# Terraform merges this block into the upstream one argument by argument; the
# dynamic "assume_role" here replaces the upstream dynamic block.
provider "aws" {
  alias   = "primary"
  profile = var.account_map_enabled ? module.iam_roles.dns_terraform_profile_name : null

  dynamic "assume_role" {
    for_each = var.account_map_enabled ? compact([module.iam_roles.dns_terraform_role_arn]) : [var.account_map.iam_role_arn_templates["dns-delegation"]]
    content {
      role_arn = assume_role.value
    }
  }
}
