# Access model, upgrade policy, vpc-cni IRSA and node IMDS defaults, with mock
# providers (no AWS credentials). Run from the component directory with
# `terraform init -backend=false && terraform test`.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

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

# A distinct ARN, so the addon assertion cannot pass on the shared mock value.
override_resource {
  target = aws_iam_role.vpc_cni
  values = {
    arn = "arn:aws:iam::123456789012:role/production-main-vpc-cni-role"
  }
}

variables {
  region     = "eu-west-2"
  name       = "main"
  subnet_ids = ["subnet-0a1b2c3d", "subnet-4e5f6a7b"]
  tags = {
    Environment = "production"
  }
  node_groups = {
    workers = {
      instance_types = ["m5.xlarge"]
    }
  }
}

run "defaults_are_api_mode_without_creator_admin_and_standard_support" {
  command = plan

  assert {
    condition     = aws_eks_cluster.default[0].access_config[0].authentication_mode == "API"
    error_message = "The default authentication mode must be API (access entries, no aws-auth)."
  }

  assert {
    condition     = aws_eks_cluster.default[0].access_config[0].bootstrap_cluster_creator_admin_permissions == false
    error_message = "The cluster creator must not get hidden admin permissions by default."
  }

  assert {
    condition     = aws_eks_cluster.default[0].upgrade_policy[0].support_type == "STANDARD"
    error_message = "upgrade_policy must default to STANDARD so the cluster never moves to paid extended support silently."
  }

  assert {
    condition     = length(aws_eks_access_entry.map) == 0 && length(aws_eks_access_entry.standard) == 0
    error_message = "No access entry is created unless one is declared."
  }
}

run "node_imds_hop_limit_defaults_to_1" {
  command = plan

  assert {
    condition     = aws_launch_template.default["workers"].metadata_options[0].http_put_response_hop_limit == 1
    error_message = "Node IMDS hop limit must default to 1."
  }
}

run "node_group_may_raise_the_hop_limit" {
  command = plan

  variables {
    node_groups = {
      workers = {
        metadata_http_put_response_hop_limit = 2
      }
    }
  }

  assert {
    condition     = aws_launch_template.default["workers"].metadata_options[0].http_put_response_hop_limit == 2
    error_message = "A node group must be able to set its own hop limit."
  }
}

run "cni_policy_is_on_the_vpc_cni_irsa_role_not_the_node_role" {
  command = apply

  assert {
    condition = length([
      for a in [
        aws_iam_role_policy_attachment.amazon_eks_worker_node_policy[0],
        aws_iam_role_policy_attachment.amazon_ec2_container_registry_read_only[0],
      ] : a if a.policy_arn == "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
    ]) == 0
    error_message = "The node role must not carry AmazonEKS_CNI_Policy."
  }

  assert {
    condition = (
      aws_iam_role_policy_attachment.vpc_cni[0].policy_arn == "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy" &&
      aws_iam_role_policy_attachment.vpc_cni[0].role == aws_iam_role.vpc_cni[0].name &&
      aws_iam_role_policy_attachment.vpc_cni[0].role != aws_iam_role.node[0].name
    )
    error_message = "AmazonEKS_CNI_Policy must be attached to the vpc-cni IRSA role."
  }

  assert {
    condition     = aws_iam_role.vpc_cni[0].name == "production-main-vpc-cni-role"
    error_message = "The vpc-cni role must be <cluster>-vpc-cni-role."
  }

  assert {
    condition = (
      jsondecode(aws_iam_role.vpc_cni[0].assume_role_policy).Statement[0].Condition.StringEquals["oidc.eks.eu-west-2.amazonaws.com/id/ABCDEF0123456789ABCDEF0123456789:sub"] == "system:serviceaccount:kube-system:aws-node" &&
      jsondecode(aws_iam_role.vpc_cni[0].assume_role_policy).Statement[0].Condition.StringEquals["oidc.eks.eu-west-2.amazonaws.com/id/ABCDEF0123456789ABCDEF0123456789:aud"] == "sts.amazonaws.com" &&
      jsondecode(aws_iam_role.vpc_cni[0].assume_role_policy).Statement[0].Principal.Federated == aws_iam_openid_connect_provider.default[0].arn
    )
    error_message = "Only kube-system/aws-node may assume the vpc-cni role, through the cluster's OIDC provider."
  }

  assert {
    condition = (
      aws_eks_addon.vpc_cni[0].addon_name == "vpc-cni" &&
      aws_eks_addon.vpc_cni[0].service_account_role_arn == "arn:aws:iam::123456789012:role/production-main-vpc-cni-role" &&
      output.vpc_cni_service_account_role_arn == "arn:aws:iam::123456789012:role/production-main-vpc-cni-role"
    )
    error_message = "The vpc-cni addon must get the IRSA role as service_account_role_arn."
  }

  assert {
    condition     = aws_eks_addon.vpc_cni[0].resolve_conflicts_on_create == "OVERWRITE" && aws_eks_addon.vpc_cni[0].preserve
    error_message = "The addon must adopt the self-managed aws-node EKS installs, and keep it if the addon is removed."
  }

  assert {
    condition     = keys(output.eks_addons_versions) == ["vpc-cni"]
    error_message = "eks_addons_versions must list vpc-cni."
  }
}

run "vpc_cni_existing_role_creates_none" {
  command = plan

  variables {
    vpc_cni_addon = {
      service_account_role_arn = "arn:aws:iam::123456789012:role/shared-vpc-cni"
    }
  }

  assert {
    condition     = length(aws_iam_role.vpc_cni) == 0 && length(aws_iam_role_policy_attachment.vpc_cni) == 0
    error_message = "A caller-supplied vpc-cni role must not create another."
  }

  assert {
    condition     = aws_eks_addon.vpc_cni[0].service_account_role_arn == "arn:aws:iam::123456789012:role/shared-vpc-cni"
    error_message = "The addon must use the caller's role."
  }
}

# The stack wiring: CI plan role View, CI apply role ClusterAdmin.
run "list_entries_for_ci_roles" {
  command = apply

  variables {
    access_entries = [
      { principal_arn = "arn:aws:iam::123456789012:role/fnx-prod-production-ci-plan" },
      { principal_arn = "arn:aws:iam::123456789012:role/fnx-prod-production-ci-apply" },
    ]
    access_policy_associations = [
      {
        principal_arn = "arn:aws:iam::123456789012:role/fnx-prod-production-ci-plan"
        policy_arn    = "AmazonEKSViewPolicy"
        access_scope  = { type = "cluster" }
      },
      {
        principal_arn = "arn:aws:iam::123456789012:role/fnx-prod-production-ci-apply"
        policy_arn    = "AmazonEKSClusterAdminPolicy"
        access_scope  = { type = "cluster" }
      },
    ]
  }

  assert {
    condition = (
      length(aws_eks_access_entry.standard) == 2 &&
      alltrue([for e in aws_eks_access_entry.standard : e.type == "STANDARD" && e.cluster_name == "production-main"])
    )
    error_message = "Each listed principal must get a STANDARD access entry on the cluster."
  }

  assert {
    condition = (
      aws_eks_access_policy_association.list[0].policy_arn == "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy" &&
      aws_eks_access_policy_association.list[1].policy_arn == "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" &&
      aws_eks_access_policy_association.list[1].access_scope[0].type == "cluster"
    )
    error_message = "Policy names must expand to the EKS access policy ARNs, at cluster scope."
  }

  assert {
    condition     = length(output.eks_access_entry_principal_arns) == 2
    error_message = "eks_access_entry_principal_arns must list both entries."
  }
}

# iam/ci returns a null ci_apply_role_arn while its apply role is disabled.
run "null_principal_is_skipped" {
  command = plan

  variables {
    access_entries = [
      { principal_arn = "arn:aws:iam::123456789012:role/fnx-prod-production-ci-plan" },
      { principal_arn = null },
    ]
    access_policy_associations = [
      {
        principal_arn = "arn:aws:iam::123456789012:role/fnx-prod-production-ci-plan"
        policy_arn    = "View"
      },
      {
        principal_arn = null
        policy_arn    = "ClusterAdmin"
      },
    ]
  }

  assert {
    condition     = length(aws_eks_access_entry.standard) == 1 && length(aws_eks_access_policy_association.list) == 1
    error_message = "An entry or association with a null principal_arn must be skipped."
  }

  assert {
    condition     = aws_eks_access_policy_association.list[0].policy_arn == "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
    error_message = "The short name View must expand to AmazonEKSViewPolicy."
  }
}

run "map_entries_expand_policies_and_translate_system_masters" {
  command = plan

  variables {
    access_entry_map = {
      "arn:aws:iam::123456789012:role/platform-admin" = {
        kubernetes_groups = ["system:masters"]
      }
      "arn:aws:iam::123456789012:role/team-a" = {
        access_policy_associations = {
          Edit = {
            access_scope = {
              type       = "namespace"
              namespaces = ["team-a"]
            }
          }
          AmazonEKSAdminViewPolicy = {}
        }
      }
    }
  }

  assert {
    condition     = length(aws_eks_access_entry.map["arn:aws:iam::123456789012:role/platform-admin"].kubernetes_groups) == 0
    error_message = "system:masters must be removed from a STANDARD entry's groups."
  }

  assert {
    condition = (
      aws_eks_access_policy_association.map["arn:aws:iam::123456789012:role/platform-admin-arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"].access_scope[0].type == "cluster" &&
      aws_eks_access_policy_association.map["arn:aws:iam::123456789012:role/team-a-arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"].access_scope[0].namespaces == toset(["team-a"]) &&
      aws_eks_access_policy_association.map["arn:aws:iam::123456789012:role/team-a-arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminViewPolicy"].access_scope[0].type == "cluster"
    )
    error_message = "system:masters must become ClusterAdmin; Edit and AmazonEKSAdminViewPolicy must expand to their ARNs with their scopes."
  }
}

# The stacks' human admins (globals.yaml): Cloud Posse's
# map_additional_iam_roles with system:masters, next to a map entry of a
# different shape and the CI roles' list entries.
run "admin_roles_get_cluster_admin_with_the_sso_path_kept" {
  command = plan

  variables {
    map_additional_iam_roles = [{
      rolearn = "arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/eu-west-2/AWSReservedSSO_AdministratorAccess_0123456789abcdef"
      groups  = ["system:masters"]
    }]
    access_entry_map = {
      "arn:aws:iam::123456789012:role/team-a" = {
        access_policy_associations = {
          Edit = {
            access_scope = {
              type       = "namespace"
              namespaces = ["team-a"]
            }
          }
        }
      }
    }
    access_entries = [
      { principal_arn = "arn:aws:iam::123456789012:role/fnx-dev-testenv-01-ci-apply" },
    ]
    access_policy_associations = [{
      principal_arn = "arn:aws:iam::123456789012:role/fnx-dev-testenv-01-ci-apply"
      policy_arn    = "AmazonEKSClusterAdminPolicy"
    }]
  }

  assert {
    condition = (
      aws_eks_access_entry.map["arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/eu-west-2/AWSReservedSSO_AdministratorAccess_0123456789abcdef"].principal_arn == "arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/eu-west-2/AWSReservedSSO_AdministratorAccess_0123456789abcdef" &&
      aws_eks_access_entry.map["arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/eu-west-2/AWSReservedSSO_AdministratorAccess_0123456789abcdef"].type == "STANDARD" &&
      length(aws_eks_access_entry.map["arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/eu-west-2/AWSReservedSSO_AdministratorAccess_0123456789abcdef"].kubernetes_groups) == 0
    )
    error_message = "An admin role must be a STANDARD access entry keyed by its full ARN, path included, with system:masters removed from its groups."
  }

  assert {
    condition     = aws_eks_access_policy_association.map["arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/eu-west-2/AWSReservedSSO_AdministratorAccess_0123456789abcdef-arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"].access_scope[0].type == "cluster"
    error_message = "An admin role must get a cluster-scoped AmazonEKSClusterAdminPolicy association."
  }

  assert {
    condition     = length(aws_eks_access_entry.map) == 2 && length(aws_eks_access_policy_association.map) == 2 && length(aws_eks_access_entry.standard) == 1
    error_message = "The admin role, the map entry and the CI list entry must all be created."
  }
}

run "sso_admin_role_without_its_path_is_rejected" {
  command = plan

  variables {
    map_additional_iam_roles = [{
      rolearn = "arn:aws:iam::123456789012:role/AWSReservedSSO_AdministratorAccess_0123456789abcdef"
      groups  = ["system:masters"]
    }]
  }

  expect_failures = [var.map_additional_iam_roles]
}

run "assumed_role_session_arn_is_rejected_as_admin_role" {
  command = plan

  variables {
    map_additional_iam_roles = [{
      rolearn = "arn:aws:sts::123456789012:assumed-role/AWSReservedSSO_AdministratorAccess_0123456789abcdef/jane"
      groups  = ["system:masters"]
    }]
  }

  expect_failures = [var.map_additional_iam_roles]
}

run "placeholder_admin_role_is_rejected" {
  command = plan

  variables {
    map_additional_iam_roles = [{
      rolearn = "arn:aws:iam::<account>:role/aws-reserved/sso.amazonaws.com/eu-west-2/AWSReservedSSO_AdministratorAccess_<hash>"
      groups  = ["system:masters"]
    }]
  }

  expect_failures = [var.map_additional_iam_roles]
}

run "service_linked_admin_role_is_rejected" {
  command = plan

  variables {
    map_additional_iam_roles = [{
      rolearn = "arn:aws:iam::123456789012:role/aws-service-role/eks.amazonaws.com/AWSServiceRoleForAmazonEKS"
      groups  = ["system:masters"]
    }]
  }

  expect_failures = [var.map_additional_iam_roles]
}

run "admin_role_with_another_system_group_is_rejected" {
  command = plan

  variables {
    map_additional_iam_roles = [{
      rolearn = "arn:aws:iam::123456789012:role/platform-admin"
      groups  = ["system:nodes"]
    }]
  }

  expect_failures = [var.map_additional_iam_roles]
}

run "namespace_scope_without_namespaces_is_rejected" {
  command = plan

  variables {
    access_policy_associations = [{
      principal_arn = "arn:aws:iam::123456789012:role/team-a"
      policy_arn    = "Edit"
      access_scope  = { type = "namespace" }
    }]
  }

  expect_failures = [var.access_policy_associations]
}

run "map_namespace_scope_without_namespaces_is_rejected" {
  command = plan

  variables {
    access_entry_map = {
      "arn:aws:iam::123456789012:role/team-a" = {
        access_policy_associations = {
          Edit = { access_scope = { type = "namespace", namespaces = [] } }
        }
      }
    }
  }

  expect_failures = [var.access_entry_map]
}

run "cluster_scope_with_namespaces_is_rejected" {
  command = plan

  variables {
    access_policy_associations = [{
      principal_arn = "arn:aws:iam::123456789012:role/team-a"
      policy_arn    = "View"
      access_scope  = { type = "cluster", namespaces = ["team-a"] }
    }]
  }

  expect_failures = [var.access_policy_associations]
}

run "unknown_scope_type_is_rejected" {
  command = plan

  variables {
    access_policy_associations = [{
      principal_arn = "arn:aws:iam::123456789012:role/team-a"
      policy_arn    = "View"
      access_scope  = { type = "account" }
    }]
  }

  expect_failures = [var.access_policy_associations]
}

run "unknown_access_policy_is_rejected" {
  command = plan

  variables {
    access_policy_associations = [{
      principal_arn = "arn:aws:iam::123456789012:role/team-a"
      policy_arn    = "AmazonEKSSuperUserPolicy"
    }]
  }

  expect_failures = [var.access_policy_associations]
}

run "iam_policy_arn_is_rejected_as_access_policy" {
  command = plan

  variables {
    access_entry_map = {
      "arn:aws:iam::123456789012:role/team-a" = {
        access_policy_associations = {
          "arn:aws:iam::aws:policy/AdministratorAccess" = {}
        }
      }
    }
  }

  expect_failures = [var.access_entry_map]
}

run "system_group_on_list_entry_is_rejected" {
  command = plan

  variables {
    access_entries = [{
      principal_arn     = "arn:aws:iam::123456789012:role/team-a"
      kubernetes_groups = ["system:masters"]
    }]
  }

  expect_failures = [var.access_entries]
}

run "config_map_mode_is_rejected" {
  command = plan

  variables {
    access_config = { authentication_mode = "CONFIG_MAP" }
  }

  expect_failures = [var.access_config]
}

run "unknown_upgrade_support_type_is_rejected" {
  command = plan

  variables {
    upgrade_policy = { support_type = "LTS" }
  }

  expect_failures = [var.upgrade_policy]
}

run "extended_support_is_an_explicit_choice" {
  command = plan

  variables {
    upgrade_policy = { support_type = "EXTENDED" }
    access_config  = { authentication_mode = "API_AND_CONFIG_MAP", bootstrap_cluster_creator_admin_permissions = true }
  }

  assert {
    condition = (
      aws_eks_cluster.default[0].upgrade_policy[0].support_type == "EXTENDED" &&
      aws_eks_cluster.default[0].access_config[0].authentication_mode == "API_AND_CONFIG_MAP"
    )
    error_message = "Explicit access_config and upgrade_policy values must reach the cluster."
  }

  # The cluster already exists in this file's state (earlier apply runs), and
  # bootstrap_cluster_creator_admin_permissions only applies at creation, so
  # it is ignored afterwards, as in Cloud Posse.
  assert {
    condition     = aws_eks_cluster.default[0].access_config[0].bootstrap_cluster_creator_admin_permissions == false
    error_message = "bootstrap_cluster_creator_admin_permissions must be ignored once the cluster exists."
  }
}

run "invalid_vpc_cni_role_is_rejected" {
  command = plan

  variables {
    vpc_cni_addon = { service_account_role_arn = "aws-node-role" }
  }

  expect_failures = [var.vpc_cni_addon]
}

run "disabled_creates_no_access_or_addon" {
  command = plan

  variables {
    enabled = false
    access_entries = [
      { principal_arn = "arn:aws:iam::123456789012:role/fnx-prod-production-ci-plan" },
    ]
    access_policy_associations = [{
      principal_arn = "arn:aws:iam::123456789012:role/fnx-prod-production-ci-plan"
      policy_arn    = "View"
    }]
  }

  assert {
    condition = (
      length(aws_eks_access_entry.standard) == 0 && length(aws_eks_access_policy_association.list) == 0 &&
      length(aws_eks_addon.vpc_cni) == 0 && length(aws_iam_role.vpc_cni) == 0
    )
    error_message = "enabled = false must create no access entry, association, addon or role."
  }
}
