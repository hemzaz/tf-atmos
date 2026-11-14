# House file in the vendored Cloud Posse aws-guardduty v3.0.2 (vendor.yaml),
# allowlisted in scripts/check-vendor.py HOUSE_FILE_ALLOWLIST: an override file
# cannot add a block, and this variable and detector are new (E5c6, owner
# decision 2026-11-14: the management account is a GuardDuty member in every
# region, a deviation from Cloud Posse, whose main.tf leaves it out of
# member_account_id_list).
#
# GuardDuty enables a member through CreateMembers, except the organization
# management account: "Before the management account account gets added as a
# GuardDuty member, it must have GuardDuty enabled" (GuardDuty User Guide,
# add-member-accounts-guardduty-organization.html), and Cloud Posse's root
# step only delegates. So the root step (create_org_delegation, the
# management account's own stack, in the same region) also enables the
# management account's detector, and members_override.tf adds the management
# account to the org-settings step's members. Once it is a member, the delegated
# administrator's organization configuration (step 3's features) applies to it.
variable "management_account_member_enabled" {
  type        = bool
  default     = false
  description = <<-DOC
  House (E5c6): make the organization management account a GuardDuty member. In the root step
  it enables the management account's detector (GuardDuty cannot enable it through CreateMembers);
  in the org-settings step the management account joins the members. false is Cloud Posse's
  behaviour (no detector there, not a member).
  DOC
}

resource "aws_guardduty_detector" "management" {
  #checkov:skip=CKV2_AWS_3:the management account's detector becomes a member of the delegated administrator (fnx-security) in org-settings, step 3; this resource cannot see that membership
  count = local.create_org_delegation && var.management_account_member_enabled ? 1 : 0

  enable = true
  # The administrator's frequency: a member inherits it, so the same value
  # never drifts once the account is a member.
  finding_publishing_frequency = var.finding_publishing_frequency

  tags = module.this.tags
}
