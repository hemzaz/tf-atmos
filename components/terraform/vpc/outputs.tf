output "vpc_management_role_arn" {
  value       = var.create_vpc_iam_role ? aws_iam_role.vpc_management_role[0].arn : ""
  description = "ARN of the VPC management IAM role"
}

output "vpc_management_instance_profile_arn" {
  value       = var.create_vpc_iam_role ? aws_iam_instance_profile.vpc_management_profile[0].arn : ""
  description = "ARN of the VPC management instance profile"
}