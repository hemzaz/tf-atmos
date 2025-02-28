output "external_secrets_role_arn" {
  description = "ARN of the IAM role for external-secrets"
  value       = try(aws_iam_role.external_secrets[0].arn, "")
}

output "external_secrets_role_name" {
  description = "Name of the IAM role for external-secrets"
  value       = try(aws_iam_role.external_secrets[0].name, "")
}

output "external_secrets_policy_arn" {
  description = "ARN of the IAM policy for external-secrets"
  value       = try(aws_iam_policy.external_secrets[0].arn, "")
}

output "external_secrets_policy_name" {
  description = "Name of the IAM policy for external-secrets"
  value       = try(aws_iam_policy.external_secrets[0].name, "")
}

output "external_secrets_service_account" {
  description = "Name of the service account for external-secrets"
  value       = var.service_account_name
}

output "external_secrets_namespace" {
  description = "Namespace where external-secrets is installed"
  value       = var.namespace
}

output "default_cluster_secret_store_name" {
  description = "Name of the default ClusterSecretStore"
  value       = var.create_default_cluster_secret_store ? "aws-secretsmanager" : ""
}

output "certificate_secret_store_name" {
  description = "Name of the certificate ClusterSecretStore"
  value       = var.create_certificate_secret_store ? "aws-certificate-store" : ""
}