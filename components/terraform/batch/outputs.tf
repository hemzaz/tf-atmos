output "compute_environment_arns" {
  description = "Compute environment ARNs by compute_environments key"
  value       = { for k, ce in aws_batch_compute_environment.this : k => ce.arn }
}

output "compute_environment_names" {
  description = "Compute environment names (<Environment>-<name>-<key>) by compute_environments key, for CloudWatch dimensions"
  value       = { for k, ce in aws_batch_compute_environment.this : k => ce.name }
}

output "job_queue_arns" {
  description = "Job queue ARNs by job_queues key"
  value       = { for k, q in aws_batch_job_queue.this : k => q.arn }
}

output "job_queue_names" {
  description = "Job queue names (<Environment>-<name>-<key>) by job_queues key"
  value       = { for k, q in aws_batch_job_queue.this : k => q.name }
}

output "instance_role_arn" {
  description = "ARN of the ECS instance role created for EC2/SPOT compute environments without their own instance_role (null when none is created)"
  value       = one(aws_iam_role.instance[*].arn)
}
