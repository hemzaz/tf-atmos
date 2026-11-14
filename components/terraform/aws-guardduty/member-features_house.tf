# House file in the vendored Cloud Posse aws-guardduty v3.0.2 (vendor.yaml),
# allowlisted in scripts/check-vendor.py HOUSE_FILE_ALLOWLIST: an override file
# cannot add a resource, nor change main.tf's depends_on (E5c6, #525 review).
#
# Cloud Posse's org-settings step orders aws_guardduty_organization_configuration
# (auto-enable NEW) and its features AFTER awsutils_guardduty_organization_settings
# (main.tf depends_on), so step 3's first apply adds the members with CreateMembers
# before the organization configuration exists, and awsutils never calls
# CreateMembers again (only on create or a member_accounts change). The accounts
# that are members at that first apply, the management account included, can keep
# the managed features off. These resources set each managed feature ENABLED on
# each member explicitly (UpdateMemberDetectors), after both.
#
# The features follow the same flags Cloud Posse uses for the organization
# configuration (a false flag stays unmanaged, as there), and the members are
# main.tf's member_account_id_list (members_override.tf), so the residency is the
# account map's: no prod-eu in a US region, prod-eu in an EU one (owner OQ-RES).
# The provider has no import for this resource and its delete only drops it from
# state (the feature stays enabled).
locals {
  house_member_features = local.create_org_configuration ? compact([
    var.s3_protection_enabled ? "S3_DATA_EVENTS" : "",
    var.kubernetes_audit_logs_enabled ? "EKS_AUDIT_LOGS" : "",
    var.malware_protection_scan_ec2_ebs_volumes_enabled ? "EBS_MALWARE_PROTECTION" : "",
  ]) : []
  house_member_feature_pairs = local.create_org_configuration ? {
    for pair in setproduct(local.member_account_id_list, local.house_member_features) :
    "${pair[0]}/${pair[1]}" => { account_id = pair[0], name = pair[1] }
  } : {}
}

resource "aws_guardduty_member_detector_feature" "house" {
  for_each = local.house_member_feature_pairs

  detector_id = module.guardduty_delegated_detector[0].outputs.guardduty_detector_id
  account_id  = each.value.account_id
  name        = each.value.name
  status      = "ENABLED"

  # The members exist (CreateMembers) and the organization configuration and its
  # features are in place: the order Cloud Posse's main.tf does not give.
  depends_on = [
    awsutils_guardduty_organization_settings.this,
    aws_guardduty_organization_configuration.this,
    aws_guardduty_organization_configuration_feature.s3_data_events,
    aws_guardduty_organization_configuration_feature.eks_audit_logs,
    aws_guardduty_organization_configuration_feature.ebs_malware_protection,
  ]
}
