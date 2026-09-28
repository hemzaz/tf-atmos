# Names and expressions as in cloudposse/terraform-aws-eks-cluster
# (one(<resource>[*].<attr>)) and cloudposse-terraform-components/aws-eks-cluster.
# Every value is null (or an empty list) when enabled = false.

output "eks_cluster_id" {
  description = "The name of the cluster"
  # The provider sets id to the name; `name` says so (Cloud Posse reads `id`).
  value = one(aws_eks_cluster.default[*].name)
}

output "eks_cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the cluster"
  value       = one(aws_eks_cluster.default[*].arn)
}

output "eks_cluster_endpoint" {
  description = "The endpoint for the Kubernetes API server"
  value       = one(aws_eks_cluster.default[*].endpoint)
}

output "eks_cluster_version" {
  description = "The Kubernetes server version of the cluster"
  value       = one(aws_eks_cluster.default[*].version)
}

output "eks_cluster_certificate_authority_data" {
  description = "The Kubernetes cluster certificate authority data, base64-encoded as EKS returns it"
  value       = one(aws_eks_cluster.default[*].certificate_authority[0].data)
}

output "eks_cluster_identity_oidc_issuer" {
  description = "The OIDC Identity issuer URL for the cluster, including https://"
  value       = one(aws_eks_cluster.default[*].identity[0].oidc[0].issuer)
}

output "eks_cluster_identity_oidc_issuer_arn" {
  description = "The OIDC Identity issuer ARN for the cluster, for IRSA trust policies"
  value       = one(aws_iam_openid_connect_provider.default[*].arn)
}

output "eks_cluster_managed_security_group_id" {
  description = "Security group EKS created for the cluster"
  value       = one(aws_eks_cluster.default[*].vpc_config[0].cluster_security_group_id)
}

output "eks_node_group_arns" {
  description = "List of all the node group ARNs in the cluster"
  value       = [for ng in aws_eks_node_group.default : ng.arn]
}

output "eks_node_group_ids" {
  description = "EKS Cluster name and EKS Node Group name separated by a colon"
  value       = [for ng in aws_eks_node_group.default : ng.id]
}

output "eks_managed_node_workers_role_arns" {
  description = "List of ARNs for workers in managed node groups"
  value       = aws_iam_role.node[*].arn
}

output "cloudwatch_log_group_name" {
  description = "The name of the log group for the cluster's control plane logs"
  value       = one(aws_cloudwatch_log_group.default[*].name)
}

# cloudposse/terraform-aws-eks-cluster: eks_addons_versions. Only vpc-cni is
# managed here; eks-addons owns the other addons.
output "eks_addons_versions" {
  description = "Map of enabled EKS Addons names and versions"
  value       = { for addon in aws_eks_addon.vpc_cni : addon.addon_name => addon.addon_version }
}

# cloudposse/terraform-aws-eks-iam-role's service_account_role_arn, for the
# vpc-cni role (addons.tf).
output "vpc_cni_service_account_role_arn" {
  description = "IRSA role of the vpc-cni addon's aws-node service account, whether created here or passed in vpc_cni_addon.service_account_role_arn"
  value       = local.vpc_cni_service_account_role_arn
}

# Cloud Posse has no access-entry output; this lists who can reach the
# Kubernetes API besides the managed node groups.
output "eks_access_entry_principal_arns" {
  description = "IAM principals with an EKS access entry created by this component (access_entry_map keys, then access_entries)"
  value       = concat([for e in aws_eks_access_entry.map : e.principal_arn], [for e in aws_eks_access_entry.standard : e.principal_arn])
}
