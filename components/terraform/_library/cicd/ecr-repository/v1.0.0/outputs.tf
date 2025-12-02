################################################################################
# Repository Outputs
################################################################################

output "repository_id" {
  description = "ID of the ECR repository"
  value       = aws_ecr_repository.this.id
}

output "repository_arn" {
  description = "ARN of the ECR repository"
  value       = aws_ecr_repository.this.arn
}

output "repository_name" {
  description = "Name of the ECR repository"
  value       = aws_ecr_repository.this.name
}

output "repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.this.repository_url
}

output "registry_id" {
  description = "Registry ID where the repository was created"
  value       = aws_ecr_repository.this.registry_id
}

################################################################################
# Console URL Outputs
################################################################################

output "repository_console_url" {
  description = "URL to the ECR repository console"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/ecr/repositories/private/${local.account_id}/${var.name}"
}

################################################################################
# Scanning Outputs
################################################################################

output "scan_on_push_enabled" {
  description = "Whether scan on push is enabled"
  value       = var.enable_scan_on_push
}

output "scan_type" {
  description = "Type of scanning configured"
  value       = var.scan_type
}

################################################################################
# CloudWatch Alarm Outputs
################################################################################

output "high_severity_alarm_arn" {
  description = "ARN of the high severity findings alarm"
  value       = var.enable_cloudwatch_metrics && var.enable_scan_on_push ? aws_cloudwatch_metric_alarm.image_scan_findings_high[0].arn : null
}

output "low_pull_count_alarm_arn" {
  description = "ARN of the low pull count alarm"
  value       = var.enable_cloudwatch_metrics ? aws_cloudwatch_metric_alarm.repository_pull_count[0].arn : null
}

################################################################################
# Replication Outputs
################################################################################

output "replication_enabled" {
  description = "Whether replication is enabled"
  value       = var.enable_replication && length(var.replication_destinations) > 0
}

output "replication_destinations" {
  description = "List of replication destinations"
  value       = var.replication_destinations
}

################################################################################
# Authentication Commands
################################################################################

output "docker_login_command" {
  description = "Docker login command for this repository"
  value       = "aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin ${local.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"
}

output "docker_pull_command" {
  description = "Example docker pull command"
  value       = "docker pull ${aws_ecr_repository.this.repository_url}:latest"
}

output "docker_push_command" {
  description = "Example docker push command"
  value       = "docker push ${aws_ecr_repository.this.repository_url}:latest"
}
