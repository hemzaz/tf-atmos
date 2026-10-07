output "backend_bucket" {
  description = "The S3 bucket used for storing Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "backend_bucket_arn" {
  description = "The ARN of the S3 bucket used for storing Terraform state"
  value       = aws_s3_bucket.terraform_state.arn
}

output "backend_kms_key_arn" {
  description = "The ARN of the KMS key encrypting Terraform state"
  value       = aws_kms_key.terraform_state_key.arn
}

output "access_role_arns" {
  description = "ARN of every state access role, by access_roles key"
  value       = { for key, role in aws_iam_role.access : key => role.arn }
}

output "access_role_names" {
  description = "Name of every state access role, by access_roles key"
  value       = { for key, role in aws_iam_role.access : key => role.name }
}

output "backend_role_arn" {
  description = "ARN of the non-prod read/write state role (access_roles key \"write\"): what dev/staging stacks' backend assumes for apply; iam/ci grants the dev/staging CI apply roles sts:AssumeRole on it"
  value       = try(aws_iam_role.access["write"].arn, null)
}

output "backend_role_name" {
  description = "Name of the non-prod read/write state role (access_roles key \"write\")"
  value       = try(aws_iam_role.access["write"].name, null)
}

output "backend_prod_role_arn" {
  description = "ARN of the production read/write state role (access_roles key \"prod_write\"): what prod stacks' backend assumes for apply; iam/ci grants the prod CI apply role sts:AssumeRole on it"
  value       = try(aws_iam_role.access["prod_write"].arn, null)
}

output "backend_prod_role_name" {
  description = "Name of the production read/write state role (access_roles key \"prod_write\")"
  value       = try(aws_iam_role.access["prod_write"].name, null)
}

output "backend_root_role_arn" {
  description = "ARN of the fnx-ue1-root state role (access_roles key \"root_write\"): what fnx-ue1-root's backend assumes; trusted only by the administrator who applies backend/main"
  value       = try(aws_iam_role.access["root_write"].arn, null)
}

output "backend_root_role_name" {
  description = "Name of the fnx-ue1-root state role (access_roles key \"root_write\")"
  value       = try(aws_iam_role.access["root_write"].name, null)
}

output "backend_read_role_arn" {
  description = "ARN of the non-prod read-only state role (access_roles key \"read\"): what dev/staging stacks' backend assumes for plans; iam/ci grants the dev/staging CI plan roles sts:AssumeRole on it"
  value       = try(aws_iam_role.access["read"].arn, null)
}

output "backend_prod_read_role_arn" {
  description = "ARN of the read-only state role for production state (access_roles key \"prod_read\"): what prod stacks' backend assumes for plans; iam/ci grants the prod CI plan role sts:AssumeRole on it"
  value       = try(aws_iam_role.access["prod_read"].arn, null)
}

output "backend_prod_read_role_name" {
  description = "Name of the production read-only state role (access_roles key \"prod_read\")"
  value       = try(aws_iam_role.access["prod_read"].name, null)
}

output "backend_read_role_name" {
  description = "Name of the read-only state role (access_roles key \"read\")"
  value       = try(aws_iam_role.access["read"].name, null)
}
