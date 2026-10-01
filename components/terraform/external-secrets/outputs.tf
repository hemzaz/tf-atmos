output "external_secrets_role_arn" {
  description = "ARN of the default ClusterSecretStore's (aws-secretsmanager) IAM role"
  value       = try(aws_iam_role.external_secrets["aws-secretsmanager"].arn, "")
}

output "external_secrets_role_name" {
  description = "Name of the default ClusterSecretStore's (aws-secretsmanager) IAM role"
  value       = try(aws_iam_role.external_secrets["aws-secretsmanager"].name, "")
}

output "external_secrets_policy_arn" {
  description = "ARN of the default ClusterSecretStore's (aws-secretsmanager) IAM policy"
  value       = try(aws_iam_policy.external_secrets["aws-secretsmanager"].arn, "")
}

output "external_secrets_policy_name" {
  description = "Name of the default ClusterSecretStore's (aws-secretsmanager) IAM policy"
  value       = try(aws_iam_policy.external_secrets["aws-secretsmanager"].name, "")
}

output "certificate_store_role_arn" {
  description = "ARN of the certificate ClusterSecretStore's (aws-certificate-store) IAM role"
  value       = try(aws_iam_role.external_secrets["aws-certificate-store"].arn, "")
}

output "certificate_store_role_name" {
  description = "Name of the certificate ClusterSecretStore's (aws-certificate-store) IAM role"
  value       = try(aws_iam_role.external_secrets["aws-certificate-store"].name, "")
}

output "external_secrets_service_account" {
  description = "Name of the operator's service account"
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
