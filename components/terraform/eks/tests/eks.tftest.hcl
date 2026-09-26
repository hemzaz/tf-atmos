# Mock-provider tests: no AWS credentials, no network. Run from the component
# directory with `terraform init -backend=false && terraform test`.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  # What EKS returns: the CA base64-encoded, the issuer as an https:// URL.
  mock_resource "aws_eks_cluster" {
    defaults = {
      arn      = "arn:aws:eks:eu-west-2:123456789012:cluster/mock"
      endpoint = "https://ABCDEF0123456789.gr7.eu-west-2.eks.amazonaws.com"
      certificate_authority = [{
        data = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUMvakNDQWVhZ0F3SUJBZ0lCQURBTkJna3Foa2lHOXcwQkFRc0ZBREFWTVJNd0VRWURWUVFERXdwcmRXSmwKLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLQo="
      }]
      identity = [{
        oidc = [{
          issuer = "https://oidc.eks.eu-west-2.amazonaws.com/id/ABCDEF0123456789ABCDEF0123456789"
        }]
      }]
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:eu-west-2:123456789012:key/00000000-0000-0000-0000-000000000000"
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
      arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.eu-west-2.amazonaws.com/id/ABCDEF0123456789ABCDEF0123456789"
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
  region     = "eu-west-2"
  name       = "main"
  subnet_ids = ["subnet-0a1b2c3d", "subnet-4e5f6a7b"]
  tags = {
    Environment = "production"
    Tenant      = "fnx"
  }
  node_groups = {
    workers = {
      instance_types = ["m5.xlarge"]
    }
    memory-optimized = {
      instance_types = ["r5.xlarge"]
    }
  }
}

run "prod_names_do_not_repeat_the_environment" {
  command = apply

  assert {
    condition     = aws_eks_cluster.default[0].name == "production-main"
    error_message = "The prod cluster must be named production-main."
  }

  assert {
    condition     = aws_iam_role.default[0].name == "production-main-cluster-role" && aws_iam_role.node[0].name == "production-main-node-role"
    error_message = "IAM role names must be <Environment>-<name>-{cluster,node}-role."
  }

  assert {
    condition     = aws_cloudwatch_log_group.default[0].name == "/aws/eks/production-main/cluster"
    error_message = "The log group must be /aws/eks/<cluster>/cluster, as EKS writes it."
  }

  assert {
    condition     = aws_launch_template.default["workers"].name_prefix == "production-main-workers-"
    error_message = "The node group name base must be <cluster>-<node group>."
  }

  assert {
    condition = alltrue([
      for n in concat(
        [aws_eks_cluster.default[0].name, aws_iam_role.default[0].name, aws_iam_role.node[0].name],
        [for lt in aws_launch_template.default : lt.name_prefix],
        [for ng in aws_eks_node_group.default : ng.node_group_name],
      ) : length(regexall("production-production", n)) == 0
    ])
    error_message = "No name may contain the Environment twice."
  }

  assert {
    condition     = alltrue([for r in [aws_iam_role.default[0].name, aws_iam_role.node[0].name] : length(r) <= 64])
    error_message = "IAM role names must fit 64 characters."
  }

  assert {
    condition     = alltrue([for ng in aws_eks_node_group.default : length(ng.node_group_name) <= 63])
    error_message = "Node group names must fit EKS's 63 characters."
  }

  assert {
    condition     = aws_eks_cluster.default[0].deletion_protection == true
    error_message = "A production cluster must have deletion protection."
  }

  assert {
    condition     = aws_cloudwatch_log_group.default[0].retention_in_days == 7
    error_message = "Log retention defaults to 7 days."
  }
}

run "scalar_outputs_have_the_consumer_formats" {
  command = apply

  # The CA and issuer values come from the mocks above, shaped as EKS returns
  # them. These asserts guard what the outputs do to those values (no decoding,
  # no stripping, the right attribute), not EKS's own behaviour.

  # external-secrets base64-decodes the CA.
  assert {
    condition     = can(base64decode(output.eks_cluster_certificate_authority_data))
    error_message = "eks_cluster_certificate_authority_data must be base64."
  }

  assert {
    condition     = startswith(base64decode(output.eks_cluster_certificate_authority_data), "-----BEGIN CERTIFICATE-----")
    error_message = "eks_cluster_certificate_authority_data must decode to a PEM certificate."
  }

  # eks-addons requires ^https://; external-secrets strips it.
  assert {
    condition     = startswith(output.eks_cluster_identity_oidc_issuer, "https://")
    error_message = "eks_cluster_identity_oidc_issuer must include https://."
  }

  # external-secrets and the kubernetes providers want the name, not the ARN.
  assert {
    condition     = output.eks_cluster_id == "production-main" && !startswith(output.eks_cluster_id, "arn:")
    error_message = "eks_cluster_id must be the cluster name."
  }

  assert {
    condition     = startswith(output.eks_cluster_identity_oidc_issuer_arn, "arn:aws:iam::") && strcontains(output.eks_cluster_identity_oidc_issuer_arn, ":oidc-provider/")
    error_message = "eks_cluster_identity_oidc_issuer_arn must be the OIDC provider ARN."
  }

  # The exact attribute, and a string (regex() fails on anything else).
  assert {
    condition = (
      output.eks_cluster_managed_security_group_id == aws_eks_cluster.default[0].vpc_config[0].cluster_security_group_id &&
      can(regex("^\\S+$", output.eks_cluster_managed_security_group_id))
    )
    error_message = "eks_cluster_managed_security_group_id must be the cluster's vpc_config cluster_security_group_id, as a string."
  }

  assert {
    condition     = output.cloudwatch_log_group_name == "/aws/eks/production-main/cluster"
    error_message = "cloudwatch_log_group_name must be the control-plane log group."
  }

  assert {
    condition     = length(output.eks_node_group_arns) == 2 && length(output.eks_managed_node_workers_role_arns) == 1
    error_message = "Two node groups share one node role."
  }
}

run "dev_and_staging_names" {
  command = plan

  variables {
    tags = {
      Environment = "staging-01"
    }
  }

  assert {
    condition     = aws_eks_cluster.default[0].name == "staging-01-main"
    error_message = "The staging cluster must be named staging-01-main."
  }

  assert {
    condition     = aws_iam_role.default[0].name == "staging-01-main-cluster-role"
    error_message = "IAM role names must be <Environment>-<name>-cluster-role."
  }

  assert {
    condition     = aws_eks_cluster.default[0].deletion_protection == false
    error_message = "Only prod clusters get deletion protection."
  }
}

run "name_repeating_the_environment_is_rejected" {
  command = plan

  variables {
    name = "production-main"
  }

  expect_failures = [var.name]
}

run "name_too_long_for_iam_is_rejected" {
  command = plan

  variables {
    name        = "a-very-long-cluster-name-that-overflows-iam"
    node_groups = {}
  }

  expect_failures = [var.name]
}

run "node_group_name_too_long_is_rejected" {
  command = plan

  variables {
    node_groups = {
      a-node-group-key-long-enough-to-overflow-sixty-three = {}
    }
  }

  expect_failures = [var.node_groups]
}

run "disabled_creates_nothing" {
  command = apply

  variables {
    enabled = false
  }

  assert {
    condition     = length(aws_eks_cluster.default) == 0 && length(aws_eks_node_group.default) == 0 && length(aws_kms_key.cluster) == 0
    error_message = "enabled = false must create nothing."
  }

  assert {
    condition     = output.eks_cluster_id == null && output.eks_cluster_identity_oidc_issuer == null && length(output.eks_node_group_arns) == 0
    error_message = "enabled = false must output nulls and empty lists."
  }
}

# --- Endpoint rules: variable validations, so they hold without credentials ---

run "public_endpoint_with_empty_cidrs_is_rejected" {
  command = plan

  variables {
    cluster_endpoint_public_access = true
    public_access_cidrs            = []
  }

  expect_failures = [var.public_access_cidrs]
}

run "public_endpoint_without_cidrs_is_rejected" {
  command = plan

  variables {
    cluster_endpoint_public_access = true
    public_access_cidrs            = null
  }

  expect_failures = [var.public_access_cidrs]
}

run "public_endpoint_open_to_the_world_is_rejected" {
  command = plan

  variables {
    cluster_endpoint_public_access = true
    public_access_cidrs            = ["203.0.113.0/24", "0.0.0.0/0"]
  }

  expect_failures = [var.public_access_cidrs]
}

# A zero-padded prefix is still /0: the check compares numbers, not strings.
run "public_endpoint_open_to_the_world_zero_padded_is_rejected" {
  command = plan

  variables {
    cluster_endpoint_public_access = true
    public_access_cidrs            = ["0.0.0.0/00"]
  }

  expect_failures = [var.public_access_cidrs]
}

run "public_endpoint_open_to_all_of_ipv6_zero_padded_is_rejected" {
  command = plan

  variables {
    cluster_endpoint_public_access = true
    public_access_cidrs            = ["::/00"]
  }

  expect_failures = [var.public_access_cidrs]
}

run "public_endpoint_open_to_all_of_ipv6_is_rejected" {
  command = plan

  variables {
    cluster_endpoint_public_access = true
    public_access_cidrs            = ["203.0.113.0/24", "::/0"]
  }

  expect_failures = [var.public_access_cidrs]
}

run "malformed_cidr_is_rejected" {
  command = plan

  variables {
    cluster_endpoint_public_access = true
    public_access_cidrs            = ["203.0.113.0"]
  }

  expect_failures = [var.public_access_cidrs]
}

run "public_endpoint_with_a_cidr_is_accepted" {
  command = plan

  variables {
    cluster_endpoint_public_access = true
    public_access_cidrs            = ["203.0.113.0/24"]
  }

  assert {
    condition     = aws_eks_cluster.default[0].vpc_config[0].endpoint_public_access && aws_eks_cluster.default[0].vpc_config[0].public_access_cidrs == toset(["203.0.113.0/24"])
    error_message = "A public endpoint with a named CIDR must plan."
  }
}

run "no_endpoint_is_rejected" {
  command = plan

  variables {
    cluster_endpoint_private_access = false
    cluster_endpoint_public_access  = false
  }

  expect_failures = [var.cluster_endpoint_public_access]
}

# --- KMS: prod passes its own key for secrets ---

run "caller_key_encrypts_secrets_and_the_log_group_no_component_key_created" {
  command = apply

  variables {
    cluster_encryption_config_kms_key_id = "arn:aws:kms:eu-west-2:123456789012:key/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition     = aws_eks_cluster.default[0].encryption_config[0].provider[0].key_arn == "arn:aws:kms:eu-west-2:123456789012:key/11111111-2222-3333-4444-555555555555"
    error_message = "Secrets must be encrypted with the caller's key."
  }

  assert {
    condition     = aws_cloudwatch_log_group.default[0].kms_key_id == "arn:aws:kms:eu-west-2:123456789012:key/11111111-2222-3333-4444-555555555555"
    error_message = "With a caller key given, the log group must use it too (kms/main's allow_cloudwatch_logs already grants every log group in this account and region)."
  }

  assert {
    condition     = length(aws_kms_key.cluster) == 0
    error_message = "With a caller key given, the component's own key is unused for both secrets and the log group, so it must not be created at all."
  }
}

run "component_key_encrypts_secrets_by_default" {
  command = apply

  assert {
    condition     = aws_eks_cluster.default[0].encryption_config[0].provider[0].key_arn == aws_kms_key.cluster[0].arn
    error_message = "Without a caller key, secrets use the component key."
  }

  assert {
    condition     = length(aws_kms_key.cluster) == 1
    error_message = "Without a caller key, the component must create its own key."
  }
}

# --- Node group EBS: node_group_ebs_kms_key_id (kms/main) is the default ---

run "node_group_ebs_kms_key_id_defaults_every_devices_key" {
  command = plan

  variables {
    node_group_ebs_kms_key_id = "arn:aws:kms:eu-west-2:123456789012:key/22222222-3333-4444-5555-666666666666"
  }

  assert {
    condition     = aws_launch_template.default["workers"].block_device_mappings[0].ebs[0].kms_key_id == "arn:aws:kms:eu-west-2:123456789012:key/22222222-3333-4444-5555-666666666666"
    error_message = "A block device with no ebs.kms_key_id of its own must default to node_group_ebs_kms_key_id."
  }
}

run "device_level_kms_key_id_wins_over_the_default" {
  command = plan

  variables {
    node_group_ebs_kms_key_id = "arn:aws:kms:eu-west-2:123456789012:key/22222222-3333-4444-5555-666666666666"
    node_groups = {
      workers = {
        instance_types = ["m5.xlarge"]
        block_device_map = {
          "/dev/xvda" = {
            ebs = {
              kms_key_id = "arn:aws:kms:eu-west-2:123456789012:key/33333333-4444-5555-6666-777777777777"
            }
          }
        }
      }
    }
  }

  assert {
    condition     = aws_launch_template.default["workers"].block_device_mappings[0].ebs[0].kms_key_id == "arn:aws:kms:eu-west-2:123456789012:key/33333333-4444-5555-6666-777777777777"
    error_message = "A device's own ebs.kms_key_id must win over node_group_ebs_kms_key_id."
  }
}

run "node_group_ebs_kms_key_id_empty_leaves_the_aws_managed_key" {
  command = plan

  assert {
    condition     = aws_launch_template.default["workers"].block_device_mappings[0].ebs[0].kms_key_id == null
    error_message = "With node_group_ebs_kms_key_id empty (the default) and no device-level key, the volume stays on the AWS managed aws/ebs key (kms_key_id unset)."
  }
}

run "unencrypted_device_does_not_get_the_default_kms_key_id" {
  command = plan

  variables {
    node_group_ebs_kms_key_id = "arn:aws:kms:eu-west-2:123456789012:key/22222222-3333-4444-5555-666666666666"
    node_groups = {
      workers = {
        instance_types = ["m5.xlarge"]
        block_device_map = {
          "/dev/xvda" = {
            ebs = {
              encrypted = false
            }
          }
        }
      }
    }
  }

  assert {
    condition     = aws_launch_template.default["workers"].block_device_mappings[0].ebs[0].kms_key_id == null
    error_message = "A device with encrypted = false must not get node_group_ebs_kms_key_id: EC2 rejects a launch template that sets KmsKeyId on an unencrypted device."
  }
}

# --- Name validation: no false positives, and the boundaries ---

run "names_that_merely_resemble_the_environment_are_accepted" {
  command = plan

  variables {
    name = "production2"
  }

  assert {
    condition     = aws_eks_cluster.default[0].name == "production-production2"
    error_message = "production2 does not start with \"production-\" and must be accepted."
  }
}

run "prod_prefix_is_not_the_environment" {
  command = plan

  variables {
    name = "prod-main"
  }

  assert {
    condition     = aws_eks_cluster.default[0].name == "production-prod-main"
    error_message = "prod-main is not the Environment and must be accepted."
  }
}

run "environment_in_another_case_is_rejected" {
  command = plan

  variables {
    name = "Production-main"
  }

  expect_failures = [var.name]
}

# "production-" (11) + 40 + "-cluster-role" (13) = 64, IAM's limit exactly.
run "longest_name_is_accepted" {
  command = plan

  variables {
    name        = "abcdefghij-abcdefghij-abcdefghij-abcdefg"
    node_groups = {}
  }

  assert {
    condition     = length(aws_iam_role.default[0].name) == 64
    error_message = "A 64-character role name is within IAM's limit."
  }
}

# "production-main-" (16) + 38 = 54, the node group budget at random_pet_length 1.
run "longest_node_group_key_is_accepted" {
  command = plan

  variables {
    node_groups = {
      abcdefghij-abcdefghij-abcdefghij-abcde = {}
    }
  }

  assert {
    condition     = length(aws_launch_template.default["abcdefghij-abcdefghij-abcdefghij-abcde"].name_prefix) == 55
    error_message = "A 54-character name base (plus \"-\") is within the node group budget."
  }
}

# --- Kubernetes 1.36: AL2023 node groups ---

run "node_groups_default_to_al2023" {
  command = plan

  variables {
    cluster_kubernetes_version = "1.36"
  }

  assert {
    condition     = alltrue([for ng in aws_eks_node_group.default : ng.ami_type == "AL2023_x86_64_STANDARD"])
    error_message = "Node groups default to AL2023_x86_64_STANDARD: AWS publishes no AL2 EKS AMIs for Kubernetes 1.33 and later (a deviation from Cloud Posse's AL2_x86_64)."
  }

  assert {
    condition     = aws_eks_cluster.default[0].version == "1.36"
    error_message = "The cluster takes cluster_kubernetes_version."
  }
}

run "al2_on_136_is_rejected" {
  command = plan

  variables {
    cluster_kubernetes_version = "1.36"
    node_groups = {
      workers = {
        ami_type = "AL2_x86_64"
      }
    }
  }

  expect_failures = [var.node_groups]
}

run "al2_before_133_is_accepted" {
  command = plan

  variables {
    cluster_kubernetes_version = "1.32"
    node_groups = {
      workers = {
        ami_type = "AL2_x86_64"
      }
    }
  }

  assert {
    condition     = aws_eks_node_group.default["workers"].ami_type == "AL2_x86_64"
    error_message = "AL2 is still valid before Kubernetes 1.33."
  }
}
