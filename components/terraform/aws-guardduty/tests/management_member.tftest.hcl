# House test of management-member_house.tf and members_override.tf (E5c6, owner 2026-11-14: the
# management account is a GuardDuty member in every region, unlike Cloud Posse). Mocked providers,
# no AWS. Distinct synthetic IDs per account; fnx-root (111111111111) is the management account.
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

# The catalog's values (stacks/catalog/aws-guardduty/defaults.yaml, management_account_member_enabled
# true), with the US-region map: every account but prod-eu (OQ-RES).
variables {
  region      = "us-east-1"
  enabled     = true
  tenant      = "fnx"
  environment = "ue1"
  stage       = "security"
  name        = "aws-guardduty"

  account_map_enabled                             = false
  delegated_administrator_account_name            = "fnx-security"
  management_account_member_enabled               = true
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

# Step 2 (aws-guardduty/root, fnx-ue1-root): the delegation plus the management account's own
# detector, at the administrator's frequency (GuardDuty cannot enable it through CreateMembers).
run "root_enables_the_management_detector" {
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
    error_message = "root still delegates GuardDuty to fnx-security"
  }
  assert {
    condition     = length(aws_guardduty_detector.management) == 1 && one(aws_guardduty_detector.management[*].enable) == true
    error_message = "root enables the management account's detector"
  }
  assert {
    condition     = one(aws_guardduty_detector.management[*].finding_publishing_frequency) == "FIFTEEN_MINUTES"
    error_message = "the management detector publishes at the administrator's frequency"
  }
  assert {
    condition     = length(module.guardduty) == 0 && length(aws_guardduty_organization_configuration.this) == 0
    error_message = "root creates no CP detector module and no organization settings"
  }
}

# Steps 1 and 3 run in the security account: no management detector there.
run "security_steps_create_no_management_detector" {
  command = plan
  override_data {
    target = data.aws_caller_identity.this[0]
    values = { account_id = "222222222222" }
  }
  assert {
    condition     = length(aws_guardduty_detector.management) == 0 && length(module.guardduty) == 1
    error_message = "step 1 creates the administrator's detector only"
  }
}

# Step 3 in a US region: the management account is a member; prod-eu (absent from the US map) and
# the administrator itself are not.
run "org_settings_us_members_include_the_management_account" {
  command = plan
  variables {
    admin_delegated = true
  }
  override_data {
    target = data.aws_caller_identity.this[0]
    values = { account_id = "222222222222" }
  }
  assert {
    condition = toset(one(awsutils_guardduty_organization_settings.this[*].member_accounts)) == toset([
      "111111111111", "333333333333", "444444444444", "555555555555", "666666666666", "777777777777",
      "888888888888", "999999999999"
    ])
    error_message = "US members are the US map minus fnx-security, fnx-root included"
  }
  assert {
    condition     = length(aws_guardduty_detector.management) == 0
    error_message = "org-settings creates no management detector"
  }
}

# Step 3 in an EU region: the full map, so prod-eu and the management account are members.
run "org_settings_eu_members_include_management_and_prod_eu" {
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
    condition     = toset(one(awsutils_guardduty_organization_settings.this[*].member_accounts)) == toset(["111111111111", "999999999999", "121212121212"])
    error_message = "EU members are the full map minus fnx-security"
  }
}

# Cloud Posse's behaviour with the flag off: no management detector, the management account no member.
run "flag_off_is_cloud_posse" {
  command = plan
  variables {
    admin_delegated                   = true
    management_account_member_enabled = false
  }
  override_data {
    target = data.aws_caller_identity.this[0]
    values = { account_id = "222222222222" }
  }
  assert {
    condition     = !contains(one(awsutils_guardduty_organization_settings.this[*].member_accounts), "111111111111")
    error_message = "with the flag off the management account is no member (CP main.tf)"
  }
}

run "flag_off_root_has_no_detector" {
  command = plan
  variables {
    stage                             = "root"
    management_account_member_enabled = false
  }
  override_data {
    target = data.aws_caller_identity.this[0]
    values = { account_id = "111111111111" }
  }
  assert {
    condition     = length(aws_guardduty_detector.management) == 0
    error_message = "with the flag off root only delegates"
  }
}
