# Web Service Component Outputs

# Load Balancer outputs
output "load_balancer_arn" {
  description = "ARN of the load balancer"
  value       = var.load_balancer_enabled ? aws_lb.this[0].arn : null
}

output "load_balancer_dns_name" {
  description = "DNS name of the load balancer"
  value       = var.load_balancer_enabled ? aws_lb.this[0].dns_name : null
}

output "load_balancer_zone_id" {
  description = "Canonical hosted zone ID of the load balancer"
  value       = var.load_balancer_enabled ? aws_lb.this[0].zone_id : null
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = var.load_balancer_enabled ? aws_lb_target_group.this[0].arn : null
}

# ECS outputs
output "cluster_id" {
  description = "ID of the ECS cluster"
  value       = aws_ecs_cluster.this.id
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.this.arn
}

output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.this.name
}

output "service_id" {
  description = "ID of the ECS service"
  value       = aws_ecs_service.this.id
}

output "service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.this.name
}

output "service_arn" {
  description = "ARN of the ECS service"
  value       = aws_ecs_service.this.arn
}

output "task_definition_arn" {
  description = "ARN of the task definition"
  value       = aws_ecs_task_definition.this.arn
}

output "task_definition_family" {
  description = "Family of the task definition"
  value       = aws_ecs_task_definition.this.family
}

output "task_definition_revision" {
  description = "Revision of the task definition"
  value       = aws_ecs_task_definition.this.revision
}

# Security Group outputs
output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = var.load_balancer_enabled ? aws_security_group.alb[0].id : null
}

output "service_security_group_id" {
  description = "ID of the service security group"
  value       = aws_security_group.service.id
}

# IAM outputs
output "task_execution_role_arn" {
  description = "ARN of the task execution role"
  value       = aws_iam_role.task_execution.arn
}

output "task_role_arn" {
  description = "ARN of the task role"
  value       = aws_iam_role.task.arn
}

# CloudWatch outputs
output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.this.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.this.arn
}

# Auto Scaling outputs
output "auto_scaling_target_resource_id" {
  description = "Resource ID of the auto scaling target"
  value       = var.auto_scaling_enabled ? aws_appautoscaling_target.this[0].resource_id : null
}

output "auto_scaling_cpu_policy_arn" {
  description = "ARN of the CPU auto scaling policy"
  value       = var.auto_scaling_enabled ? aws_appautoscaling_policy.cpu[0].arn : null
}

output "auto_scaling_memory_policy_arn" {
  description = "ARN of the memory auto scaling policy"
  value       = var.auto_scaling_enabled && var.auto_scaling_memory_enabled ? aws_appautoscaling_policy.memory[0].arn : null
}

# Service discovery outputs (for future use)
output "service_discovery_service_id" {
  description = "ID of the service discovery service"
  value       = null # TODO: Implement service discovery
}

# Computed values
output "service_url" {
  description = "URL to access the service"
  value       = var.load_balancer_enabled ? "http${var.certificate_arn != "" ? "s" : ""}://${aws_lb.this[0].dns_name}" : null
}

output "service_endpoint" {
  description = "Service endpoint information"
  value = var.load_balancer_enabled ? {
    dns_name     = aws_lb.this[0].dns_name
    zone_id      = aws_lb.this[0].zone_id
    scheme       = aws_lb.this[0].scheme
    load_balancer_type = aws_lb.this[0].load_balancer_type
    protocol     = var.certificate_arn != "" ? "HTTPS" : "HTTP"
    port         = var.certificate_arn != "" ? 443 : 80
  } : null
}

# Summary information
output "service_info" {
  description = "Summary information about the service"
  value = {
    name                = var.service_name
    cluster_name        = aws_ecs_cluster.this.name
    desired_count       = var.desired_count
    task_cpu           = var.task_cpu
    task_memory        = var.task_memory
    container_port     = var.container_port
    load_balancer_enabled = var.load_balancer_enabled
    auto_scaling_enabled  = var.auto_scaling_enabled
    container_insights    = var.container_insights_enabled
    platform_version      = var.platform_version
  }
}

# Resource tags
output "common_tags" {
  description = "Common tags applied to resources"
  value       = local.common_tags
  sensitive   = false
}