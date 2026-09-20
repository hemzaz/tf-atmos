output "detector_id" {
  description = "ID of the GuardDuty detector (null when enable is false)"
  value       = var.enable ? aws_guardduty_detector.main[0].id : null
}

output "detector_arn" {
  description = "ARN of the GuardDuty detector (null when enable is false)"
  value       = var.enable ? aws_guardduty_detector.main[0].arn : null
}

output "enabled_features" {
  description = "Protection plan name to status, as applied to the detector"
  value       = { for name, feature in aws_guardduty_detector_feature.main : name => feature.status }
}

output "auto_archive_filter_arns" {
  description = "ARNs of the auto-archive finding filters"
  value       = aws_guardduty_filter.auto_archive[*].arn
}
