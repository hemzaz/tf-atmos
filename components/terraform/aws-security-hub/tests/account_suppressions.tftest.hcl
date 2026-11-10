# House test of account-suppressions_house.tf (E5c1; a vendored target admits
# tests/*.tftest.hcl: scripts/check-vendor.py TESTS). Mocked providers, no AWS.
# Distinct synthetic IDs per account (the repo's placeholders are all
# 123456789012, which would hide a wrong account filter).
mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { name = "eu-west-1", region = "eu-west-1" }
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

# fnx-ew1-security's org-settings (catalog aws-security-hub/org-settings-eu
# plus eu-shared-account-suppressions), in the security account.
variables {
  region                               = "eu-west-1"
  enabled                              = true
  tenant                               = "fnx"
  environment                          = "ew1"
  stage                                = "security"
  name                                 = "aws-security-hub"
  account_map_enabled                  = false
  admin_delegated                      = true
  delegated_administrator_account_name = "fnx-security"
  finding_aggregator_enabled           = false
  account_map = {
    full_account_map = {
      "fnx-root"     = "111111111111"
      "fnx-security" = "222222222222"
      "fnx-prod"     = "999999999999"
      "fnx-prod-eu"  = "121212121212"
    }
    root_account_account_name = "fnx-root"
  }
  account_scoped_control_suppressions = {
    shared-iam = {
      control_ids     = ["IAM.1", "KMS.1"]
      account_names   = ["fnx-root", "fnx-security", "fnx-prod"]
      disabled_reason = "home region us-east-1"
    }
  }
}

run "org_settings_rule_filters_the_shared_accounts" {
  command = plan
  override_data {
    target = data.aws_caller_identity.this[0]
    values = { account_id = "222222222222" }
  }
  assert {
    condition     = length(aws_securityhub_automation_rule.suppress_account_control_findings) == 1
    error_message = "one rule per entry in the delegated administrator's org-settings"
  }
  assert {
    condition = toset([for c in aws_securityhub_automation_rule.suppress_account_control_findings["shared-iam"].criteria[0].aws_account_id : c.value]) == toset([
      "111111111111", "222222222222", "999999999999"
    ])
    error_message = "the rule matches the named accounts' IDs only (prod-eu's findings stay)"
  }
  assert {
    condition     = toset([for c in aws_securityhub_automation_rule.suppress_account_control_findings["shared-iam"].criteria[0].compliance_security_control_id : c.value]) == toset(["IAM.1", "KMS.1"])
    error_message = "the rule matches the listed controls"
  }
}

# Step 1 (admin_delegated false) and root make no rule.
run "step1_and_root_make_no_rule" {
  command = plan
  variables {
    admin_delegated = false
  }
  override_data {
    target = data.aws_caller_identity.this[0]
    values = { account_id = "222222222222" }
  }
  assert {
    condition     = length(aws_securityhub_automation_rule.suppress_account_control_findings) == 0
    error_message = "only org-settings makes rules"
  }
}

run "too_many_control_ids_fails" {
  command = plan
  variables {
    account_scoped_control_suppressions = {
      x = {
        control_ids     = [for i in range(21) : "IAM.${i}"]
        account_names   = ["fnx-prod"]
        disabled_reason = "r"
      }
    }
  }
  override_data {
    target = data.aws_caller_identity.this[0]
    values = { account_id = "222222222222" }
  }
  expect_failures = [var.account_scoped_control_suppressions]
}
