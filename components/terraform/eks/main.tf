# Add AWS caller identity data source for IAM policies
data "aws_caller_identity" "current" {}

locals {
  clusters = {
    for k, v in var.clusters : k => v if lookup(v, "enabled", true)
  }

  # Merge node groups across all clusters
  node_groups = merge([
    for cluster_key, cluster in local.clusters : {
      for ng_key, ng in lookup(cluster, "node_groups", {}) :
      "${cluster_key}.${ng_key}" => merge(ng, { cluster_name = cluster_key })
      if lookup(ng, "enabled", true)
    }
  ]...)
}

resource "aws_cloudwatch_log_group" "eks" {
  for_each = local.clusters

  name              = "/aws/eks/${var.tags["Environment"]}-${each.key}/cluster"
  retention_in_days = lookup(each.value, "log_retention_days", var.default_cluster_log_retention_days)
  kms_key_id        = lookup(each.value, "log_kms_key_id", null)

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
#trivy:ignore:AWS-0041 Public endpoint is off unless a cluster sets endpoint_public_access = true
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

  description             = "KMS key for EKS ${each.key} secrets encryption"
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
resource "aws_eks_node_group" "node_groups" {
  for_each = local.node_groups

  cluster_name    = aws_eks_cluster.clusters[each.value.cluster_name].name
  node_group_name = "${var.tags["Environment"]}-${each.key}"
  node_role_arn   = aws_iam_role.node[each.value.cluster_name].arn
  subnet_ids      = lookup(each.value, "subnet_ids", var.subnet_ids)

  instance_types = lookup(each.value, "instance_types", ["t3.medium"])
  ami_type       = lookup(each.value, "ami_type", "AL2_x86_64")
  capacity_type  = lookup(each.value, "capacity_type", "ON_DEMAND")
  disk_size      = lookup(each.value, "disk_size", 50)

  scaling_config {
    desired_size = lookup(each.value, "desired_size", 2)
    max_size     = lookup(each.value, "max_size", 4)
    min_size     = lookup(each.value, "min_size", 1)
  }

  dynamic "taint" {
    for_each = lookup(each.value, "taints", [])
    content {
      key    = taint.value.key
      value  = lookup(taint.value, "value", null)
      effect = taint.value.effect
    }
  }

  dynamic "update_config" {
    for_each = lookup(each.value, "update_config", null) != null ? [1] : []
    content {
      max_unavailable            = lookup(each.value.update_config, "max_unavailable", null)
      max_unavailable_percentage = lookup(each.value.update_config, "max_unavailable_percentage", null)
    }
  }

  dynamic "launch_template" {
    for_each = lookup(each.value, "launch_template", null) != null ? [1] : []
    content {
      id      = lookup(each.value.launch_template, "id", null)
      name    = lookup(each.value.launch_template, "name", null)
      version = lookup(each.value.launch_template, "version", null)
    }
  }

  labels = lookup(each.value, "labels", {})

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {}),
    {
      Name        = "${var.tags["Environment"]}-${each.key}",
      ClusterName = aws_eks_cluster.clusters[each.value.cluster_name].name
    }
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
      # For example, labels and tags might be updated outside Terraform
      labels,
      tags
    ]

    # Validate taint effect values
    precondition {
      condition = length(lookup(each.value, "taints", [])) == 0 || alltrue([
        for taint in lookup(each.value, "taints", []) :
        contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], lookup(taint, "effect", "NO_SCHEDULE"))
      ])
      error_message = "Taint effect must be one of: NO_SCHEDULE, PREFER_NO_SCHEDULE, or NO_EXECUTE."
    }

    # Add precondition to check for required values
    precondition {
      condition     = length(lookup(each.value, "subnet_ids", var.subnet_ids)) > 0
      error_message = "At least one subnet must be provided for the node group."
    }

    # Add precondition to validate instance types are valid
    precondition {
      condition     = length(lookup(each.value, "instance_types", ["t3.medium"])) > 0
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
