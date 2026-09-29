# Mock-provider tests for zones.<key>.parent_zone (subzone delegation within
# one instance): no AWS credentials, no network. Run from the component
# directory with `terraform init -backend=false && terraform test`.
#
# override_during = plan makes the mocked zone ids and name servers known at
# plan, so the NS record's values can be asserted.

mock_provider "aws" {
  override_during = plan

  mock_resource "aws_route53_zone" {
    defaults = {
      zone_id      = "Z1234567890ABCDEFGHIJ"
      name_servers = ["ns-1.awsdns-01.org", "ns-2.awsdns-02.co.uk"]
    }
  }
}

mock_provider "aws" {
  alias           = "dns_account"
  override_during = plan
}

variables {
  region      = "eu-west-2"
  root_domain = "fnx.example.com"
  tags = {
    Environment = "test"
  }
}

run "parent_zone_writes_the_ns_record" {
  command = plan

  variables {
    zones = {
      services = { name = "services.fnx.example.com" }
      data     = { name = "data.services.fnx.example.com", parent_zone = "services" }
    }
    records = {
      api = { zone_name = "services", name = "api.services.fnx.example.com", type = "CNAME", records = ["x.example.com"] }
    }
  }

  assert {
    condition     = toset(keys(aws_route53_record.records)) == toset(["api", "delegation_data"])
    error_message = "The data zone's delegation is one extra record, delegation_data."
  }

  assert {
    condition = (
      aws_route53_record.records["delegation_data"].type == "NS"
      && aws_route53_record.records["delegation_data"].name == "data.services.fnx.example.com"
      && aws_route53_record.records["delegation_data"].zone_id == aws_route53_zone.zones["services"].zone_id
      && toset(aws_route53_record.records["delegation_data"].records) == toset(aws_route53_zone.zones["data"].name_servers)
    )
    error_message = "delegation_data is an NS record for the data zone's name, in the services zone, listing the data zone's name servers."
  }
}

run "no_parent_zone_no_delegation" {
  command = plan

  variables {
    zones = {
      services = { name = "services.fnx.example.com" }
    }
  }

  assert {
    condition     = length(aws_route53_record.records) == 0
    error_message = "Without parent_zone no NS record is written."
  }
}

run "parent_zone_must_exist" {
  command = plan

  variables {
    zones = {
      data = { name = "data.services.fnx.example.com", parent_zone = "services" }
    }
  }

  expect_failures = [var.zones]
}

run "parent_zone_must_be_above_the_zone" {
  command = plan

  variables {
    zones = {
      services = { name = "services.fnx.example.com" }
      other    = { name = "other.example.org", parent_zone = "services" }
    }
  }

  expect_failures = [var.zones]
}

run "private_zones_cannot_delegate" {
  command = plan

  variables {
    zones = {
      services = { name = "services.fnx.example.com", vpc_associations = ["vpc-0123456789abcdef0"] }
      data     = { name = "data.services.fnx.example.com", parent_zone = "services" }
    }
  }

  expect_failures = [var.zones]
}
