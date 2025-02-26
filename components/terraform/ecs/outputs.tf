output "cluster_id" {
  value       = aws_ecs_cluster.main.id
  description = "The ID of the ECS cluster"
}

output "cluster_arn" {
  value       = aws_ecs_cluster.main.arn
  description = "The ARN of the ECS cluster"
}

output "cluster_name" {
  value       = aws_ecs_cluster.main.name
  description = "The name of the ECS cluster"
}

output "capacity_providers" {
  value       = aws_ecs_cluster_capacity_providers.main.capacity_providers
  description = "List of capacity providers in the cluster"
}