output "addon_arns" {
  value       = { for k, v in merge(aws_eks_addon.core, aws_eks_addon.addons) : k => v.arn }
  description = "Map of addon names to addon ARNs"
}

output "helm_release_statuses" {
  value       = { for k, v in helm_release.releases : k => v.status }
  description = "Map of Helm release names to statuses"
}

output "addon_role_arns" {
  value       = { for k, v in aws_iam_role.addon : k => v.arn }
  description = "IRSA role ARNs of the enable_* add-ons, keyed <cluster key>.<add-on>"
}

output "addon_release_statuses" {
  value       = { for k, v in merge(helm_release.aws_load_balancer_controller, helm_release.addon) : k => v.status }
  description = "Helm release statuses of the enable_* add-ons, keyed <cluster key>.<add-on>"
}

output "container_insights_role_arns" {
  value       = { for k, v in aws_iam_role.container_insights : k => v.arn }
  description = "IRSA role ARNs of the Container Insights add-on, keyed by cluster key"
}

output "container_insights_log_group_names" {
  value       = { for k, v in aws_cloudwatch_log_group.container_insights : k => v.name }
  description = "Container Insights log groups, keyed <cluster key>.<application|dataplane|host|performance>"
}

output "service_account_role_arns" {
  value       = { for k, v in aws_iam_role.service_account : k => v.arn }
  description = "Map of service account names to role ARNs"
}