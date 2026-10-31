# Mock-provider tests for external_zones: zones another component creates
# (e.g. a vendored aws-dns-delegated zone) that this instance signs, query-logs
# or writes records into. No AWS credentials, no network. dnssec.tftest.hcl and
# query_logging.tftest.hcl keep covering the zones the instance creates.

mock_provider "aws" {
  override_during = plan

  mock_resource "aws_route53_zone" {
    defaults = { zone_id = "ZMAIN000000000000000", arn = "arn:aws:route53:::hostedzone/ZMAIN000000000000000", name_servers = ["ns-1.awsdns-01.org"] }
  }
  mock_data "aws_route53_zone" {
    defaults = { name = "dev.fnx-svc.example.net", arn = "arn:aws:route53:::hostedzone/ZDELEGATED0000000000", name_servers = ["ns-2.awsdns-02.org"] }
  }
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-east-1:111111111111:key/11111111-1111-1111-1111-111111111111", key_id = "11111111-1111-1111-1111-111111111111" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:us-east-1:111111111111:log-group:/aws/route53/dev.fnx-svc.example.net/queries" }
  }
  mock_resource "aws_route53_key_signing_key" {
    defaults = { ds_record = "12345 13 2 ABCDEF0123456789" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
}

mock_provider "aws" {
  alias           = "dns_account"
  override_during = plan

  mock_data "aws_route53_zone" {
    defaults = { zone_id = "ZPRIMARY000000000000", arn = "arn:aws:route53:::hostedzone/ZPRIMARY000000000000", name_servers = ["ns-3.awsdns-03.org"] }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "222222222222" }
  }
}

variables {
  region                      = "us-east-2"
  root_domain                 = "dev.fnx-svc.example.net"
  dnssec_enabled              = true
  dns_account_assume_role_arn = "arn:aws:iam::222222222222:role/dns"
  zones = {
    internal = { name = "internal.dev.fnx-svc.example.net", vpc_associations = ["vpc-0123456789abcdef0"] }
  }
  external_zones = {
    delegated = { zone_id = "ZDELEGATED0000000000", dnssec_enabled = true, enable_query_logging = true, parent_zone = "primary" }
    primary   = { name = "fnx-svc.example.net", dns_account = true }
  }
  records = {
    www = { zone_name = "delegated", name = "www.dev.fnx-svc.example.net", type = "CNAME", records = ["app.example.org"] }
  }
  tags = { Environment = "test" }
}

run "external_zone_is_signed_with_the_instance_key" {
  command = plan

  assert {
    condition = (
      toset(keys(aws_route53_key_signing_key.zones)) == toset(["delegated"])
      && aws_route53_key_signing_key.zones["delegated"].hosted_zone_id == "ZDELEGATED0000000000"
      && aws_route53_key_signing_key.zones["delegated"].name == "ksk_dev_fnx_svc_example_net"
      && aws_route53_key_signing_key.zones["delegated"].key_management_service_arn == aws_kms_key.dnssec[0].arn
      && aws_route53_hosted_zone_dnssec.zones["delegated"].hosted_zone_id == "ZDELEGATED0000000000"
    )
    error_message = "An external zone with dnssec_enabled gets a KSK (named from the looked-up zone name) and SIGNING on its own zone id, with the instance's key."
  }

  assert {
    condition     = length(aws_route53_zone.zones) == 1 && contains(keys(aws_route53_zone.zones), "internal")
    error_message = "External zones are looked up, never created."
  }

  assert {
    condition     = output.ds_records == tomap({ delegated = "12345 13 2 ABCDEF0123456789" })
    error_message = "ds_records publishes the external zone's DS for its parent; the unsigned primary has none."
  }
}

run "outputs_include_external_zones" {
  command = plan

  assert {
    condition = (
      output.zone_ids["delegated"] == "ZDELEGATED0000000000"
      && output.zone_ids["primary"] == "ZPRIMARY000000000000"
      && output.zone_ids["internal"] == "ZMAIN000000000000000"
      && tolist(output.zone_name_servers["delegated"]) == tolist(["ns-2.awsdns-02.org"])
    )
    error_message = "zone_ids and zone_name_servers map external_zones keys too, so zone_ids.<key> readers survive a move from zones to external_zones."
  }
}

run "external_zone_is_query_logged" {
  command = plan

  assert {
    condition = (
      aws_route53_query_log.query_logging["delegated"].zone_id == "ZDELEGATED0000000000"
      && aws_cloudwatch_log_group.dns_query_logs["delegated"].name == "/aws/route53/dev.fnx-svc.example.net/queries"
      && aws_cloudwatch_log_group.dns_query_logs["delegated"].retention_in_days == 7
      && length(aws_kms_key.query_logs) == 1 && length(aws_route53_query_log.dns_account_query_logging) == 0
    )
    error_message = "enable_query_logging gives an external zone a us-east-1 log group, this component's key and a query log on its zone id."
  }

  assert {
    condition = (
      jsondecode(aws_cloudwatch_log_resource_policy.route53_query_logging[0].policy_document).Statement[0].Condition.ArnLike["aws:SourceArn"]
      == ["arn:aws:route53:::hostedzone/ZDELEGATED0000000000"]
    )
    error_message = "The resource policy names the external zone's ARN from the lookup."
  }
}

run "records_target_external_zones_in_either_account" {
  command = plan

  assert {
    condition = (
      aws_route53_record.dns_account_records["delegation_ds_delegated"].zone_id == "ZPRIMARY000000000000"
      && aws_route53_record.dns_account_records["delegation_ds_delegated"].name == "dev.fnx-svc.example.net"
      && aws_route53_record.dns_account_records["delegation_ds_delegated"].records == toset(["12345 13 2 ABCDEF0123456789"])
      && aws_route53_record.records["www"].zone_id == "ZDELEGATED0000000000"
    )
    error_message = "parent_zone writes the signed zone's DS into its dns_account parent through aws.dns_account; a record in a local external zone uses the default provider."
  }

  assert {
    condition     = data.aws_route53_zone.dns_account_external_zones["primary"].name == "fnx-svc.example.net" && data.aws_route53_zone.dns_account_external_zones["primary"].private_zone == false
    error_message = "A name-only entry looks the public zone up by name."
  }
}

run "unsigned_external_zone_needs_no_key" {
  command = plan

  variables {
    external_zones = { primary = { name = "fnx-svc.example.net", dns_account = true } }
    records        = {}
  }

  assert {
    condition     = length(aws_kms_key.dnssec) == 0 && length(aws_kms_key.dns_account_dnssec) == 0 && length(aws_route53_key_signing_key.dns_account_zones) == 0 && length(aws_kms_key.query_logs) == 0
    error_message = "An external zone without dnssec_enabled or enable_query_logging is only a record target: no key, KSK or log group."
  }
}

run "zone_id_and_name_are_exclusive" {
  command = plan

  variables {
    external_zones = { bad = { zone_id = "ZDELEGATED0000000000", name = "dev.fnx-svc.example.net" } }
  }

  expect_failures = [var.external_zones]
}

run "keys_must_not_collide_with_zones" {
  command = plan

  variables {
    external_zones = { internal = { zone_id = "ZDELEGATED0000000000" } }
  }

  expect_failures = [var.external_zones]
}

run "signing_needs_instance_dnssec" {
  command = plan

  variables {
    dnssec_enabled = false
    external_zones = { delegated = { zone_id = "ZDELEGATED0000000000", dnssec_enabled = true } }
  }

  expect_failures = [var.external_zones]
}

run "ds_off_drops_the_parent_ds" {
  command = plan

  variables {
    dnssec_ds_enabled = false
  }

  assert {
    condition     = !contains(keys(aws_route53_record.dns_account_records), "delegation_ds_delegated") && length(aws_route53_hosted_zone_dnssec.zones) == 1
    error_message = "dnssec_ds_enabled = false keeps SIGNING but drops the parent DS record."
  }
}

run "parent_zone_needs_a_signed_entry_and_a_known_key" {
  command = plan

  variables {
    external_zones = { delegated = { zone_id = "ZDELEGATED0000000000", parent_zone = "nope" } }
  }

  expect_failures = [var.external_zones]
}

run "parent_zone_must_not_be_a_private_zone" {
  command = plan

  variables {
    external_zones = { delegated = { zone_id = "ZDELEGATED0000000000", dnssec_enabled = true, parent_zone = "internal" } }
  }

  expect_failures = [var.external_zones]
}

run "dns_account_needs_its_role" {
  command = plan

  variables {
    dns_account_assume_role_arn = null
  }

  expect_failures = [var.external_zones]
}

run "private_zone_is_rejected" {
  command = plan

  override_data {
    target = data.aws_route53_zone.external_zones["delegated"]
    values = { name = "dev.fnx-svc.example.net", name_servers = [] }
  }

  expect_failures = [data.aws_route53_zone.external_zones["delegated"]]
}
