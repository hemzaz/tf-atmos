# House override of the vendored Cloud Posse aws-security-hub v2.2.1 (vendor.yaml)
# main.tf locals (E5c6, owner decision 2026-11-14). Terraform merges a locals
# override value by value, so only member_account_id_list changes: upstream
# drops both this account and the organization management account from the
# org-settings step's CreateMembers list (awsutils_security_hub_organization_settings);
# with management_account_member_enabled (management-member_house.tf) only this
# account is dropped, so the management account is a member. The residency is
# still the account map's (catalog aws-security-hub org-settings-us/-eu, owner
# OQ-RES): the management account is a shared account, in both maps.
locals {
  member_account_id_list = [
    for a in keys(local.account_map) : local.account_map[a]
    if local.account_map[a] != local.current_account_id
    && (var.management_account_member_enabled || local.account_map[a] != local.org_management_account_id)
  ]
}
