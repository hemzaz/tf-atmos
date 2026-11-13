# House test of aggregator-regions_house.tf and aggregator-regions_override.tf (E5c3b; a vendored
# target admits tests/*.tftest.hcl: scripts/check-vendor.py TESTS). Mocked providers, no AWS.
# fnx-ue1-security's aws-config (catalog aws-config/security): the US aggregator over the US
# regions only, never Cloud Posse's all_regions. A run cannot see inside module.aws_config, so
# the override's disabled_aggregation_regions (the module's own aggregator off) is not asserted.
mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { name = "us-east-1", region = "us-east-1" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "222222222222" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
}

mock_provider "awsutils" {}

variables {
  region                             = "us-east-1"
  enabled                            = true
  tenant                             = "fnx"
  environment                        = "ue1"
  stage                              = "security"
  name                               = "aws-config"
  account_map_enabled                = false
  account_verification_enabled       = false
  global_resource_collector_region   = "us-east-1"
  central_resource_collector_account = "fnx-security"
  config_bucket_env                  = "ue1"
  config_bucket_stage                = "audit"
  create_iam_role                    = true
  delegated_accounts                 = ["111111111111", "222222222222"]
  account_map = {
    full_account_map = {
      "fnx-root"     = "111111111111"
      "fnx-security" = "222222222222"
    }
    root_account_account_name     = "fnx-root"
    identity_account_account_name = "fnx-root"
    audit_account_account_name    = "fnx-root"
  }
}

run "named_regions_replace_all_regions" {
  command = plan

  variables {
    aggregator_regions = ["us-east-1", "us-east-2", "us-west-2"]
  }

  assert {
    condition     = length(aws_config_configuration_aggregator.regions) == 1
    error_message = "The central account's collector region must create the house aggregator."
  }
  assert {
    condition = (
      aws_config_configuration_aggregator.regions[0].account_aggregation_source[0].regions == tolist(["us-east-1", "us-east-2", "us-west-2"])
      && aws_config_configuration_aggregator.regions[0].account_aggregation_source[0].all_regions != true
    )
    error_message = "The aggregator must name exactly aggregator_regions, never all_regions."
  }
  assert {
    condition     = aws_config_configuration_aggregator.regions[0].name == "${module.aws_config_label.id}-aggregator"
    error_message = "The aggregator keeps Cloud Posse's name (label attributes config, aggregator)."
  }
  assert {
    condition = (
      length(aws_config_aggregate_authorization.regions) == 1
      && aws_config_aggregate_authorization.regions[0].account_id == "222222222222"
      && aws_config_aggregate_authorization.regions[0].region == "us-east-1"
    )
    error_message = "The region's authorization to the central account replaces Cloud Posse's child authorization."
  }
}

run "unset_keeps_cloud_posse" {
  command = plan

  assert {
    condition     = length(aws_config_configuration_aggregator.regions) == 0 && length(aws_config_aggregate_authorization.regions) == 0
    error_message = "Without aggregator_regions the house file creates nothing."
  }
}

run "empty_list_is_refused" {
  command = plan

  variables {
    aggregator_regions = []
  }

  expect_failures = [var.aggregator_regions]
}
