# House test of remote-state_override.tf (E5c1, OQ-W; a vendored target admits
# tests/*.tftest.hcl: scripts/check-vendor.py TESTS) and the E5c spike: each of
# Cloud Posse's three steps plans only its own resources, and org-settings takes
# the detector id from the house lookup, not remote state. Mocked providers, no
# AWS. Distinct synthetic IDs per account (the repo's placeholders are all
# 123456789012, which would hide a wrong member list).
mock_provider "aws" {
  mock_data "aws_organizations_organization" {
    defaults = {
      aws_service_access_principals = ["guardduty.amazonaws.com"]
    }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_guardduty_detector" {
    defaults = {
      id     = "d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5"
      arn    = "arn:aws:guardduty:us-east-1:222222222222:detector/d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5"
      status = "ENABLED"
    }
  }
}

mock_provider "awsutils" {}

# The catalog's values (stacks/catalog/aws-guardduty/defaults.yaml), with the
# US-region map: every account but prod-eu (OQ-RES).
variables {
  region      = "us-east-1"
  enabled     = true
  tenant      = "fnx"
  environment = "ue1"
  stage       = "security"
  name        = "aws-guardduty"

  account_map_enabled                             = false
  delegated_administrator_account_name            = "fnx-security"
  organization_management_account_name            = "fnx-root"
  finding_publishing_frequency                    = "FIFTEEN_MINUTES"
  s3_protection_enabled                           = true
  kubernetes_audit_logs_enabled                   = true
  malware_protection_scan_ec2_ebs_volumes_enabled = true
  lambda_network_logs_enabled                     = false
  runtime_monitoring_enabled                      = false
  account_map = {
    full_account_map = {
      "fnx-root"      = "111111111111"
      "fnx-security"  = "222222222222"
      "fnx-audit"     = "333333333333"
      "fnx-network"   = "444444444444"
      "fnx-identity"  = "555555555555"
      "fnx-artifacts" = "666666666666"
      "fnx-dev"       = "777777777777"
      "fnx-staging"   = "888888888888"
      "fnx-prod"      = "999999999999"
    }
    root_account_account_name = "fnx-root"
  }
}

# Step 1 (aws-guardduty/delegated-administrator, fnx-ue1-security): the
# detector, nothing org-wide, no lookup.
run "step1_delegated_administrator_detector_only" {
  command = plan
  override_data {
    target = data.aws_caller_identity.this[0]
    values = { account_id = "222222222222" }
  }
  assert {
    condition     = length(module.guardduty) == 1 && length(aws_guardduty_organization_admin_account.this) == 0
    error_message = "step 1 creates the detector and no delegation"
  }
  assert {
    condition     = length(awsutils_guardduty_organization_settings.this) == 0 && length(aws_guardduty_organization_configuration.this) == 0
    error_message = "step 1 configures no organization settings"
  }
  assert {
    condition     = length(module.guardduty_delegated_detector) == 0
    error_message = "step 1 looks up no detector"
  }
}

# Step 2 (aws-guardduty/root, fnx-ue1-root): only the delegation; the house
# lookup is skipped (upstream would read remote state here).
run "step2_root_delegation_only" {
  command = plan
  variables {
    stage = "root"
  }
  override_data {
    target = data.aws_caller_identity.this[0]
    values = { account_id = "111111111111" }
  }
  assert {
    condition     = one(aws_guardduty_organization_admin_account.this[*].admin_account_id) == "222222222222"
    error_message = "root delegates GuardDuty to fnx-security"
  }
  assert {
    condition     = length(module.guardduty) == 0 && length(aws_guardduty_organization_configuration.this) == 0
    error_message = "root creates no detector and no organization settings"
  }
  assert {
    condition     = length(module.guardduty_delegated_detector) == 0
    error_message = "root must not look up a detector"
  }
}

# Step 3 (aws-guardduty/org-settings, fnx-ue1-security): the detector id comes
# from the house lookup; members are the map minus self and the management
# account; prod-eu (absent from the US map) is no member.
run "step3_org_settings_us" {
  command = plan
  variables {
    admin_delegated = true
  }
  override_data {
    target = data.aws_caller_identity.this[0]
    values = { account_id = "222222222222" }
  }
  assert {
    condition     = length(module.guardduty_delegated_detector) == 1 && length(module.guardduty) == 0
    error_message = "org-settings looks up the detector and creates none"
  }
  assert {
    condition     = one(aws_guardduty_organization_configuration.this[*].detector_id) == "d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5"
    error_message = "the organization configuration uses the looked-up detector"
  }
  assert {
    condition     = one(aws_guardduty_organization_configuration.this[*].auto_enable_organization_members) == "NEW"
    error_message = "CP default NEW (existing members get the org configuration through CreateMembers)"
  }
  assert {
    condition = toset(one(awsutils_guardduty_organization_settings.this[*].member_accounts)) == toset([
      "333333333333", "444444444444", "555555555555", "666666666666", "777777777777", "888888888888", "999999999999"
    ])
    error_message = "members are the US map minus fnx-security and fnx-root"
  }
  assert {
    condition = (length(aws_guardduty_organization_configuration_feature.s3_data_events) == 1 &&
      length(aws_guardduty_organization_configuration_feature.eks_audit_logs) == 1 &&
      length(aws_guardduty_organization_configuration_feature.ebs_malware_protection) == 1 &&
      length(aws_guardduty_organization_configuration_feature.lambda_network_logs) == 0 &&
    length(aws_guardduty_organization_configuration_feature.runtime_monitoring) == 0)
    error_message = "OQ-GD: S3, EKS audit logs and EBS malware on; Lambda and runtime off"
  }
  assert {
    condition     = output.guardduty_delegated_detector_id == "d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5"
    error_message = "the output reports the looked-up detector"
  }
}

# The EU-region map adds prod-eu, which then is a member.
run "step3_org_settings_eu_includes_prod_eu" {
  command = plan
  variables {
    region          = "eu-west-1"
    environment     = "ew1"
    admin_delegated = true
    account_map = {
      full_account_map = {
        "fnx-root"     = "111111111111"
        "fnx-security" = "222222222222"
        "fnx-prod"     = "999999999999"
        "fnx-prod-eu"  = "121212121212"
      }
      root_account_account_name = "fnx-root"
    }
  }
  override_data {
    target = data.aws_caller_identity.this[0]
    values = { account_id = "222222222222" }
  }
  assert {
    condition     = toset(one(awsutils_guardduty_organization_settings.this[*].member_accounts)) == toset(["999999999999", "121212121212"])
    error_message = "EU members include prod-eu"
  }
}

# Account verification: step 1/3 in fnx-ue1-security's account passes, run in
# the management account it fails.
run "verification_security_in_root_fails" {
  command = plan
  override_data {
    target = data.aws_caller_identity.this[0]
    values = { account_id = "111111111111" }
  }
  expect_failures = [terraform_data.account_verification]
}

run "verification_root_and_security_pass" {
  command = plan
  variables {
    stage = "root"
  }
  override_data {
    target = data.aws_caller_identity.this[0]
    values = { account_id = "111111111111" }
  }
  assert {
    condition     = length(terraform_data.account_verification) == 1
    error_message = "verification runs (and passes) for fnx-ue1-root"
  }
}
