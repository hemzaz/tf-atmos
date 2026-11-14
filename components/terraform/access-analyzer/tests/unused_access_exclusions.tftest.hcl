# House test of unused-access-exclusions_house.tf and unused-access_override.tf (E5c7, owner
# 2026-11-14: the global unused-access analyzer keeps EU data in the EU). Mocked provider, no AWS.
# Distinct synthetic IDs per account (the repo's placeholders are all 123456789012, which would hide
# a wrong account); fnx-security (222222222222) is the delegated administrator, the analyzer owner.
mock_provider "aws" {}

# The full map (catalog/_base account-map-bypass), as both residencies' instances use it.
variables {
  region                                            = "us-east-1"
  enabled                                           = true
  tenant                                            = "fnx"
  environment                                       = "ue1"
  stage                                             = "security"
  name                                              = "access-analyzer"
  account_map_enabled                               = false
  delegated_administrator_account_name              = "fnx-security"
  organizations_delegated_administrator_enabled     = false
  accessanalyzer_organization_enabled               = false
  accessanalyzer_organization_unused_access_enabled = true
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
      "fnx-prod-eu"   = "121212121212"
    }
    root_account_account_name = "fnx-root"
  }
}

# fnx-ue1-security (catalog access-analyzer/delegated-administrator-us-unused-access): no external-access
# analyzer, the unused-access analyzer without prod-eu.
run "us_unused_access_excludes_the_all_gdpr_accounts" {
  command = plan
  variables {
    unused_access_exclusion_account_names = ["fnx-prod-eu"]
  }
  override_data {
    target = data.aws_caller_identity.this[0]
    values = { account_id = "222222222222" }
  }
  assert {
    condition     = length(aws_accessanalyzer_analyzer.organization) == 0
    error_message = "no ORGANIZATION external-access analyzer in a US region"
  }
  assert {
    condition     = aws_accessanalyzer_analyzer.organization_unused_access[0].type == "ORGANIZATION_UNUSED_ACCESS"
    error_message = "the unused-access analyzer"
  }
  assert {
    condition     = aws_accessanalyzer_analyzer.organization_unused_access[0].configuration[0].unused_access[0].unused_access_age == 30
    error_message = "CP's unused_access_age is kept"
  }
  assert {
    condition     = toset(aws_accessanalyzer_analyzer.organization_unused_access[0].configuration[0].unused_access[0].analysis_rule[0].exclusion[0].account_ids) == toset(["121212121212"])
    error_message = "the analysis rule excludes exactly prod-eu's ID"
  }
  assert {
    condition     = length(aws_accessanalyzer_analyzer.organization_unused_access[0].configuration[0].unused_access[0].analysis_rule[0].exclusion) == 1
    error_message = "one exclusion criterion"
  }
}

# fnx-ew1-security (catalog access-analyzer/delegated-administrator-eu-unused-access): the
# external-access analyzer, and the unused-access analyzer over prod-eu (and the security account,
# which AWS does not let the owner exclude).
run "eu_unused_access_excludes_the_shared_accounts_but_the_owner" {
  command = plan
  variables {
    region                              = "eu-west-1"
    environment                         = "ew1"
    accessanalyzer_organization_enabled = true
    unused_access_exclusion_account_names = [
      "fnx-root", "fnx-audit", "fnx-network", "fnx-identity", "fnx-artifacts", "fnx-dev", "fnx-staging", "fnx-prod",
    ]
  }
  override_data {
    target = data.aws_caller_identity.this[0]
    values = { account_id = "222222222222" }
  }
  assert {
    condition     = aws_accessanalyzer_analyzer.organization[0].type == "ORGANIZATION"
    error_message = "the external-access analyzer in the EU"
  }
  assert {
    condition = toset(aws_accessanalyzer_analyzer.organization_unused_access[0].configuration[0].unused_access[0].analysis_rule[0].exclusion[0].account_ids) == toset([
      "111111111111", "333333333333", "444444444444", "555555555555", "666666666666", "777777777777", "888888888888", "999999999999",
    ])
    error_message = "the EU rule excludes every shared account but the security account, never prod-eu"
  }
}

# Unset (CP's behaviour): no analysis rule.
run "no_exclusions_is_cp_behaviour" {
  command = plan
  override_data {
    target = data.aws_caller_identity.this[0]
    values = { account_id = "222222222222" }
  }
  assert {
    condition     = length(aws_accessanalyzer_analyzer.organization_unused_access[0].configuration[0].unused_access[0].analysis_rule) == 0
    error_message = "no analysis rule when no account is excluded"
  }
  assert {
    condition     = aws_accessanalyzer_analyzer.organization_unused_access[0].configuration[0].unused_access[0].unused_access_age == 30
    error_message = "CP's unused_access_age"
  }
}

# The root step (fnx-ue1-root) creates no analyzer, whatever the list.
run "root_step_makes_no_analyzer" {
  command = plan
  variables {
    stage                                             = "root"
    organizations_delegated_administrator_enabled     = true
    accessanalyzer_organization_unused_access_enabled = false
  }
  override_data {
    target = data.aws_caller_identity.this[0]
    values = { account_id = "111111111111" }
  }
  assert {
    condition     = length(aws_accessanalyzer_analyzer.organization_unused_access) == 0 && length(aws_accessanalyzer_analyzer.organization) == 0
    error_message = "the delegation step makes no analyzer"
  }
}

run "excluding_the_owner_account_fails" {
  command = plan
  variables {
    unused_access_exclusion_account_names = ["fnx-prod-eu", "fnx-security"]
  }
  override_data {
    target = data.aws_caller_identity.this[0]
    values = { account_id = "222222222222" }
  }
  expect_failures = [var.unused_access_exclusion_account_names]
}

run "an_unknown_account_name_fails" {
  command = plan
  variables {
    unused_access_exclusion_account_names = ["fnx-prodeu"]
  }
  override_data {
    target = data.aws_caller_identity.this[0]
    values = { account_id = "222222222222" }
  }
  expect_failures = [var.unused_access_exclusion_account_names]
}

run "a_repeated_account_fails" {
  command = plan
  variables {
    unused_access_exclusion_account_names = ["fnx-prod-eu", "fnx-prod-eu"]
  }
  override_data {
    target = data.aws_caller_identity.this[0]
    values = { account_id = "222222222222" }
  }
  expect_failures = [var.unused_access_exclusion_account_names]
}
