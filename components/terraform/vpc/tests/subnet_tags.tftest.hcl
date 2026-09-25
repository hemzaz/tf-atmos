# Mock-provider tests for the subnet tag inputs: no AWS credentials, no
# network. Run from the component directory with
# `terraform init -backend=false && terraform test`.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]
    }
  }
}

variables {
  region                  = "eu-west-2"
  ipv4_primary_cidr_block = "10.20.0.0/16"
  availability_zones      = ["eu-west-2a", "eu-west-2b"]
  private_subnets         = ["10.20.0.0/18", "10.20.64.0/18"]
  public_subnets          = ["10.20.192.0/22", "10.20.196.0/22"]
  vpc_flow_logs_enabled   = false
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "no_extra_tags_by_default" {
  command = plan

  assert {
    condition     = aws_subnet.public["10.20.192.0/22"].tags == tomap({ Name = "test-public-subnet-1" })
    error_message = "Without additional tags a subnet carries only its Name."
  }
}

run "eks_discovery_tags_on_each_tier" {
  command = plan

  variables {
    public_subnets_additional_tags = {
      "kubernetes.io/role/elb"                   = "1"
      "kubernetes.io/cluster/test-microservices" = "shared"
    }
    private_subnets_additional_tags = {
      "kubernetes.io/role/internal-elb" = "1"
    }
  }

  assert {
    condition     = alltrue([for s in aws_subnet.public : s.tags["kubernetes.io/role/elb"] == "1" && s.tags["kubernetes.io/cluster/test-microservices"] == "shared"])
    error_message = "Every public subnet gets public_subnets_additional_tags."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.private : s.tags["kubernetes.io/role/internal-elb"] == "1" && !contains(keys(s.tags), "kubernetes.io/role/elb")])
    error_message = "Private subnets get only private_subnets_additional_tags."
  }

  assert {
    condition     = aws_subnet.private["10.20.64.0/18"].tags["Name"] == "test-private-subnet-2"
    error_message = "The component still names each subnet."
  }
}

run "rejects_a_name_tag" {
  command = plan

  variables {
    public_subnets_additional_tags = { Name = "mine" }
  }

  expect_failures = [var.public_subnets_additional_tags]
}
