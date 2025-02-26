output "addon_arns" {
  value       = { for k, v in aws_eks_addon.addons : k => v.arn }
  description = "Map of addon names to addon ARNs"
}

output "helm_release_statuses" {
  value       = { for k, v in helm_release.releases : k => v.status }
  description = "Map of Helm release names to statuses"
}

output "service_account_role_arns" {
  value       = { for k, v in aws_iam_role.service_account : k => v.arn }
  description = "Map of service account names to role ARNs"
}