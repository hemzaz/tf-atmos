output "cross_account_role_arn" {
  description = "ARN of the cross-account IAM role"
  value       = aws_iam_role.cross_account_role.arn
}

output "cross_account_role_name" {
  description = "Name of the cross-account IAM role"
  value       = aws_iam_role.cross_account_role.name
}

output "cross_account_policy_arn" {
  description = "ARN of the cross-account IAM policy"
  value       = aws_iam_policy.cross_account_policy.arn
}

output "cross_account_policy_name" {
  description = "Name of the cross-account IAM policy"
  value       = aws_iam_policy.cross_account_policy.name
}