output "cluster_ids" {
  value       = { for k, v in aws_eks_cluster.clusters : k => v.id }
  description = "Map of cluster names to cluster IDs"
}

output "cluster_arns" {
  value       = { for k, v in aws_eks_cluster.clusters : k => v.arn }
  description = "Map of cluster names to cluster ARNs"
}

output "cluster_endpoints" {
  value       = { for k, v in aws_eks_cluster.clusters : k => v.endpoint }
  description = "Map of cluster names to cluster endpoints"
}

output "cluster_ca_data" {
  value       = { for k, v in aws_eks_cluster.clusters : k => v.certificate_authority[0].data }
  description = "Map of cluster names to cluster CA certificate data"
}

output "node_group_arns" {
  value       = { for k, v in aws_eks_node_group.node_groups : k => v.arn }
  description = "Map of node group names to node group ARNs"
}

output "oidc_provider_arns" {
  value       = { for k, v in aws_iam_openid_connect_provider.oidc_provider : k => v.arn }
  description = "Map of cluster names to OIDC provider ARNs"
}

output "cluster_security_group_ids" {
  value       = { for k, v in aws_eks_cluster.clusters : k => v.vpc_config[0].cluster_security_group_id }
  description = "Map of cluster names to cluster security group IDs"
}

output "node_role_arns" {
  value       = { for k, v in aws_iam_role.node : k => v.arn }
  description = "Map of cluster names to node IAM role ARNs"
}

# Scalar outputs for the instance's single cluster, named as in Cloud Posse's
# eks/cluster component (the issuer ARN as in terraform-aws-eks-cluster), so a
# consumer reads `!terraform.state eks/<instance> .eks_cluster_id` without knowing
# the cluster's map key. The map outputs above stay for multi-cluster instances.
#
# one() never picks among several clusters: with no enabled cluster these are null,
# and with more than one the plan fails ("must be a list, set, or tuple value with
# either zero or one elements"). A multi-cluster instance must read the map outputs.

output "eks_cluster_id" {
  value       = one([for c in aws_eks_cluster.clusters : c.name])
  description = "Name of the instance's only EKS cluster (null without a cluster; the plan fails with more than one)"
}

output "eks_cluster_arn" {
  value       = one([for c in aws_eks_cluster.clusters : c.arn])
  description = "ARN of the instance's only EKS cluster (null without a cluster; the plan fails with more than one)"
}

output "eks_cluster_endpoint" {
  value       = one([for c in aws_eks_cluster.clusters : c.endpoint])
  description = "Kubernetes API server URL (https://...) of the instance's only EKS cluster (null without a cluster; the plan fails with more than one)"
}

output "eks_cluster_certificate_authority_data" {
  value       = one([for c in aws_eks_cluster.clusters : c.certificate_authority[0].data])
  description = "Base64-encoded CA certificate of the instance's only EKS cluster, as EKS returns it; base64decode() before use (null without a cluster; the plan fails with more than one)"
}

output "eks_cluster_identity_oidc_issuer" {
  value       = one([for c in aws_eks_cluster.clusters : c.identity[0].oidc[0].issuer])
  description = "OIDC issuer URL, including https://, of the instance's only EKS cluster (null without a cluster; the plan fails with more than one)"
}

output "eks_cluster_identity_oidc_issuer_arn" {
  value       = one([for p in aws_iam_openid_connect_provider.oidc_provider : p.arn])
  description = "ARN of the IAM OIDC provider of the instance's only EKS cluster, for IRSA trust policies (null without a cluster; the plan fails with more than one)"
}