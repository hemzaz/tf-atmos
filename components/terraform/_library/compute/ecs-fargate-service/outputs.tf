# ECS Fargate Service Module - Outputs
# Version: 1.0.0

# ==============================================================================
# CLUSTER OUTPUTS
# ==============================================================================

output "cluster_id" {
  description = "ID of the ECS cluster"
  value       = var.create_cluster ? aws_ecs_cluster.main[0].id : var.cluster_name
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = var.create_cluster ? aws_ecs_cluster.main[0].arn : null
}

output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = local.cluster_name
}

# ==============================================================================
# SERVICE OUTPUTS
# ==============================================================================

output "service_id" {
  description = "ID of the ECS service"
  value       = aws_ecs_service.main.id
}

output "service_arn" {
  description = "ARN of the ECS service"
  value       = aws_ecs_service.main.id
}

output "service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.main.name
}

# ==============================================================================
# TASK DEFINITION OUTPUTS
# ==============================================================================

output "task_definition_arn" {
  description = "Full ARN of the task definition (including revision)"
  value       = aws_ecs_task_definition.main.arn
}

output "task_definition_family" {
  description = "Family of the task definition"
  value       = aws_ecs_task_definition.main.family
}

output "task_definition_revision" {
  description = "Revision of the task definition"
  value       = aws_ecs_task_definition.main.revision
}

# ==============================================================================
# IAM ROLE OUTPUTS
# ==============================================================================

output "task_role_arn" {
  description = "ARN of the task IAM role"
  value       = var.task_role_arn != null ? var.task_role_arn : (length(aws_iam_role.task) > 0 ? aws_iam_role.task[0].arn : null)
}

output "task_role_name" {
  description = "Name of the task IAM role"
  value       = var.task_role_arn == null && length(aws_iam_role.task) > 0 ? aws_iam_role.task[0].name : null
}

output "execution_role_arn" {
  description = "ARN of the task execution IAM role"
  value       = var.execution_role_arn != null ? var.execution_role_arn : (length(aws_iam_role.execution) > 0 ? aws_iam_role.execution[0].arn : null)
}

output "execution_role_name" {
  description = "Name of the task execution IAM role"
  value       = var.execution_role_arn == null && length(aws_iam_role.execution) > 0 ? aws_iam_role.execution[0].name : null
}

# ==============================================================================
# SECURITY GROUP OUTPUTS
# ==============================================================================

output "security_group_id" {
  description = "ID of the service security group"
  value       = length(var.security_group_ids) > 0 ? var.security_group_ids[0] : (length(aws_security_group.service) > 0 ? aws_security_group.service[0].id : null)
}

output "security_group_ids" {
  description = "List of security group IDs attached to the service"
  value       = length(var.security_group_ids) > 0 ? var.security_group_ids : (length(aws_security_group.service) > 0 ? [aws_security_group.service[0].id] : [])
}

# ==============================================================================
# CLOUDWATCH LOGS OUTPUTS
# ==============================================================================

output "log_group_name" {
  description = "Name of the CloudWatch Log Group"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.service[0].name : null
}

output "log_group_arn" {
  description = "ARN of the CloudWatch Log Group"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.service[0].arn : null
}

# ==============================================================================
# AUTO-SCALING OUTPUTS
# ==============================================================================

output "autoscaling_target_resource_id" {
  description = "Resource ID of the autoscaling target"
  value       = var.enable_autoscaling ? aws_appautoscaling_target.service[0].resource_id : null
}

output "autoscaling_cpu_policy_arn" {
  description = "ARN of the CPU-based autoscaling policy"
  value       = var.enable_autoscaling ? aws_appautoscaling_policy.cpu[0].arn : null
}

output "autoscaling_memory_policy_arn" {
  description = "ARN of the memory-based autoscaling policy"
  value       = var.enable_autoscaling ? aws_appautoscaling_policy.memory[0].arn : null
}

output "autoscaling_alb_policy_arn" {
  description = "ARN of the ALB request count-based autoscaling policy"
  value       = var.enable_autoscaling && var.enable_alb_target_tracking && var.target_group_arn != null ? aws_appautoscaling_policy.alb[0].arn : null
}

# ==============================================================================
# SERVICE DISCOVERY OUTPUTS
# ==============================================================================

output "service_discovery_id" {
  description = "ID of the service discovery service"
  value       = var.enable_service_discovery ? aws_service_discovery_service.main[0].id : null
}

output "service_discovery_arn" {
  description = "ARN of the service discovery service"
  value       = var.enable_service_discovery ? aws_service_discovery_service.main[0].arn : null
}

# ==============================================================================
# CODEDEPLOY OUTPUTS (BLUE/GREEN)
# ==============================================================================

output "codedeploy_app_name" {
  description = "Name of the CodeDeploy application"
  value       = var.enable_blue_green_deployment ? aws_codedeploy_app.main[0].name : null
}

output "codedeploy_app_id" {
  description = "ID of the CodeDeploy application"
  value       = var.enable_blue_green_deployment ? aws_codedeploy_app.main[0].id : null
}

output "codedeploy_deployment_group_name" {
  description = "Name of the CodeDeploy deployment group"
  value       = var.enable_blue_green_deployment ? aws_codedeploy_deployment_group.main[0].deployment_group_name : null
}

output "codedeploy_deployment_group_id" {
  description = "ID of the CodeDeploy deployment group"
  value       = var.enable_blue_green_deployment ? aws_codedeploy_deployment_group.main[0].id : null
}

output "codedeploy_role_arn" {
  description = "ARN of the CodeDeploy IAM role"
  value       = var.enable_blue_green_deployment ? aws_iam_role.codedeploy[0].arn : null
}

# ==============================================================================
# CAPACITY PROVIDER OUTPUTS
# ==============================================================================

output "capacity_provider_strategy" {
  description = "Capacity provider strategy configuration"
  value = {
    fargate_weight      = var.fargate_base_weight
    fargate_spot_weight = var.enable_fargate_spot ? var.fargate_spot_weight : 0
    fargate_spot_enabled = var.enable_fargate_spot
  }
}

# ==============================================================================
# DEPLOYMENT CONFIGURATION OUTPUTS
# ==============================================================================

output "deployment_configuration" {
  description = "Deployment configuration summary"
  value = {
    circuit_breaker_enabled      = var.enable_deployment_circuit_breaker
    blue_green_enabled           = var.enable_blue_green_deployment
    deployment_config_name       = var.enable_blue_green_deployment ? var.deployment_config_name : null
    maximum_percent              = var.deployment_maximum_percent
    minimum_healthy_percent      = var.deployment_minimum_healthy_percent
  }
}

# ==============================================================================
# COST OPTIMIZATION OUTPUTS
# ==============================================================================

output "cost_optimization_summary" {
  description = "Summary of cost optimization features"
  value = {
    fargate_spot_enabled    = var.enable_fargate_spot
    fargate_spot_percentage = var.enable_fargate_spot ? var.fargate_spot_weight : 0
    estimated_monthly_cost_usd = {
      fargate_base_cost = var.cpu == 256 && var.memory == 512 ? 13.00 * var.desired_count : null
      notes = "Actual costs depend on CPU, memory, and running time. Use AWS Cost Calculator for precise estimates."
    }
  }
}

# ==============================================================================
# MODULE METADATA
# ==============================================================================

output "module_metadata" {
  description = "Module version and configuration summary"
  value = {
    module_version = "1.0.0"
    service_name   = var.service_name
    environment    = var.environment
    cpu            = var.cpu
    memory         = var.memory
    desired_count  = var.desired_count
    autoscaling_enabled = var.enable_autoscaling
    load_balancer_enabled = var.enable_load_balancer
    service_discovery_enabled = var.enable_service_discovery
    container_insights_enabled = var.enable_container_insights
  }
}
