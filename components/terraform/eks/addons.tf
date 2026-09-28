# The `vpc-cni` EKS managed addon with its own IRSA role, as
# cloudposse-terraform-components/aws-eks-cluster does in addons.tf
# (`module "vpc_cni_eks_iam_role"` for the kube-system/aws-node service
# account, `aws_iam_role_policy_attachment.vpc_cni` attaching
# AmazonEKS_CNI_Policy, and the role passed as the addon's
# `service_account_role_arn`, unless the addon entry names its own role).
#
# The node role does not carry AmazonEKS_CNI_Policy (AWS's recommendation,
# docs.aws.amazon.com/eks/latest/userguide/cni-iam-role.html), so this addon is
# what gives aws-node its EC2 permissions. It is created before the node
# groups (see aws_eks_node_group.default depends_on): the first nodes then
# start aws-node with the IRSA role already in place, and pod networking
# works in the same apply that creates the cluster.
#
# Divergence from Cloud Posse, whose addons default to installing after the
# node groups (addons_depends_on = true): CoreDNS needs nodes to go ACTIVE,
# but vpc-cni does not, and without the node-role policy the nodes need it.
# vpc-cni is always managed here, and only here: do not also list it in an
# eks-addons instance's `addons`.

locals {
  vpc_cni_sa_needed = local.enabled && var.vpc_cni_addon.service_account_role_arn == null
  vpc_cni_service_account_role_arn = (
    var.vpc_cni_addon.service_account_role_arn != null ? var.vpc_cni_addon.service_account_role_arn : one(aws_iam_role.vpc_cni[*].arn)
  )
  eks_oidc_issuer_host = local.enabled ? replace(aws_eks_cluster.default[0].identity[0].oidc[0].issuer, "https://", "") : ""
}

resource "aws_iam_role" "vpc_cni" {
  count = local.vpc_cni_sa_needed ? 1 : 0

  name = "${local.cluster_name}-vpc-cni-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.default[0].arn
        }
        Condition = {
          StringEquals = {
            "${local.eks_oidc_issuer_host}:sub" = "system:serviceaccount:kube-system:aws-node"
            "${local.eks_oidc_issuer_host}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, { Name = "${local.cluster_name}-vpc-cni-role" })
}

resource "aws_iam_role_policy_attachment" "vpc_cni" {
  count = local.vpc_cni_sa_needed ? 1 : 0

  role       = aws_iam_role.vpc_cni[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_eks_addon" "vpc_cni" {
  count = local.enabled ? 1 : 0

  cluster_name         = aws_eks_cluster.default[0].name
  addon_name           = "vpc-cni"
  addon_version        = var.vpc_cni_addon.addon_version
  configuration_values = var.vpc_cni_addon.configuration_values
  # EKS installs a self-managed aws-node with every new cluster; OVERWRITE
  # adopts it into the managed addon.
  resolve_conflicts_on_create = var.vpc_cni_addon.resolve_conflicts_on_create
  resolve_conflicts_on_update = var.vpc_cni_addon.resolve_conflicts_on_update
  service_account_role_arn    = local.vpc_cni_service_account_role_arn
  preserve                    = var.vpc_cni_addon.preserve

  tags = merge(var.tags, { Name = "${local.cluster_name}-vpc-cni" })

  timeouts {
    create = var.vpc_cni_addon.create_timeout
    update = var.vpc_cni_addon.update_timeout
    delete = var.vpc_cni_addon.delete_timeout
  }

  depends_on = [aws_iam_role_policy_attachment.vpc_cni]
}
