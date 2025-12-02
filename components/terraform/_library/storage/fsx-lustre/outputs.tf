output "file_system_id" {
  description = "ID of the FSx Lustre file system"
  value       = aws_fsx_lustre_file_system.this.id
}

output "file_system_arn" {
  description = "ARN of the FSx Lustre file system"
  value       = aws_fsx_lustre_file_system.this.arn
}

output "file_system_dns_name" {
  description = "DNS name of the FSx Lustre file system"
  value       = aws_fsx_lustre_file_system.this.dns_name
}

output "mount_name" {
  description = "Mount name for the FSx Lustre file system"
  value       = aws_fsx_lustre_file_system.this.mount_name
}

output "network_interface_ids" {
  description = "List of network interface IDs"
  value       = aws_fsx_lustre_file_system.this.network_interface_ids
}

output "vpc_id" {
  description = "VPC ID where the file system is located"
  value       = aws_fsx_lustre_file_system.this.vpc_id
}

output "data_repository_association_ids" {
  description = "Map of data repository association names to IDs"
  value       = { for k, v in aws_fsx_data_repository_association.this : k => v.id }
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for data repository (if created)"
  value       = var.create_s3_bucket ? aws_s3_bucket.data_repository[0].id : null
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for data repository (if created)"
  value       = var.create_s3_bucket ? aws_s3_bucket.data_repository[0].arn : null
}

output "kms_key_id" {
  description = "ID of the KMS key used for encryption"
  value       = var.enable_encryption ? (var.kms_key_id != null ? var.kms_key_id : aws_kms_key.fsx[0].id) : null
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption"
  value       = var.enable_encryption ? (var.kms_key_id != null ? var.kms_key_id : aws_kms_key.fsx[0].arn) : null
}

output "log_group_name" {
  description = "Name of the CloudWatch log group (if created)"
  value       = var.enable_logging && var.log_destination_arn == null ? aws_cloudwatch_log_group.fsx[0].name : null
}

output "mount_command" {
  description = "Example mount command for FSx Lustre file system"
  value       = "sudo mount -t lustre -o noatime,flock ${aws_fsx_lustre_file_system.this.dns_name}@tcp:/${aws_fsx_lustre_file_system.this.mount_name} /mnt/fsx"
}
