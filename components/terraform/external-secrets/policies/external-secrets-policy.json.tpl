{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadScopedSecrets",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetResourcePolicy",
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "secretsmanager:ListSecretVersionIds"
      ],
      "Resource": ${jsonencode(secretsmanager_resource_arns)}
    },
    {
      "Sid": "DecryptViaSecretsManager",
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt"
      ],
      "Resource": "${kms_key_arn}",
      "Condition": {
        "StringEquals": {
          "kms:ViaService": "secretsmanager.${region}.${dns_suffix}"
        }
      }
    }
  ]
}
