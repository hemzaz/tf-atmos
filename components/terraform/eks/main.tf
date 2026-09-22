# Add AWS caller identity data source for IAM policies
data "aws_caller_identity" "current" {}

locals {
  clusters = {
    for k, v in var.clusters : k => v if lookup(v, "enabled", true)
  }

  cluster_log_group_names = {
    for k, v in local.clusters : k => "/aws/eks/${var.tags["Environment"]}-${k}/cluster"
  }

  # Merge node groups across all clusters.
  # `name_base` is the node group's name without its random_pet suffix:
  # "<cluster>-<node group>", with the Environment prefixed only when the
  # cluster key does not already start with it ("production-main", not
  # "production-production-main"). It is a plain `-` join, never the `.` of the
  # map key, which EKS does not document as valid in a node group name.
  # Keep this expression in sync with the node group name validation on
  # var.clusters, which has to repeat it because a validation cannot read locals.
  node_groups = merge([
    for cluster_key, cluster in local.clusters : {
      for ng_key, ng in lookup(cluster, "node_groups", {}) :
      "${cluster_key}.${ng_key}" => merge(ng, {
        cluster_name = cluster_key
        name_base    = "${var.tags["Environment"]}-${trimprefix(cluster_key, "${var.tags["Environment"]}-")}-${ng_key}"
      })
      if lookup(ng, "enabled", true)
    }
  ]...)

  # One label for everything a node group creates, as Cloud Posse does: the
  # node group, its launch template, and what the template launches.
  node_group_tags = {
    for k, ng in local.node_groups : k => merge(var.tags, ng.tags, { Name = ng.name_base })
  }

  # The launch template's settings in one object, read both by the template
  # and by the random_pet keeper, as `launch_template_config` is in
  # cloudposse/terraform-aws-eks-node-group (launch-template.tf).
  # Any new aws_launch_template argument must be added here and read from
  # here; otherwise a change to it rolls in place instead of replacing the group.
  launch_template_configs = {
    for k, ng in local.node_groups : k => {
      block_device_mappings = ng.block_device_map
      tag_specifications    = ["instance", "volume", "network-interface"]
      # http_endpoint is documented as optional but is required whenever
      # http_put_response_hop_limit is set.
      metadata_options = {
        http_endpoint               = ng.metadata_http_endpoint_enabled ? "enabled" : "disabled"
        http_put_response_hop_limit = ng.metadata_http_put_response_hop_limit
        http_tokens                 = ng.metadata_http_tokens_required ? "required" : "optional"
      }
      tags = local.node_group_tags[k]
      monitoring = {
        enabled = ng.detailed_monitoring_enabled
      }
    }
  }

  # Cloud Posse: "When `null` (default) this input takes the value of
  # `create_before_destroy`". Node groups here are always
  # create_before_destroy, so null means true.
  immediately_apply_lt_changes = {
    for k, ng in local.node_groups : k => coalesce(ng.immediately_apply_lt_changes, true)
  }
}

resource "aws_cloudwatch_log_group" "eks" {
  for_each = local.clusters

  # checkov:skip=CKV_AWS_338:Retention is a per-stack cost decision, not a module one. Only prod pins default_cluster_log_retention_days (90); dev and staging inherit it, so raising the default to the year this check wants would quadruple their audit-log spend without anyone deciding to. The repo accepts the same finding on its five other log groups. Removing the dead lookup() below is what made this check resolvable at all -- it was never passing, only invisible.
  name = local.cluster_log_group_names[each.key]
  # No per-cluster override: `clusters` is a typed object and declares neither
  # `log_retention_days` nor `log_kms_key_id`, so a stack setting either would be
  # dropped by the type constraint and silently ignored here.
  retention_in_days = var.default_cluster_log_retention_days
  # The cluster's own key, the one already encrypting its secrets. Until now
  # this read a `log_kms_key_id` key that the typed schema does not declare, so
  # it always resolved to null and the control-plane logs -- which carry the
  # audit trail -- were written unencrypted. Checkov could not see that, because
  # it cannot resolve a lookup(): removing the dead expression is what surfaced
  # CKV_AWS_158.
  kms_key_id = aws_kms_key.eks[each.key].arn

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {}),
    {
      Name        = "/aws/eks/${var.tags["Environment"]}-${each.key}/cluster"
      Environment = var.tags["Environment"]
      Component   = "eks"
      ClusterName = "${var.tags["Environment"]}-${each.key}"
    }
  )
}

#trivy:ignore:AWS-0040 Public endpoint is off unless a cluster sets endpoint_public_access = true
resource "aws_eks_cluster" "clusters" {
  #checkov:skip=CKV_AWS_38:Public endpoint is off unless a cluster sets endpoint_public_access = true
  for_each = local.clusters

  name     = "${var.tags["Environment"]}-${each.key}"
  role_arn = aws_iam_role.cluster[each.key].arn
  version  = coalesce(each.value.kubernetes_version, var.default_kubernetes_version)

  vpc_config {
    subnet_ids              = coalesce(each.value.subnet_ids, var.subnet_ids)
    endpoint_private_access = lookup(each.value, "endpoint_private_access", true)
    endpoint_public_access  = lookup(each.value, "endpoint_public_access", false)
    public_access_cidrs     = each.value.public_access_cidrs
    security_group_ids      = lookup(each.value, "security_group_ids", [])
  }

  encryption_config {
    provider {
      # Use explicit fallback logic to avoid dependency cycle
      key_arn = lookup(each.value, "kms_key_arn", null) != null ? lookup(each.value, "kms_key_arn", null) : aws_kms_key.eks[each.key].arn
    }
    resources = ["secrets"]
  }

  enabled_cluster_log_types = lookup(each.value, "enabled_cluster_log_types", ["api", "audit", "authenticator", "controllerManager", "scheduler"])

  # Add timeouts to allow for longer cluster creation/update
  timeouts {
    create = "45m"
    update = "60m"
    delete = "30m"
  }

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {}),
    {
      Name        = "${var.tags["Environment"]}-${each.key}"
      Environment = var.tags["Environment"]
      Component   = "eks"
      ClusterName = "${var.tags["Environment"]}-${each.key}"
      CreatedBy   = "terraform"
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.cluster_eks_cluster_policy,
    aws_iam_role_policy_attachment.cluster_eks_vpc_resource_controller,
    aws_cloudwatch_log_group.eks
  ]

  # prevent_destroy only accepts literals, so production protection uses EKS deletion protection instead
  deletion_protection = var.enable_cluster_protection && contains(["prod", "production"], lower(var.tags["Environment"]))

  lifecycle {
    # Add preconditions for various cluster requirements
    precondition {
      condition     = length(coalesce(each.value.subnet_ids, var.subnet_ids)) >= 2
      error_message = "At least 2 subnet IDs are required for the EKS cluster ${each.key} to ensure high availability."
    }

    precondition {
      condition     = can(regex("^\\d+\\.(\\d+)$", coalesce(each.value.kubernetes_version, var.default_kubernetes_version)))
      error_message = "Kubernetes version for cluster ${each.key} must be in the format 'X.Y' (e.g., 1.28)."
    }

    precondition {
      condition     = length(lookup(each.value, "enabled_cluster_log_types", [])) > 0
      error_message = "At least one cluster log type must be enabled for cluster ${each.key}."
    }
  }
}

resource "aws_kms_key" "eks" {
  for_each = local.clusters

  description             = "KMS key for EKS ${each.key} secrets and control-plane log encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  # Add key policy to allow EKS service to use the key and AWS root user to administer it
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "Enable IAM User Permissions",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        Action = [
          "kms:Create*",
          "kms:Describe*",
          "kms:Enable*",
          "kms:List*",
          "kms:Put*",
          "kms:Update*",
          "kms:Revoke*",
          "kms:Disable*",
          "kms:Get*",
          "kms:Delete*",
          "kms:TagResource",
          "kms:UntagResource",
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion"
        ],
        Resource = "*"
      },
      {
        Sid    = "Allow EKS Service to use the key",
        Effect = "Allow",
        Principal = {
          Service = "eks.amazonaws.com"
        },
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource = "*",
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id,
            "kms:ViaService"    = "eks.${var.region}.amazonaws.com"
          }
        }
      },
      {
        # Required for the log group below to use this key. Without it, CloudWatch
        # Logs cannot write and AWS rejects the key association outright, so a
        # missing statement fails the apply rather than silently dropping logs.
        # Scoped by encryption context to this cluster's log group, which is why
        # the name comes from local.cluster_log_group_names rather than being
        # spelled out a second time.
        Sid    = "Allow CloudWatch Logs to use the key for this cluster's log group",
        Effect = "Allow",
        Principal = {
          Service = "logs.${var.region}.amazonaws.com"
        },
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ],
        Resource = "*",
        Condition = {
          ArnEquals = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:${local.cluster_log_group_names[each.key]}"
          }
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {}),
    {
      Name        = "${var.tags["Environment"]}-${each.key}-kms-key"
      Environment = var.tags["Environment"]
      Cluster     = each.key
      ManagedBy   = "terraform"
    }
  )
}

// Log group configuration moved to aws_cloudwatch_log_group.eks above

# IAM Role for EKS Cluster
resource "aws_iam_role" "cluster" {
  for_each = local.clusters

  name = "${var.tags["Environment"]}-${each.key}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {}),
    {
      Name = "${var.tags["Environment"]}-${each.key}-cluster-role"
    }
  )
}

resource "aws_iam_role_policy_attachment" "cluster_eks_cluster_policy" {
  for_each = local.clusters

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster[each.key].name
}

resource "aws_iam_role_policy_attachment" "cluster_eks_vpc_resource_controller" {
  for_each = local.clusters

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.cluster[each.key].name
}

# EKS Node Groups
# A launch template is the only way to control root-volume encryption and
# volume type on a managed node group; `aws_eks_node_group` exposes neither.
# One template per node group, because block_device_map is per node group.
# Deliberately no `image_id`/`user_data`: leaving them unset lets EKS supply the
# AMI matching `ami_type` and inject its own bootstrap script.
resource "aws_launch_template" "node_groups" {
  # checkov:skip=CKV_AWS_79: http_tokens is "required" unless a stack sets
  #   metadata_http_tokens_required = false. Checkov cannot evaluate the
  #   conditional below and flags the resource whatever the value resolves to.
  # checkov:skip=CKV_AWS_341: the hop limit defaults to 2 because AWS requires at
  #   least 2 for a container off the host network to reach IMDSv2
  #   (https://docs.aws.amazon.com/eks/latest/userguide/launch-templates.html),
  #   which is also cloudposse/terraform-aws-eks-node-group's default. Prefer IRSA
  #   over the instance profile and set the limit to 1 where no pod needs IMDS.
  for_each = local.node_groups

  # A launch template name_prefix may be up to 102 characters (128 minus the
  # 26-character unique suffix). name_base is capped below 63 on var.clusters,
  # well inside that limit.
  name_prefix = "${each.value.name_base}-"
  description = "Managed node group ${each.key} in cluster ${each.value.cluster_name}"

  dynamic "block_device_mappings" {
    for_each = local.launch_template_configs[each.key].block_device_mappings

    content {
      device_name  = block_device_mappings.key
      no_device    = block_device_mappings.value.no_device
      virtual_name = block_device_mappings.value.virtual_name

      dynamic "ebs" {
        for_each = block_device_mappings.value.ebs == null ? [] : [block_device_mappings.value.ebs]

        content {
          delete_on_termination = ebs.value.delete_on_termination
          encrypted             = ebs.value.encrypted
          iops                  = ebs.value.iops
          kms_key_id            = ebs.value.kms_key_id
          snapshot_id           = ebs.value.snapshot_id
          throughput            = ebs.value.throughput
          volume_size           = ebs.value.volume_size
          volume_type           = ebs.value.volume_type
        }
      }
    }
  }

  metadata_options {
    http_endpoint               = local.launch_template_configs[each.key].metadata_options.http_endpoint
    http_put_response_hop_limit = local.launch_template_configs[each.key].metadata_options.http_put_response_hop_limit
    http_tokens                 = local.launch_template_configs[each.key].metadata_options.http_tokens
  }

  monitoring {
    enabled = local.launch_template_configs[each.key].monitoring.enabled
  }

  # Resource tags on the launch template tag only the template itself. These
  # propagate the tags to what EKS launches from it. The resource types match
  # the `resources_to_tag` default in cloudposse/terraform-aws-eks-node-group.
  dynamic "tag_specifications" {
    for_each = local.launch_template_configs[each.key].tag_specifications

    content {
      resource_type = tag_specifications.value
      tags          = local.launch_template_configs[each.key].tags
    }
  }

  tags = local.launch_template_configs[each.key].tags

  lifecycle {
    create_before_destroy = true
  }
}

# The node group's name suffix, as in cloudposse/terraform-aws-eks-node-group.
# The node group is create_before_destroy, so a replacement has to run beside
# the live group under a different name, or EKS rejects it with
# ResourceInUseException. The keepers are every node group input that the AWS
# provider marks ForceNew: when one of them changes, a new pet is generated
# and the replacement gets a fresh name. Keeper set and launch template
# switch as in cloudposse/terraform-aws-eks-node-group main.tf.
#
# Not `node_group_name_prefix`: the provider caps that at 37 characters, and
# the prod names run to 44.
resource "random_pet" "node_groups" {
  for_each = local.node_groups

  # The pet is Name (length 1), Adjective-Name (2), or one Adverb per word
  # beyond two, then Adjective-Name (3+). With the pinned random provider,
  # names and adjectives are at most 8 characters and adverbs at most 10.
  # The name_base validation on var.clusters budgets exactly that, "-" included.
  length    = each.value.random_pet_length
  separator = "-"

  keepers = {
    node_role_arn  = aws_iam_role.node[each.value.cluster_name].arn
    subnet_ids     = join(",", sort(coalesce(each.value.subnet_ids, var.subnet_ids)))
    instance_types = join(",", each.value.instance_types)
    ami_type       = each.value.ami_type
    capacity_type  = each.value.capacity_type
    # immediately_apply_lt_changes (default: true, following
    # create_before_destroy): any launch template change is a new pet, so the
    # node group is replaced blue/green and every node gets the change at
    # once. false: only a new template ID (launch_template.id is ForceNew)
    # renames the group; a content change is a new template version that EKS
    # rolls onto the existing group.
    launch_template_id = (local.immediately_apply_lt_changes[each.key]
      ? jsonencode(local.launch_template_configs[each.key])
      : aws_launch_template.node_groups[each.key].id
    )
  }
}

resource "aws_eks_node_group" "node_groups" {
  for_each = local.node_groups

  cluster_name = aws_eks_cluster.clusters[each.value.cluster_name].name
  # EKS allows 63 characters. The validation on var.clusters caps name_base
  # at 63 minus the longest possible "-<pet>", so the name always fits. The
  # pet is unknown until apply, so the cap is the only plan-time check.
  node_group_name = "${each.value.name_base}-${random_pet.node_groups[each.key].id}"
  node_role_arn   = aws_iam_role.node[each.value.cluster_name].arn
  # A typed object always carries the attribute, so an unset value arrives as
  # null rather than absent and `lookup` would no longer reach its default.
  subnet_ids = coalesce(each.value.subnet_ids, var.subnet_ids)

  instance_types = each.value.instance_types
  ami_type       = each.value.ami_type
  capacity_type  = each.value.capacity_type
  # No `disk_size`: AWS rejects a node group that sets it while a launch
  # template is attached. Size lives in block_device_map instead.

  launch_template {
    id      = aws_launch_template.node_groups[each.key].id
    version = aws_launch_template.node_groups[each.key].latest_version
  }

  scaling_config {
    desired_size = each.value.desired_size
    max_size     = each.value.max_size
    min_size     = each.value.min_size
  }

  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  dynamic "update_config" {
    for_each = each.value.update_config == null ? [] : [each.value.update_config]
    content {
      max_unavailable            = update_config.value.max_unavailable
      max_unavailable_percentage = update_config.value.max_unavailable_percentage
    }
  }

  labels = each.value.labels

  tags = merge(
    local.node_group_tags[each.key],
    { ClusterName = aws_eks_cluster.clusters[each.value.cluster_name].name }
  )

  # Explicit dependencies to avoid race conditions during creation and destruction
  depends_on = [
    aws_iam_role_policy_attachment.node_eks_worker_node_policy,
    aws_iam_role_policy_attachment.node_eks_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_read_only,
    aws_eks_cluster.clusters, # Ensure clusters are fully created before node groups
    aws_iam_role.node         # Ensure roles are fully created before node groups
  ]

  lifecycle {
    # Prevent replacement of node groups when certain changes occur
    create_before_destroy = true
    ignore_changes = [
      scaling_config[0].desired_size, # Allow autoscaling to manage desired size

      # Add other attributes that shouldn't trigger replacement if needed
      # For example, labels and tags might be updated outside Terraform.
      # Ignoring tags only matters with immediately_apply_lt_changes = false:
      # under the default keeper, a tag change is also a launch template
      # change, so it gives a new pet and replaces the group anyway.
      labels,
      tags
    ]

    # Validate taint effect values
    precondition {
      condition = alltrue([
        for taint in each.value.taints :
        contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], taint.effect)
      ])
      error_message = "Taint effect must be one of: NO_SCHEDULE, PREFER_NO_SCHEDULE, or NO_EXECUTE."
    }

    # Add precondition to check for required values
    precondition {
      condition     = length(coalesce(each.value.subnet_ids, var.subnet_ids)) > 0
      error_message = "At least one subnet must be provided for the node group."
    }

    # Add precondition to validate instance types are valid
    precondition {
      condition     = length(each.value.instance_types) > 0
      error_message = "At least one instance type must be specified."
    }
  }

  # Add a timeouts block to extend default timeouts for creation/deletion
  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

# IAM Role for EKS Node Group
resource "aws_iam_role" "node" {
  for_each = local.clusters

  name = "${var.tags["Environment"]}-${each.key}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {}),
    {
      Name = "${var.tags["Environment"]}-${each.key}-node-role"
    }
  )
}

resource "aws_iam_role_policy_attachment" "node_eks_worker_node_policy" {
  for_each = local.clusters

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node[each.key].name
}

resource "aws_iam_role_policy_attachment" "node_eks_cni_policy" {
  for_each = local.clusters

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node[each.key].name
}

resource "aws_iam_role_policy_attachment" "node_ecr_read_only" {
  for_each = local.clusters

  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node[each.key].name
}

# IRSA (IAM Roles for Service Accounts)
resource "aws_iam_openid_connect_provider" "oidc_provider" {
  for_each = local.clusters

  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks[each.key].certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.clusters[each.key].identity[0].oidc[0].issuer

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {}),
    {
      Name        = "${var.tags["Environment"]}-${each.key}-oidc"
      ClusterName = "${var.tags["Environment"]}-${each.key}"
    }
  )

  lifecycle {
    # Thumbprint list may be updated by AWS, but we want to trigger rotation only
    # when URL changes to avoid needless redeployments. To force rotation, update the URL
    # or replace the resource.
    ignore_changes = [thumbprint_list]
  }
}

# AWS caller identity data source moved to top of file

data "tls_certificate" "eks" {
  for_each = local.clusters

  url = aws_eks_cluster.clusters[each.key].identity[0].oidc[0].issuer

  # Add retry logic for certificate lookup which can sometimes fail
  lifecycle {
    # Add explicit error messages to help with troubleshooting
    postcondition {
      condition     = length(self.certificates) > 0
      error_message = "Failed to retrieve OIDC certificates for cluster ${each.key}. Check if the cluster API is accessible."
    }
  }
}

# Renamed to snake_case (tflint terraform_naming_convention); keeps existing state.
moved {
  from = aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy
  to   = aws_iam_role_policy_attachment.cluster_eks_cluster_policy
}

moved {
  from = aws_iam_role_policy_attachment.cluster_AmazonEKSVPCResourceController
  to   = aws_iam_role_policy_attachment.cluster_eks_vpc_resource_controller
}

moved {
  from = aws_iam_role_policy_attachment.node_AmazonEKSWorkerNodePolicy
  to   = aws_iam_role_policy_attachment.node_eks_worker_node_policy
}

moved {
  from = aws_iam_role_policy_attachment.node_AmazonEKS_CNI_Policy
  to   = aws_iam_role_policy_attachment.node_eks_cni_policy
}

moved {
  from = aws_iam_role_policy_attachment.node_AmazonEC2ContainerRegistryReadOnly
  to   = aws_iam_role_policy_attachment.node_ecr_read_only
}
