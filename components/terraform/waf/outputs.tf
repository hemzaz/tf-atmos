output "arn" {
  description = "Web ACL ARN. For scope = CLOUDFRONT, set the distribution's web_acl_id to this"
  value       = one(aws_wafv2_web_acl.this[*].arn)
}

output "id" {
  description = "Web ACL id"
  value       = one(aws_wafv2_web_acl.this[*].id)
}

output "name" {
  description = "Web ACL name"
  value       = one(aws_wafv2_web_acl.this[*].name)
}

output "log_group_arn" {
  description = "CloudWatch log group ARN, or null when enable_logging is false"
  value       = one(aws_cloudwatch_log_group.this[*].arn)
}
