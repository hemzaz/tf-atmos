# House test of aggregator-regions_house.tf and aggregator-regions_override.tf (E5c3b; a vendored
# target admits tests/*.tftest.hcl: scripts/check-vendor.py TESTS). Mocked providers, no AWS.
# By default fnx-ue1-security's aws-config (catalog aws-config/security): the US aggregator over
# the US regions only, never Cloud Posse's all_regions. Later runs: the EU central collector
# (fnx-ew1-security) and a shared account's EU recorder (aws-config/main-core-region-eu), each
# with exactly one authorization. A run cannot see inside module.aws_config, so
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

# fnx-ew1-security (aws-config/security-eu): the EU central collector, its own aggregator over the
# EU regions only and its one authorization, to itself in eu-west-1.
run "eu_central_collector" {
  command = plan

  override_data {
    target = data.aws_region.this[0]
    values = { name = "eu-west-1", region = "eu-west-1" }
  }

  variables {
    region                           = "eu-west-1"
    environment                      = "ew1"
    global_resource_collector_region = "eu-west-1"
    config_bucket_env                = "ew1"
    aggregator_regions               = ["eu-west-1", "eu-central-1"]
  }

  assert {
    condition     = aws_config_configuration_aggregator.regions[0].account_aggregation_source[0].regions == tolist(["eu-west-1", "eu-central-1"])
    error_message = "The EU central collector creates the aggregator over the EU regions only."
  }
  assert {
    condition = (
      length(aws_config_aggregate_authorization.regions) == 1
      && aws_config_aggregate_authorization.regions[0].region == "eu-west-1"
      && aws_config_aggregate_authorization.regions[0].account_id == "222222222222"
    )
    error_message = "One authorization, to the central account in eu-west-1."
  }
}

# fnx-ew1-root (aws-config/main-core-region-eu): a shared account's eu-west-1 recorder keeps its US
# home collector region (no IAM recording) and authorizes the EU aggregator, never the US one.
run "shared_eu_recorder_authorizes_the_eu_aggregator" {
  command = plan

  override_data {
    target = data.aws_region.this[0]
    values = { name = "eu-west-1", region = "eu-west-1" }
  }
  override_data {
    target = data.aws_caller_identity.this[0]
    values = { account_id = "111111111111" }
  }

  variables {
    region                          = "eu-west-1"
    environment                     = "ew1"
    stage                           = "root"
    config_bucket_env               = "ew1"
    create_iam_role                 = false
    iam_role_arn                    = "arn:aws:iam::111111111111:role/fnx-ue1-root-aws-config-config"
    delegated_accounts              = null
    aggregator_authorization_region = "eu-west-1"
  }

  assert {
    condition     = length(aws_config_configuration_aggregator.regions) == 0
    error_message = "A recorder that is not the central collector creates no aggregator."
  }
  assert {
    condition = (
      length(aws_config_aggregate_authorization.regions) == 1
      && aws_config_aggregate_authorization.regions[0].region == "eu-west-1"
      && aws_config_aggregate_authorization.regions[0].account_id == "222222222222"
    )
    error_message = "The authorization goes to the central account in eu-west-1, not the collector region."
  }
}

run "bad_authorization_region_is_refused" {
  command = plan

  variables {
    aggregator_authorization_region = "not a region"
  }

  expect_failures = [var.aggregator_authorization_region]
}
