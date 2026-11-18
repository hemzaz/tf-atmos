# House test of account-analyzer_house.tf (E5c7b, owner 2026-11-18): the ACCOUNT external-access analyzer
# exists only when accessanalyzer_account_enabled is set. Mocked provider, no AWS.
mock_provider "aws" {}

# A member account's US stack (catalog access-analyzer/account-defaults): both organization analyzers
# and the delegation off.
variables {
  region                                            = "us-east-1"
  enabled                                           = true
  tenant                                            = "fnx"
  environment                                       = "ue1"
  stage                                             = "dev"
  name                                              = "access-analyzer"
  account_map_enabled                               = false
  delegated_administrator_account_name              = "fnx-security"
  organizations_delegated_administrator_enabled     = false
  accessanalyzer_organization_enabled               = false
  accessanalyzer_organization_unused_access_enabled = false
  account_map = {
    full_account_map = {
      "fnx-root"     = "111111111111"
      "fnx-security" = "222222222222"
      "fnx-dev"      = "777777777777"
    }
    root_account_account_name = "fnx-root"
  }
}

run "flag_off_creates_no_account_analyzer" {
  command = plan
  override_data {
    target = data.aws_caller_identity.this[0]
    values = { account_id = "777777777777" }
  }
  assert {
    condition     = length(aws_accessanalyzer_analyzer.account) == 0
    error_message = "no ACCOUNT analyzer unless accessanalyzer_account_enabled (Cloud Posse's behaviour)"
  }
}

run "flag_on_creates_one_account_analyzer" {
  command = plan
  variables {
    accessanalyzer_account_enabled = true
  }
  override_data {
    target = data.aws_caller_identity.this[0]
    values = { account_id = "777777777777" }
  }
  assert {
    condition     = length(aws_accessanalyzer_analyzer.account) == 1
    error_message = "exactly one ACCOUNT analyzer"
  }
  assert {
    condition     = aws_accessanalyzer_analyzer.account[0].type == "ACCOUNT"
    error_message = "the analyzer's type is ACCOUNT"
  }
  assert {
    condition     = aws_accessanalyzer_analyzer.account[0].analyzer_name == "ue1-dev-access-analyzer-account"
    error_message = "the analyzer is named <id>-account (this null-label context: ue1-dev-access-analyzer)"
  }
  assert {
    condition     = length(aws_accessanalyzer_analyzer.organization) == 0 && length(aws_accessanalyzer_analyzer.organization_unused_access) == 0 && length(aws_organizations_delegated_administrator.default) == 0
    error_message = "an account analyzer instance creates no organization analyzer and no delegation"
  }
}

run "disabled_component_creates_nothing" {
  command = plan
  variables {
    enabled                        = false
    accessanalyzer_account_enabled = true
  }
  assert {
    condition     = length(aws_accessanalyzer_analyzer.account) == 0
    error_message = "enabled false creates nothing"
  }
}
