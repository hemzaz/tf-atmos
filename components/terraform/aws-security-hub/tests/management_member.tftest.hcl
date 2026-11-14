# House test of management-member_house.tf and members_override.tf (E5c6, owner 2026-11-14: the
# management account is a Security Hub member in every region, unlike Cloud Posse). Mocked
# providers, no AWS. Distinct synthetic IDs per account; fnx-root (111111111111) is the management
# account.
mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { name = "us-east-1", region = "us-east-1" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_organizations_organization" {
    defaults = { aws_service_access_principals = ["securityhub.amazonaws.com"] }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
}

mock_provider "awsutils" {}

# The catalog's org-settings-us values, the US map (no prod-eu, OQ-RES).
variables {
  region                               = "us-east-1"
  enabled                              = true
  tenant                               = "fnx"
  environment                          = "ue1"
  stage                                = "security"
  name                                 = "aws-security-hub"
  account_map_enabled                  = false
  admin_delegated                      = true
  delegated_administrator_account_name = "fnx-security"
  management_account_member_enabled    = true
  finding_aggregator_enabled           = false
  account_map = {
    full_account_map = {
      "fnx-root"     = "111111111111"
      "fnx-security" = "222222222222"
      "fnx-audit"    = "333333333333"
      "fnx-prod"     = "999999999999"
    }
    root_account_account_name = "fnx-root"
  }
}

run "org_settings_us_members_include_the_management_account" {
  command = plan
  override_data {
    target = data.aws_caller_identity.this[0]
    values = { account_id = "222222222222" }
  }
  assert {
    condition     = toset(one(awsutils_security_hub_organization_settings.this[*].member_accounts)) == toset(["111111111111", "333333333333", "999999999999"])
    error_message = "US members are the US map minus fnx-security, fnx-root included"
  }
  assert {
    condition     = one(aws_securityhub_organization_configuration.this[*].organization_configuration[0].configuration_type) == "LOCAL"
    error_message = "CP's LOCAL configuration (sticky)"
  }
  assert {
    condition     = one(aws_securityhub_organization_configuration.this[*].auto_enable) == true && one(aws_securityhub_organization_configuration.this[*].auto_enable_standards) == "DEFAULT"
    error_message = "auto-enable new accounts with the default standards"
  }
}

run "org_settings_eu_members_include_management_and_prod_eu" {
  command = plan
  variables {
    region      = "eu-west-1"
    environment = "ew1"
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
    condition     = toset(one(awsutils_security_hub_organization_settings.this[*].member_accounts)) == toset(["111111111111", "999999999999", "121212121212"])
    error_message = "EU members are the full map minus fnx-security"
  }
}

# The root step enables the management account's hub (CP main.tf), the precondition of its
# membership; the house adds no resource there.
run "root_enables_the_management_hub" {
  command = plan
  variables {
    stage           = "root"
    admin_delegated = false
  }
  override_data {
    target = data.aws_caller_identity.this[0]
    values = { account_id = "111111111111" }
  }
  assert {
    condition     = length(aws_securityhub_account.this) == 1 && length(aws_securityhub_organization_admin_account.this) == 1
    error_message = "root delegates and enables the management account's hub"
  }
  assert {
    condition     = length(awsutils_security_hub_organization_settings.this) == 0
    error_message = "root adds no members"
  }
}

run "flag_off_is_cloud_posse" {
  command = plan
  variables {
    management_account_member_enabled = false
  }
  override_data {
    target = data.aws_caller_identity.this[0]
    values = { account_id = "222222222222" }
  }
  assert {
    condition     = toset(one(awsutils_security_hub_organization_settings.this[*].member_accounts)) == toset(["333333333333", "999999999999"])
    error_message = "with the flag off the management account is no member (CP main.tf)"
  }
}
