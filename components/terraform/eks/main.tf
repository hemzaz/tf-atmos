# One EKS cluster per component instance, as in
# cloudposse-terraform-components/aws-eks-cluster: every resource is
# `count = local.enabled ? 1 : 0` (or a map of node groups), and the outputs
# are Cloud Posse's scalar outputs.

# Add AWS caller identity data source for IAM policies
data "aws_caller_identity" "current" {}

locals {
  enabled     = var.enabled
  environment = var.tags["Environment"]

  # Every name is "<Environment>-<name>", the repo's name_prefix convention.
  # var.name must not repeat the Environment (see its validation), so the
  # prod cluster is "production-main", not "production-production-main".
  name_prefix            = "${local.environment}-${var.name}"
  cluster_name           = local.name_prefix
  cluster_log_group_name = "/aws/eks/${local.cluster_name}/cluster"

  # `name_base` is the node group's name without its random_pet suffix:
  # "<cluster>-<node group>". The node group name validation on
  # var.node_groups repeats this expression because a validation cannot read
  # locals; keep the two in sync.
  node_groups = local.enabled ? {
    for k, ng in var.node_groups : k => merge(ng, {
      name_base = "${local.name_prefix}-${k}"
    }) if ng.enabled
  } : {}

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
      # A device's own ebs.kms_key_id always wins; otherwise fall back to
      # var.node_group_ebs_kms_key_id (kms/main, when the stack sets it) so
      # every EBS volume a node group launches is encrypted with a key this
      # repo controls rather than the AWS managed aws/ebs key. Only when the
      # device is actually encrypted: EC2 rejects a launch template that sets
      # KmsKeyId on a device with encrypted = false.
      block_device_mappings = {
        for device_name, device in ng.block_device_map : device_name => (
          device.ebs == null ? device : merge(device, {
            ebs = merge(device.ebs, {
              kms_key_id = device.ebs.kms_key_id != null ? device.ebs.kms_key_id : (
                device.ebs.encrypted && var.node_group_ebs_kms_key_id != "" ? var.node_group_ebs_kms_key_id : null
              )
            })
          })
        )
      }
      tag_specifications = ["instance", "volume", "network-interface"]
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

  # The caller's key when set, otherwise the key this component creates. Both
  # the cluster's secrets (encryption_config below) and its control-plane log
  # group (aws_cloudwatch_log_group.default) use this same key.
  kms_key_arn = var.cluster_encryption_config_kms_key_id != "" ? var.cluster_encryption_config_kms_key_id : one(aws_kms_key.cluster[*].arn)
}

resource "aws_cloudwatch_log_group" "default" {
  # checkov:skip=CKV_AWS_338:Retention is a per-stack cost decision, not a module one. Only prod pins cluster_log_retention_period (90); dev and staging keep the 7-day default, so raising the default to the year this check wants would multiply their audit-log spend without anyone deciding to. The repo accepts the same finding on its other log groups.
  count = local.enabled ? 1 : 0

  name              = local.cluster_log_group_name
  retention_in_days = var.cluster_log_retention_period
  # The caller's key when one is given (kms/main's allow_cloudwatch_logs
  # already grants every log group in this account and region), otherwise the
  # component's own key, the one already encrypting the cluster's secrets.
  kms_key_id = local.kms_key_arn

  tags = merge(var.tags, {
    Name        = local.cluster_log_group_name
    Environment = local.environment
    Component   = "eks"
    ClusterName = local.cluster_name
  })
}

#trivy:ignore:AWS-0040 Public endpoint is off unless cluster_endpoint_public_access = true
resource "aws_eks_cluster" "default" {
  #checkov:skip=CKV_AWS_38:Public endpoint is off unless cluster_endpoint_public_access = true
  count = local.enabled ? 1 : 0

  name     = local.cluster_name
  role_arn = aws_iam_role.default[0].arn
  version  = var.cluster_kubernetes_version

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = var.cluster_endpoint_private_access
    endpoint_public_access  = var.cluster_endpoint_public_access
    public_access_cidrs     = var.public_access_cidrs
    security_group_ids      = var.associated_security_group_ids
  }

  encryption_config {
    provider {
      key_arn = local.kms_key_arn
    }
    resources = ["secrets"]
  }

  enabled_cluster_log_types = var.enabled_cluster_log_types

  # Add timeouts to allow for longer cluster creation/update
  timeouts {
    create = "45m"
    update = "60m"
    delete = "30m"
  }

  tags = merge(var.tags, {
    Name        = local.cluster_name
    Environment = local.environment
    Component   = "eks"
    ClusterName = local.cluster_name
    CreatedBy   = "terraform"
  })

  depends_on = [
    aws_iam_role_policy_attachment.amazon_eks_cluster_policy,
    aws_iam_role_policy_attachment.amazon_eks_vpc_resource_controller,
    aws_cloudwatch_log_group.default,
  ]

  # prevent_destroy only accepts literals, so production protection uses EKS deletion protection instead
  deletion_protection = var.enable_cluster_protection && contains(["prod", "production"], lower(local.environment))

  # The endpoint rules are variable validations on cluster_endpoint_public_access
  # and public_access_cidrs, so they also run in a credential-less plan.
}

# The component's own key, created only when the caller supplies none of its
# own: local.kms_key_arn then routes both the cluster's secrets
# (encryption_config) and its control-plane log group to this key. When a
# caller key is given (e.g. kms/main, whose allow_cloudwatch_logs already
# grants every log group in this account and region), that key encrypts both
# instead and this component key would sit completely unused, so it is not
# created at all.
resource "aws_kms_key" "cluster" {
  count = local.enabled && var.cluster_encryption_config_kms_key_id == "" ? 1 : 0

  description             = "KMS key for EKS ${local.cluster_name} secrets and control-plane log encryption"
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
        # Required for the log group to use this key. Without it, CloudWatch
        # Logs cannot write and AWS rejects the key association outright, so a
        # missing statement fails the apply rather than silently dropping logs.
        # Scoped by encryption context to this cluster's log group.
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
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:${local.cluster_log_group_name}"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name        = "${local.cluster_name}-kms-key"
    Environment = local.environment
    ClusterName = local.cluster_name
    ManagedBy   = "terraform"
  })
}

# IAM Role for the EKS cluster
resource "aws_iam_role" "default" {
  count = local.enabled ? 1 : 0

  name = "${local.cluster_name}-cluster-role"

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

  tags = merge(var.tags, { Name = "${local.cluster_name}-cluster-role" })
}

resource "aws_iam_role_policy_attachment" "amazon_eks_cluster_policy" {
  count = local.enabled ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.default[0].name
}

resource "aws_iam_role_policy_attachment" "amazon_eks_vpc_resource_controller" {
  count = local.enabled ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.default[0].name
}

# EKS Node Groups
# A launch template is the only way to control root-volume encryption and
# volume type on a managed node group; `aws_eks_node_group` exposes neither.
# One template per node group, because block_device_map is per node group.
# Deliberately no `image_id`/`user_data`: leaving them unset lets EKS supply the
# AMI matching `ami_type` and inject its own bootstrap script.
resource "aws_launch_template" "default" {
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
  # 26-character unique suffix). name_base is capped below 63 on
  # var.node_groups, well inside that limit.
  name_prefix = "${each.value.name_base}-"
  description = "Managed node group ${each.key} in cluster ${local.cluster_name}"

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
# the prod names run longer.
resource "random_pet" "default" {
  for_each = local.node_groups

  # The pet is Name (length 1), Adjective-Name (2), or one Adverb per word
  # beyond two, then Adjective-Name (3+). With the pinned random provider,
  # names and adjectives are at most 8 characters and adverbs at most 10.
  # The name_base validation on var.node_groups budgets exactly that, "-" included.
  length    = each.value.random_pet_length
  separator = "-"

  keepers = {
    node_role_arn  = aws_iam_role.node[0].arn
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
      : aws_launch_template.default[each.key].id
    )
  }
}

resource "aws_eks_node_group" "default" {
  for_each = local.node_groups

  cluster_name = aws_eks_cluster.default[0].name
  # EKS allows 63 characters. The validation on var.node_groups caps name_base
  # at 63 minus the longest possible "-<pet>", so the name always fits. The
  # pet is unknown until apply, so the cap is the only plan-time check.
  node_group_name = "${each.value.name_base}-${random_pet.default[each.key].id}"
  node_role_arn   = aws_iam_role.node[0].arn
  subnet_ids      = coalesce(each.value.subnet_ids, var.subnet_ids)

  instance_types = each.value.instance_types
  ami_type       = each.value.ami_type
  capacity_type  = each.value.capacity_type
  # No `disk_size`: AWS rejects a node group that sets it while a launch
  # template is attached. Size lives in block_device_map instead.

  launch_template {
    id      = aws_launch_template.default[each.key].id
    version = aws_launch_template.default[each.key].latest_version
  }

  scaling_config {
    desired_size = each.value.desired_group_size
    max_size     = each.value.max_group_size
    min_size     = each.value.min_group_size
  }

  dynamic "taint" {
    for_each = each.value.kubernetes_taints
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

  labels = each.value.kubernetes_labels

  tags = merge(local.node_group_tags[each.key], { ClusterName = aws_eks_cluster.default[0].name })

  # Explicit dependencies to avoid race conditions during creation and destruction
  depends_on = [
    aws_iam_role_policy_attachment.amazon_eks_worker_node_policy,
    aws_iam_role_policy_attachment.amazon_eks_cni_policy,
    aws_iam_role_policy_attachment.amazon_ec2_container_registry_read_only,
  ]

  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      scaling_config[0].desired_size, # Allow autoscaling to manage desired size

      # Labels and tags might be updated outside Terraform. Ignoring tags only
      # matters with immediately_apply_lt_changes = false: under the default
      # keeper, a tag change is also a launch template change, so it gives a
      # new pet and replaces the group anyway.
      labels,
      tags
    ]

    precondition {
      condition     = length(each.value.instance_types) > 0
      error_message = "At least one instance type must be specified."
    }
  }

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

# IAM Role for the EKS node groups
resource "aws_iam_role" "node" {
  count = local.enabled ? 1 : 0

  name = "${local.cluster_name}-node-role"

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

  tags = merge(var.tags, { Name = "${local.cluster_name}-node-role" })
}

resource "aws_iam_role_policy_attachment" "amazon_eks_worker_node_policy" {
  count = local.enabled ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node[0].name
}

resource "aws_iam_role_policy_attachment" "amazon_eks_cni_policy" {
  count = local.enabled ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node[0].name
}

resource "aws_iam_role_policy_attachment" "amazon_ec2_container_registry_read_only" {
  count = local.enabled ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node[0].name
}

# IRSA (IAM Roles for Service Accounts)
resource "aws_iam_openid_connect_provider" "default" {
  count = local.enabled ? 1 : 0

  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster[0].certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.default[0].identity[0].oidc[0].issuer

  tags = merge(var.tags, {
    Name        = "${local.cluster_name}-oidc"
    ClusterName = local.cluster_name
  })

  lifecycle {
    # Thumbprint list may be updated by AWS, but we want to trigger rotation only
    # when URL changes to avoid needless redeployments. To force rotation, update the URL
    # or replace the resource.
    ignore_changes = [thumbprint_list]
  }
}

data "tls_certificate" "cluster" {
  count = local.enabled ? 1 : 0

  url = aws_eks_cluster.default[0].identity[0].oidc[0].issuer

  lifecycle {
    postcondition {
      condition     = length(self.certificates) > 0
      error_message = "Failed to retrieve OIDC certificates for cluster ${local.cluster_name}. Check if the cluster API is accessible."
    }
  }
}
