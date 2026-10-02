output "account_id" {
  description = "AWS account ID Inspector is enabled in (null when enabled is false). security-monitoring routes Inspector findings while it is set"
  value       = var.enabled ? one(aws_inspector2_enabler.main[0].account_ids) : null
}

output "enabled_resource_types" {
  description = "Resource types Inspector scans in this account (EC2, ECR, LAMBDA, LAMBDA_CODE); empty when enabled is false"
  value       = var.enabled ? sort(tolist(aws_inspector2_enabler.main[0].resource_types)) : tolist([])
}
