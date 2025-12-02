output "file_system_id" {
  description = "ID of the EFS file system"
  value       = aws_efs_file_system.this.id
}

output "file_system_arn" {
  description = "ARN of the EFS file system"
  value       = aws_efs_file_system.this.arn
}

output "file_system_dns_name" {
  description = "DNS name of the EFS file system"
  value       = aws_efs_file_system.this.dns_name
}

output "mount_target_ids" {
  description = "Map of subnet IDs to mount target IDs"
  value       = { for k, v in aws_efs_mount_target.this : k => v.id }
}

output "mount_target_dns_names" {
  description = "Map of subnet IDs to mount target DNS names"
  value       = { for k, v in aws_efs_mount_target.this : k => v.dns_name }
}

output "mount_target_network_interface_ids" {
  description = "Map of subnet IDs to mount target network interface IDs"
  value       = { for k, v in aws_efs_mount_target.this : k => v.network_interface_id }
}

output "access_point_ids" {
  description = "Map of access point names to IDs"
  value       = { for k, v in aws_efs_access_point.this : k => v.id }
}

output "access_point_arns" {
  description = "Map of access point names to ARNs"
  value       = { for k, v in aws_efs_access_point.this : k => v.arn }
}

output "kms_key_id" {
  description = "ID of the KMS key used for encryption"
  value       = var.enable_encryption ? (var.kms_key_id != null ? var.kms_key_id : aws_kms_key.efs[0].id) : null
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption"
  value       = var.enable_encryption ? (var.kms_key_id != null ? var.kms_key_id : aws_kms_key.efs[0].arn) : null
}

output "mount_command" {
  description = "Example mount command for EFS file system"
  value       = "sudo mount -t efs -o tls ${aws_efs_file_system.this.id}:/ /mnt/efs"
}
