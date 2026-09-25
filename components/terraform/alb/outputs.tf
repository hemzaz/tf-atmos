output "alb_arn" {
  description = "Load balancer ARN"
  value       = one(aws_lb.this[*].arn)
}

output "alb_arn_suffix" {
  description = "Load balancer ARN suffix, for CloudWatch dimensions (e.g. app/<name>/<id>)"
  value       = one(aws_lb.this[*].arn_suffix)
}

output "alb_dns_name" {
  description = "Load balancer DNS name"
  value       = one(aws_lb.this[*].dns_name)
}

output "alb_zone_id" {
  description = "Load balancer's Route 53 hosted zone id, for an alias record"
  value       = one(aws_lb.this[*].zone_id)
}

output "https_listener_arn" {
  description = "HTTPS (443) listener ARN, for a later component to add its own listener rule"
  value       = one(aws_lb_listener.https[*].arn)
}

output "default_target_group_arn" {
  description = "ARN of the catch-all default target group the HTTPS listener forwards to"
  value       = one(aws_lb_target_group.default[*].arn)
}

output "security_group_id" {
  description = "Security group id attached to the load balancer"
  value       = one(aws_security_group.this[*].id)
}

output "access_logs_bucket_id" {
  description = "Access-logs bucket id (name), or null when access_logs_enabled is false"
  value       = one(aws_s3_bucket.access_logs[*].id)
}
