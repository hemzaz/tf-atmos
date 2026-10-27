output "organizational_unit_id" {
  value       = try(aws_organizations_organizational_unit.this[0].id, null)
  description = "The ID of the Organizational Unit"
}

output "organizational_unit_arn" {
  value       = try(aws_organizations_organizational_unit.this[0].arn, null)
  description = "The ARN of the Organizational Unit"
}

output "organizational_unit_name" {
  value       = try(aws_organizations_organizational_unit.this[0].name, null)
  description = "The name of the Organizational Unit"
}

output "parent_id" {
  value       = var.parent_id
  description = "The parent ID of the Organizational Unit"
}

output "accounts" {
  value       = try(aws_organizations_organizational_unit.this[0].accounts, [])
  description = "List of accounts in this Organizational Unit"
}
