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
      "Sid": "ListSecrets",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:ListSecrets"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ReadScopedParameters",
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter*"
      ],
      "Resource": ${jsonencode(ssm_resource_arns)}
    },
    {
      "Sid": "DecryptViaSecretsManagerOrSsm",
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt"
      ],
      "Resource": "${kms_key_arn}",
      "Condition": {
        "StringEquals": {
          "kms:ViaService": [
            "secretsmanager.${region}.${dns_suffix}",
            "ssm.${region}.${dns_suffix}"
          ]
        }
      }
    }
  ]
}
