##################################################
# AWS Secrets Manager Component Outputs
##################################################

output "secret_arns" {
  description = "Map of secret names to their ARNs"
  value       = { for k, v in aws_secretsmanager_secret.this : k => v.arn }
}

output "secret_ids" {
  description = "Map of secret names to their secret IDs"
  value       = { for k, v in aws_secretsmanager_secret.this : k => v.id }
}

output "secret_names" {
  description = "Map of secret names to their full path names"
  value       = { for k, v in aws_secretsmanager_secret.this : k => v.name }
}

output "secret_versions" {
  description = "Map of secret names to the version IDs Terraform wrote (generated and static_value secrets only). No output carries a secret's value: consumers read it from Secrets Manager at runtime (ESO, the application) by secret_arns / secret_names."
  value       = { for k, v in aws_secretsmanager_secret_version.this : k => v.version_id }
  sensitive   = true
}

output "secret_policies" {
  description = "Map of secret names to their attached policies"
  value       = { for k, v in aws_secretsmanager_secret_policy.this : k => v.policy }
}

output "rotation_enabled_secrets" {
  description = "Map of secret names with rotation enabled"
  value = { for k, v in aws_secretsmanager_secret_rotation.this : k => {
    rotation_lambda_arn      = v.rotation_lambda_arn
    automatically_after_days = v.rotation_rules[0].automatically_after_days
  } }
}

output "secret_access_policy" {
  description = "Map of secret name to a ready-to-use IAM identity policy document (JSON) for a consumer that reads and writes that ONE secret and its value's version stages: secretsmanager:GetSecretValue/PutSecretValue/UpdateSecretVersionStage/DescribeSecret on the secret's own ARN, secretsmanager:GetRandomPassword (Resource \"*\" -- the action has no resource-level permissions), and kms:GenerateDataKey/kms:Decrypt on the secret's kms_key_id scoped by kms:EncryptionContext:SecretARN to this secret alone AND kms:ViaService to this region's Secrets Manager endpoint, so the grant cannot be used to call KMS directly with a forged encryption context naming this secret -- both conditions are exactly what Secrets Manager itself sets on every KMS call it makes for a secret. Built for a Secrets Manager rotation Lambda's custom_policy input (the lambda component's custom_policy accepts exactly one document); fold in another component's own grant via ITS OWN additional_policy_json-style input (e.g. elasticache's rotation_policy) rather than trying to combine two !terraform.state reads into one YAML value, which Atmos cannot do without requiring live state at describe/validate time too. Each secret's kms_key_id must be a full key ARN, not an alias or bare key ID, since it is used directly as an IAM policy Resource element."
  value = { for k, v in local.secrets_with_path : k => jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowSecretReadWrite"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:PutSecretValue", "secretsmanager:UpdateSecretVersionStage", "secretsmanager:DescribeSecret"]
        Resource = aws_secretsmanager_secret.this[k].arn
      },
      {
        Sid      = "AllowGenerateRandomPassword"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetRandomPassword"]
        Resource = "*"
      },
      {
        Sid      = "AllowSecretKMSUse"
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = v.kms_key_id
        Condition = {
          StringEquals = {
            "kms:EncryptionContext:SecretARN" = aws_secretsmanager_secret.this[k].arn
            "kms:ViaService"                  = "secretsmanager.${var.region}.amazonaws.com"
          }
        }
      },
    ]
  }) }
}
