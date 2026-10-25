# Mock-provider tests for DNSSEC signing (dnssec_enabled): no AWS credentials,
# no network. Run from the component directory with
# `terraform init -backend=false && terraform test`. override_during = plan
# makes the mocked ARNs, account ids and DS records known at plan.

mock_provider "aws" {
  override_during = plan

  mock_resource "aws_route53_zone" {
    defaults = { zone_id = "ZMAIN000000000000000", name_servers = ["ns-1.awsdns-01.org"] }
  }
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-east-1:111111111111:key/11111111-1111-1111-1111-111111111111" }
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

  mock_resource "aws_route53_zone" {
    defaults = { zone_id = "ZDNSACCT000000000000", name_servers = ["ns-3.awsdns-03.org"] }
  }
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-east-1:222222222222:key/22222222-2222-2222-2222-222222222222" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "222222222222" }
  }
}

variables {
  region         = "us-east-2"
  root_domain    = "fnx.example.com"
  dnssec_enabled = true
  zones = {
    main     = { name = "fnx.example.com" }
    services = { name = "services.fnx.example.com", parent_zone = "main" }
    internal = { name = "internal.fnx.example.com", vpc_associations = ["vpc-0123456789abcdef0"] }
  }
  tags = { Environment = "test" }
}

run "public_zones_are_signed_with_a_us_east_1_ecc_key" {
  command = plan

  assert {
    condition = (
      length(aws_kms_key.dnssec) == 1 && aws_kms_key.dnssec[0].region == "us-east-1"
      && aws_kms_key.dnssec[0].customer_master_key_spec == "ECC_NIST_P256" && aws_kms_key.dnssec[0].key_usage == "SIGN_VERIFY"
    )
    error_message = "One us-east-1 ECC_NIST_P256 SIGN_VERIFY key signs the instance's zones (stack region us-east-2)."
  }

  assert {
    condition     = toset(keys(aws_route53_hosted_zone_dnssec.zones)) == toset(["main", "services"]) && toset(keys(aws_route53_key_signing_key.zones)) == toset(["main", "services"])
    error_message = "Every public zone gets a KSK and SIGNING; the private internal zone does not."
  }

  assert {
    condition     = aws_route53_key_signing_key.zones["services"].name == "ksk_services_fnx_example_com" && aws_route53_key_signing_key.zones["main"].key_management_service_arn == aws_kms_key.dnssec[0].arn
    error_message = "KSK names use only [A-Za-z0-9_] and point at the signing key."
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_kms_key.dnssec[0].policy).Statement :
      s.Principal == { Service = "dnssec-route53.amazonaws.com" } && contains(s.Action, "kms:Sign")
      && s.Condition.StringEquals["aws:SourceAccount"] == "111111111111"
      && s.Condition.ArnLike["aws:SourceArn"] == "arn:aws:route53:::hostedzone/*"
      if s.Sid == "AllowRoute53DNSSECService"
      ]) && anytrue([
      for s in jsondecode(aws_kms_key.dnssec[0].policy).Statement :
      s.Action == "kms:CreateGrant" && s.Condition.Bool["kms:GrantIsForAWSResource"] == "true"
    ])
    error_message = "The key lets dnssec-route53.amazonaws.com sign for this account's hosted zones, and create grants only for AWS resources."
  }
}

run "subzone_ds_record_is_written_into_its_parent" {
  command = plan

  assert {
    condition = (
      aws_route53_record.records["delegation_ds_services"].type == "DS"
      && aws_route53_record.records["delegation_ds_services"].name == "services.fnx.example.com"
      && aws_route53_record.records["delegation_ds_services"].records == toset(["12345 13 2 ABCDEF0123456789"])
    )
    error_message = "A parent_zone subzone's DS record sits beside its NS record in the parent zone."
  }

  assert {
    condition     = output.ds_records == tomap({ main = "12345 13 2 ABCDEF0123456789", services = "12345 13 2 ABCDEF0123456789" })
    error_message = "ds_records maps each signed zone to the DS record its parent must publish."
  }
}

run "dns_account_zones_use_a_dns_account_key" {
  command = plan

  variables {
    multi_account_dns_delegation = true
    zones                        = { main = { name = "fnx.example.com" } }
  }

  assert {
    condition = (
      length(aws_kms_key.dnssec) == 0 && length(aws_kms_key.dns_account_dnssec) == 1
      && aws_route53_key_signing_key.dns_account_zones["main"].key_management_service_arn == aws_kms_key.dns_account_dnssec[0].arn
    )
    error_message = "Zones in the DNS account are signed with a key in the DNS account."
  }
}

run "root_zone_is_signed" {
  command = plan

  variables {
    create_root_zone = true
    zones            = {}
  }

  assert {
    condition     = length(aws_route53_hosted_zone_dnssec.root_zone) == 1 && aws_route53_key_signing_key.root_zone[0].name == "ksk_fnx_example_com"
    error_message = "create_root_zone with dnssec_enabled signs the root zone."
  }
}

# Step one of turning DNSSEC off: DS records go, signing stays.
run "ds_off_keeps_signing_and_drops_ds_records" {
  command = plan

  variables {
    dnssec_ds_enabled = false
    records = {
      other_ds = { zone_name = "main", name = "other.fnx.example.com", type = "DS", records = [null] }
    }
  }

  assert {
    condition = (
      toset(keys(aws_route53_hosted_zone_dnssec.zones)) == toset(["main", "services"])
      && !contains(keys(aws_route53_record.records), "delegation_ds_services")
      && contains(keys(aws_route53_record.records), "delegation_services")
      && length(output.ds_records) == 0
    )
    error_message = "dnssec_ds_enabled = false keeps SIGNING and the NS delegation but drops the DS record and empties ds_records."
  }

  assert {
    condition     = !contains(keys(aws_route53_record.records), "other_ds")
    error_message = "A DS record whose values are all null (another instance's emptied ds_records) is dropped."
  }
}

run "ds_requires_signing" {
  command = plan

  variables {
    dnssec_enabled    = false
    dnssec_ds_enabled = true
  }

  expect_failures = [var.dnssec_ds_enabled]
}

run "dnssec_off_creates_nothing" {
  command = plan

  variables {
    dnssec_enabled = false
  }

  assert {
    condition = (
      length(aws_kms_key.dnssec) == 0 && length(aws_route53_key_signing_key.zones) == 0
      && !contains(keys(aws_route53_record.records), "delegation_ds_services") && length(output.ds_records) == 0
    )
    error_message = "With dnssec_enabled off there is no key, KSK, signing or DS record."
  }
}
