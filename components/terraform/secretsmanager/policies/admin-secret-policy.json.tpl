{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SecretManagerFullAccess",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "secretsmanager:PutSecretValue",
        "secretsmanager:UpdateSecret",
        "secretsmanager:UpdateSecretVersionStage",
        "secretsmanager:RotateSecret",
        "secretsmanager:RestoreSecret",
        "secretsmanager:CancelRotateSecret"
      ],
      "Resource": "${secret_arn}"
    },
    {
      "Sid": "KMSCryptoOperations",
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:GenerateDataKey"
      ],
      "Resource": "${kms_key_arn}",
      "Condition": {
        "StringEquals": {
          "kms:ViaService": "secretsmanager.${region}.amazonaws.com"
        }
      }
    }
  ]
}