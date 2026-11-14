# House file in the vendored Cloud Posse aws-security-hub v2.2.1 (vendor.yaml),
# allowlisted in scripts/check-vendor.py HOUSE_FILE_ALLOWLIST: an override file
# cannot add a variable (E5c6, owner decision 2026-11-14: the management account
# is a Security Hub member in every region, a deviation from Cloud Posse, whose
# main.tf leaves it out of member_account_id_list). members_override.tf reads it.
#
# Security Hub enables a member through CreateMembers, except the organization
# management account, which "must enable Security Hub CSPM before the
# administrator account enables it as a member account" (Security Hub API
# reference, CreateMembers): Cloud Posse's root step already enables its hub
# (aws_securityhub_account, main.tf), so no resource is needed here.
variable "management_account_member_enabled" {
  type        = bool
  default     = false
  description = <<-DOC
  House (E5c6): make the organization management account (its hub enabled by the root step) a
  Security Hub member in the org-settings step. false is Cloud Posse's behaviour (its hub is
  standalone, unseen by the delegated administrator).
  DOC
}
