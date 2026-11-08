# House test of account-verification_override.tf (E5b5; a vendored target
# admits tests/*.tftest.hcl: scripts/check-vendor.py TESTS). Mocked aws
# provider, no AWS. Distinct synthetic IDs per account (the repo's
# placeholders are all 123456789012, which would hide a wrong expectation).
mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
}

variables {
  region      = "eu-west-1"
  enabled     = false
  tenant      = "fnx"
  environment = "ew1"
  stage       = "prod"
  name        = "cloudtrail"

  cloudtrail_bucket_environment_name = "ew1"
  cloudtrail_bucket_stage_name       = "audit"
  account_map_enabled                = false
  account_map = {
    full_account_map = {
      "fnx-prod"    = "111111111111"
      "fnx-prod-eu" = "222222222222"
      "fnx-dev"     = "333333333333"
      "fnx-audit"   = "444444444444"
    }
    audit_account_account_name = "fnx-audit"
  }
}

# fnx-ew1-prod as resolved: descriptor "%v-prod-eu" over [tenant], run in prod-eu.
run "ew1_prod_in_prod_eu_passes" {
  command = plan
  variables {
    descriptor_formats = { account_name = { format = "%v-prod-eu", labels = ["tenant"] } }
  }
  override_data {
    target = data.aws_caller_identity.account_verification
    values = { account_id = "222222222222" }
  }
  assert {
    condition     = length(terraform_data.account_verification) == 1
    error_message = "verification must run for fnx-ew1-prod"
  }
}

# Fail-closed: fnx-ew1-prod's credentials pointing at the US prod account.
run "ew1_prod_in_prod_fails" {
  command = plan
  variables {
    descriptor_formats = { account_name = { format = "%v-prod-eu", labels = ["tenant"] } }
  }
  override_data {
    target = data.aws_caller_identity.account_verification
    values = { account_id = "111111111111" }
  }
  expect_failures = [terraform_data.account_verification]
}

# fnx-ue1-prod (no descriptor): upstream's "<tenant>-<stage>" = fnx-prod.
run "ue1_prod_in_prod_passes" {
  command = plan
  variables {
    region      = "us-east-1"
    environment = "ue1"
  }
  override_data {
    target = data.aws_caller_identity.account_verification
    values = { account_id = "111111111111" }
  }
  assert {
    condition     = length(terraform_data.account_verification) == 1
    error_message = "verification must run for fnx-ue1-prod"
  }
}

run "ue1_prod_in_prod_eu_fails" {
  command = plan
  variables {
    region      = "us-east-1"
    environment = "ue1"
  }
  override_data {
    target = data.aws_caller_identity.account_verification
    values = { account_id = "222222222222" }
  }
  expect_failures = [terraform_data.account_verification]
}

# Fail-closed: a descriptor naming an account the map lacks fails, never skips.
run "unknown_account_name_fails" {
  command = plan
  variables {
    descriptor_formats = { account_name = { format = "%v-prod-xx", labels = ["tenant"] } }
  }
  override_data {
    target = data.aws_caller_identity.account_verification
    values = { account_id = "222222222222" }
  }
  expect_failures = [terraform_data.account_verification]
}

# Fail-closed: with the descriptor, a map without that account fails too (the
# component's audit lookup needs the audit entry, so no truly empty map).
run "descriptor_account_missing_from_map_fails" {
  command = plan
  variables {
    descriptor_formats = { account_name = { format = "%v-prod-eu", labels = ["tenant"] } }
    account_map        = { full_account_map = { "fnx-audit" = "444444444444" }, audit_account_account_name = "fnx-audit" }
  }
  override_data {
    target = data.aws_caller_identity.account_verification
    values = { account_id = "222222222222" }
  }
  expect_failures = [terraform_data.account_verification]
}

# Unchanged upstream behaviour without the descriptor: "<tenant>-<stage>"
# missing from the map skips verification, as upstream does.
run "no_descriptor_name_missing_skips" {
  command = plan
  variables {
    account_map = { full_account_map = { "fnx-audit" = "444444444444" }, audit_account_account_name = "fnx-audit" }
  }
  override_data {
    target = data.aws_caller_identity.account_verification
    values = { account_id = "222222222222" }
  }
  assert {
    condition     = length(terraform_data.account_verification) == 0
    error_message = "upstream skips verification when <tenant>-<stage> is not in the map"
  }
}

# Fail-closed: a descriptor that renders an empty account ("fnx-").
run "descriptor_empty_account_fails" {
  command = plan
  variables {
    descriptor_formats = { account_name = { format = "%v-", labels = ["tenant"] } }
  }
  override_data {
    target = data.aws_caller_identity.account_verification
    values = { account_id = "222222222222" }
  }
  expect_failures = [terraform_data.account_verification]
}

# Fail-closed: an unrendered template value ("fnx-<no value>").
run "descriptor_no_value_template_fails" {
  command = plan
  variables {
    descriptor_formats = { account_name = { format = "%v-<no value>", labels = ["tenant"] } }
  }
  override_data {
    target = data.aws_caller_identity.account_verification
    values = { account_id = "222222222222" }
  }
  expect_failures = [terraform_data.account_verification]
}

# The same with the component enabled: prod-eu's descriptor in the US
# prod account fails.
run "descriptor_with_enabled_true_same" {
  command = plan
  variables {
    enabled            = true
    descriptor_formats = { account_name = { format = "%v-prod-eu", labels = ["tenant"] } }
  }
  override_data {
    target = data.aws_caller_identity.account_verification
    values = { account_id = "111111111111" }
  }
  expect_failures = [terraform_data.account_verification]
}

# Without the descriptor, fnx-ue1-dev's credentials in prod-eu fail
# (upstream's "<tenant>-<stage>" = fnx-dev).
run "no_descriptor_dev_in_prod_eu_fails" {
  command = plan
  variables {
    region      = "us-east-1"
    environment = "ue1"
    stage       = "dev"
  }
  override_data {
    target = data.aws_caller_identity.account_verification
    values = { account_id = "222222222222" }
  }
  expect_failures = [terraform_data.account_verification]
}
