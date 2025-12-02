output "secret_id" {
  description = "Secret ID"
  value       = aws_secretsmanager_secret.main.id
}

output "secret_arn" {
  description = "Secret ARN"
  value       = aws_secretsmanager_secret.main.arn
}

output "secret_version_id" {
  description = "Secret version ID"
  value       = length(aws_secretsmanager_secret_version.main) > 0 ? aws_secretsmanager_secret_version.main[0].version_id : ""
}

output "rotation_enabled" {
  description = "Whether rotation is enabled"
  value       = var.enable_rotation
}

output "replica_secrets" {
  description = "Replica secret details"
  value = {
    for replica in aws_secretsmanager_secret.main.replica : replica.region => {
      arn        = replica.arn
      kms_key_id = replica.kms_key_id
    }
  }
}
