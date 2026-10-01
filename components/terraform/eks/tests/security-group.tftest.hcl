# Cluster API ingress (security-group.tf): allowed_security_group_ids and
# allowed_cidr_blocks, with mock providers (no AWS credentials). Run from the
# component directory with `terraform init -backend=false && terraform test`.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_resource "aws_eks_cluster" {
    defaults = {
      arn      = "arn:aws:eks:us-east-1:123456789012:cluster/mock"
      endpoint = "https://ABCDEF0123456789.gr7.us-east-1.eks.amazonaws.com"
      certificate_authority = [{
        data = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUMvakNDQWVhZ0F3SUJBZ0lCQURBTkJna3Foa2lHOXcwQkFRc0ZBREFWTVJNd0VRWURWUVFERXdwcmRXSmwKLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLQo="
      }]
      identity = [{
        oidc = [{
          issuer = "https://oidc.eks.us-east-1.amazonaws.com/id/ABCDEF0123456789ABCDEF0123456789"
        }]
      }]
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock"
    }
  }

  mock_resource "aws_launch_template" {
    defaults = {
      id = "lt-0123456789abcdef0"
    }
  }

  mock_resource "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/ABCDEF0123456789ABCDEF0123456789"
    }
  }
}

mock_provider "tls" {
  mock_data "tls_certificate" {
    defaults = {
      certificates = [{
        sha1_fingerprint = "9e99a48a9960b14926bb7f3b02e22da2b0ab7280"
      }]
    }
  }
}

mock_provider "random" {}

variables {
  region     = "us-east-1"
  name       = "main"
  subnet_ids = ["subnet-0a1b2c3d", "subnet-4e5f6a7b"]
  tags = {
    Environment = "dev"
  }
  node_groups = {
    workers = {
      instance_types = ["t3.medium"]
    }
  }
}

run "no_allowed_callers_opens_nothing" {
  command = plan

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.managed_ingress_security_groups) == 0 && length(aws_vpc_security_group_ingress_rule.managed_ingress_cidr_blocks) == 0
    error_message = "The defaults (empty lists) must add no ingress to the cluster security group."
  }
}

run "bastion_security_group_gets_443_on_the_cluster_security_group" {
  command = apply

  variables {
    allowed_security_group_ids = ["sg-0123456789abcdef0"]
    allowed_cidr_blocks        = ["10.0.0.0/16", "10.1.0.0/16"]
  }

  assert {
    condition = (
      length(aws_vpc_security_group_ingress_rule.managed_ingress_security_groups) == 1 &&
      aws_vpc_security_group_ingress_rule.managed_ingress_security_groups[0].referenced_security_group_id == "sg-0123456789abcdef0"
    )
    error_message = "Each allowed security group must get one ingress rule referencing it."
  }

  assert {
    condition = alltrue([
      for r in concat(
        aws_vpc_security_group_ingress_rule.managed_ingress_security_groups,
        aws_vpc_security_group_ingress_rule.managed_ingress_cidr_blocks,
      ) : r.security_group_id == aws_eks_cluster.default[0].vpc_config[0].cluster_security_group_id
    ])
    error_message = "The rules must be on the EKS-managed cluster security group, as in Cloud Posse."
  }

  assert {
    condition = alltrue([
      for r in concat(
        aws_vpc_security_group_ingress_rule.managed_ingress_security_groups,
        aws_vpc_security_group_ingress_rule.managed_ingress_cidr_blocks,
      ) : r.ip_protocol == "tcp" && r.from_port == 443 && r.to_port == 443
    ])
    error_message = "The rules must open TCP 443 only."
  }

  assert {
    condition     = [for r in aws_vpc_security_group_ingress_rule.managed_ingress_cidr_blocks : r.cidr_ipv4] == ["10.0.0.0/16", "10.1.0.0/16"]
    error_message = "Each allowed CIDR must get one ingress rule."
  }
}

run "disabled_opens_nothing" {
  command = plan

  variables {
    enabled                    = false
    allowed_security_group_ids = ["sg-0123456789abcdef0"]
    allowed_cidr_blocks        = ["10.0.0.0/16"]
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.managed_ingress_security_groups) == 0 && length(aws_vpc_security_group_ingress_rule.managed_ingress_cidr_blocks) == 0
    error_message = "enabled = false must create no ingress rules."
  }
}

run "malformed_security_group_id_is_rejected" {
  command = plan

  variables {
    allowed_security_group_ids = ["bastion"]
  }

  expect_failures = [var.allowed_security_group_ids]
}

run "world_cidr_is_rejected" {
  command = plan

  variables {
    allowed_cidr_blocks = ["10.0.0.0/16", "0.0.0.0/0"]
  }

  expect_failures = [var.allowed_cidr_blocks]
}

run "world_cidr_zero_padded_is_rejected" {
  command = plan

  variables {
    allowed_cidr_blocks = ["0.0.0.0/00"]
  }

  expect_failures = [var.allowed_cidr_blocks]
}

run "ipv6_cidr_is_rejected" {
  command = plan

  variables {
    allowed_cidr_blocks = ["2001:db8::/32"]
  }

  expect_failures = [var.allowed_cidr_blocks]
}

run "malformed_cidr_is_rejected" {
  command = plan

  variables {
    allowed_cidr_blocks = ["10.0.0.0"]
  }

  expect_failures = [var.allowed_cidr_blocks]
}
