output "policy_id" {
  value       = try(aws_organizations_policy.this[0].id, null)
  description = "The ID of the Service Control Policy"
}

output "policy_arn" {
  value       = try(aws_organizations_policy.this[0].arn, null)
  description = "The ARN of the Service Control Policy"
}

output "policy_name" {
  value       = try(aws_organizations_policy.this[0].name, null)
  description = "The name of the Service Control Policy"
}

output "target_ids" {
  value       = keys(aws_organizations_policy_attachment.this)
  description = "The target IDs the SCP is attached to"
}

output "attachment_ids" {
  value       = { for k, v in aws_organizations_policy_attachment.this : k => v.id }
  description = "Map of target IDs to policy attachment IDs"
}

output "attached" {
  value       = length(aws_organizations_policy_attachment.this) > 0
  description = "Whether the SCP was attached to any targets"
}
