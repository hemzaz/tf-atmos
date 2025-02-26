output "backend_bucket" {
  description = "The S3 bucket used for storing Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "backend_bucket_arn" {
  description = "The ARN of the S3 bucket used for storing Terraform state"
  value       = aws_s3_bucket.terraform_state.arn
}

output "dynamodb_table" {
  description = "The DynamoDB table used for Terraform state locking"
  value       = aws_dynamodb_table.terraform_locks.id
}

output "dynamodb_table_arn" {
  description = "The ARN of the DynamoDB table used for Terraform state locking"
  value       = aws_dynamodb_table.terraform_locks.arn
}

output "backend_role_arn" {
  description = "The ARN of the IAM role for backend access"
  value       = aws_iam_role.terraform_backend.arn
}