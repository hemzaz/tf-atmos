# Mock-provider tests for zones.<key>.parent_zone (subzone delegation within
# one instance): no AWS credentials, no network. Run from the component
# directory with `terraform init -backend=false && terraform test`.
#
# override_during = plan makes the mocked zone ids and name servers known at
# plan, so the NS record's values can be asserted. Each zone gets its own zone
# id and name servers (override_resource below), so a delegation written into
# the wrong zone, or listing the wrong zone's name servers, fails.

mock_provider "aws" {
  override_during = plan

  mock_resource "aws_route53_zone" {
    defaults = {
      zone_id      = "ZDEFAULT0000000000000"
      name_servers = ["ns-0.awsdns-00.org", "ns-0.awsdns-00.co.uk"]
    }
  }
}

override_resource {
  target          = aws_route53_zone.zones["services"]
  override_during = plan
  values = {
    zone_id      = "ZSERVICES000000000000"
    name_servers = ["ns-11.awsdns-11.org", "ns-12.awsdns-12.co.uk"]
  }
}

override_resource {
  target          = aws_route53_zone.zones["data"]
  override_during = plan
  values = {
    zone_id      = "ZDATA0000000000000000"
    name_servers = ["ns-21.awsdns-21.org", "ns-22.awsdns-22.co.uk"]
  }
}

override_resource {
  target          = aws_route53_zone.zones["api"]
  override_during = plan
  values = {
    zone_id      = "ZAPI00000000000000000"
    name_servers = ["ns-31.awsdns-31.org", "ns-32.awsdns-32.co.uk"]
  }
}

mock_provider "aws" {
  alias           = "dns_account"
  override_during = plan
}

variables {
  region      = "us-east-1"
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
      && aws_route53_record.records["delegation_data"].zone_id == "ZSERVICES000000000000"
      && toset(aws_route53_record.records["delegation_data"].records) == toset(["ns-21.awsdns-21.org", "ns-22.awsdns-22.co.uk"])
      && aws_route53_record.records["delegation_data"].ttl == 30
    )
    error_message = "delegation_data is an NS record for the data zone's name, in the services zone, listing the data zone's name servers, with the default delegation_ttl (30)."
  }
}

run "each_delegation_carries_its_own_child_zone" {
  command = plan

  variables {
    delegation_ttl = 172800
    zones = {
      services = { name = "services.fnx.example.com" }
      data     = { name = "data.services.fnx.example.com", parent_zone = "services" }
      api      = { name = "api.data.services.fnx.example.com", parent_zone = "data" }
    }
  }

  assert {
    condition     = toset(keys(aws_route53_record.records)) == toset(["delegation_data", "delegation_api"])
    error_message = "One NS record per zone with a parent_zone."
  }

  assert {
    condition = (
      aws_route53_record.records["delegation_data"].zone_id == "ZSERVICES000000000000"
      && toset(aws_route53_record.records["delegation_data"].records) == toset(["ns-21.awsdns-21.org", "ns-22.awsdns-22.co.uk"])
    )
    error_message = "delegation_data lives in the services zone and lists the data zone's name servers."
  }

  assert {
    condition = (
      aws_route53_record.records["delegation_api"].name == "api.data.services.fnx.example.com"
      && aws_route53_record.records["delegation_api"].zone_id == "ZDATA0000000000000000"
      && toset(aws_route53_record.records["delegation_api"].records) == toset(["ns-31.awsdns-31.org", "ns-32.awsdns-32.co.uk"])
    )
    error_message = "delegation_api lives in the data zone (not services) and lists the api zone's name servers (not data's)."
  }

  assert {
    condition     = alltrue([for r in values(aws_route53_record.records) : r.ttl == 172800])
    error_message = "Every delegation NS record uses delegation_ttl."
  }
}

run "delegation_ttl_must_be_whole_seconds" {
  command = plan

  variables {
    delegation_ttl = -1
    zones = {
      services = { name = "services.fnx.example.com" }
    }
  }

  expect_failures = [var.delegation_ttl]
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

# nullable = false: an explicit null (e.g. an unset Atmos var) takes the default
# instead of reaching the validation as a null comparison.
run "null_delegation_ttl_takes_the_default" {
  command = plan

  variables {
    delegation_ttl = null
    zones = {
      services = { name = "services.fnx.example.com" }
      data     = { name = "data.services.fnx.example.com", parent_zone = "services" }
    }
  }

  assert {
    condition     = aws_route53_record.records["delegation_data"].ttl == 30
    error_message = "A null delegation_ttl must fall back to the default 30."
  }
}
