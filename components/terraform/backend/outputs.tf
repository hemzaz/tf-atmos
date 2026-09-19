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

output "backend_role_arn" {
  description = "The ARN of the IAM role for backend access"
  value       = aws_iam_role.terraform_backend.arn
}
