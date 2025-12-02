################################################################################
# Application Outputs
################################################################################

output "app_id" {
  description = "ID of the CodeDeploy application"
  value       = aws_codedeploy_app.this.id
}

output "app_arn" {
  description = "ARN of the CodeDeploy application"
  value       = aws_codedeploy_app.this.arn
}

output "app_name" {
  description = "Name of the CodeDeploy application"
  value       = aws_codedeploy_app.this.name
}

output "compute_platform" {
  description = "Compute platform of the application"
  value       = aws_codedeploy_app.this.compute_platform
}

################################################################################
# Deployment Group Outputs
################################################################################

output "deployment_group_id" {
  description = "ID of the CodeDeploy deployment group"
  value       = aws_codedeploy_deployment_group.this.id
}

output "deployment_group_arn" {
  description = "ARN of the CodeDeploy deployment group"
  value       = aws_codedeploy_deployment_group.this.arn
}

output "deployment_group_name" {
  description = "Name of the CodeDeploy deployment group"
  value       = aws_codedeploy_deployment_group.this.deployment_group_name
}

################################################################################
# Deployment Configuration Outputs
################################################################################

output "deployment_config_id" {
  description = "ID of the custom deployment configuration"
  value       = var.create_deployment_config ? aws_codedeploy_deployment_config.this[0].id : null
}

output "deployment_config_name" {
  description = "Name of the deployment configuration in use"
  value       = local.deployment_config_name
}

################################################################################
# IAM Role Outputs
################################################################################

output "service_role_arn" {
  description = "ARN of the CodeDeploy service role"
  value       = var.create_service_role ? aws_iam_role.this[0].arn : var.service_role_arn
}

output "service_role_id" {
  description = "ID of the CodeDeploy service role"
  value       = var.create_service_role ? aws_iam_role.this[0].id : null
}

output "service_role_name" {
  description = "Name of the CodeDeploy service role"
  value       = var.create_service_role ? aws_iam_role.this[0].name : null
}

################################################################################
# Metadata Outputs
################################################################################

output "deployment_group_console_url" {
  description = "URL to the CodeDeploy deployment group console"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/codesuite/codedeploy/applications/${aws_codedeploy_app.this.name}/deployment-groups/${aws_codedeploy_deployment_group.this.deployment_group_name}"
}

output "deployment_type" {
  description = "Deployment type (IN_PLACE or BLUE_GREEN)"
  value       = var.deployment_type
}

output "deployment_option" {
  description = "Deployment option (WITH_TRAFFIC_CONTROL or WITHOUT_TRAFFIC_CONTROL)"
  value       = var.deployment_option
}

################################################################################
# Configuration Summary Outputs
################################################################################

output "auto_rollback_enabled" {
  description = "Whether auto rollback is enabled"
  value       = var.enable_auto_rollback
}

output "autoscaling_groups" {
  description = "List of Auto Scaling Groups associated with deployment group"
  value       = var.autoscaling_groups
}
