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

output "job_definition_arns" {
  description = "Revisioned job definition ARNs (...:job-definition/<name>:<revision>) by job_definitions key. Every change registers a new revision and deregisters this one: submitters that should follow the latest revision use job_definition_names (or job_definition_arn_prefixes) instead"
  value       = { for k, d in aws_batch_job_definition.this : k => d.arn }
}

output "job_definition_arn_prefixes" {
  description = "Job definition ARNs without the revision by job_definitions key: SubmitJob resolves them to the latest active revision; <prefix>:* scopes batch:SubmitJob in IAM"
  value       = { for k, d in aws_batch_job_definition.this : k => d.arn_prefix }
}

output "job_definition_names" {
  description = "Job definition names (<Environment>-<name>-<key>) by job_definitions key; SubmitJob with a name runs the latest active revision"
  value       = { for k, d in aws_batch_job_definition.this : k => d.name }
}

output "job_execution_role_arn" {
  description = "Execution role used by the job definitions that need one: execution_role_arn, the created <Environment>-<name>-job-execution, or null when no definition needs one"
  value       = length(local.execution_role_keys) > 0 ? local.execution_role_arn : null
}

output "job_role_arns" {
  description = "Job role ARN per job_definitions key (the given job_role_arn or the created <Environment>-<name>-<key>-job); definitions without a job role are omitted"
  value = merge(
    { for k, d in local.job_definitions : k => d.job_role_arn if d.job_role_arn != null },
    { for k, r in aws_iam_role.job : k => r.arn },
  )
}

output "events_role_arn" {
  description = "EventBridge target role ARN (null unless events_role_enabled); allowed batch:SubmitJob on this instance's job queues and job definitions only"
  value       = one(aws_iam_role.events[*].arn)
}

output "log_group_name" {
  description = "The job definitions' CloudWatch log group (/aws/batch/<Environment>-<name>); null without job definitions"
  value       = one(aws_cloudwatch_log_group.jobs[*].name)
}
