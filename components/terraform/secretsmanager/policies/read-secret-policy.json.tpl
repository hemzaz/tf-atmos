{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "GetSecretValue",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "${secret_arn}"
    },
    {
      "Sid": "DecryptSecretValue",
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt"
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