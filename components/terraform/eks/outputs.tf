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