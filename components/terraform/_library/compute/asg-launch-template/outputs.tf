# ASG Launch Template Module - Outputs
# Version: 1.0.0

output "launch_template_id" {
  description = "ID of the launch template"
  value       = aws_launch_template.main.id
}

output "launch_template_arn" {
  description = "ARN of the launch template"
  value       = aws_launch_template.main.arn
}

output "launch_template_latest_version" {
  description = "Latest version of the launch template"
  value       = aws_launch_template.main.latest_version
}

output "autoscaling_group_id" {
  description = "ID of the Auto Scaling Group"
  value       = aws_autoscaling_group.main.id
}

output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.main.name
}

output "autoscaling_group_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = aws_autoscaling_group.main.arn
}

output "iam_role_arn" {
  description = "ARN of the IAM role"
  value       = var.iam_instance_profile == null ? aws_iam_role.instance[0].arn : null
}

output "iam_instance_profile_name" {
  description = "Name of the IAM instance profile"
  value       = var.iam_instance_profile != null ? var.iam_instance_profile : aws_iam_instance_profile.instance[0].name
}

output "security_group_id" {
  description = "ID of the security group"
  value       = length(var.security_group_ids) > 0 ? var.security_group_ids[0] : aws_security_group.instance[0].id
}

output "cpu_alarm_arn" {
  description = "ARN of the high CPU alarm"
  value       = aws_cloudwatch_metric_alarm.high_cpu.arn
}
