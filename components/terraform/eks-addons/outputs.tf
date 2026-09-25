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

output "service_account_role_arns" {
  value       = { for k, v in aws_iam_role.service_account : k => v.arn }
  description = "Map of service account names to role ARNs"
}