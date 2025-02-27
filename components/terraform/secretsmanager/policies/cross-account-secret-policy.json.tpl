{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCrossAccountRoleAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": ${jsonencode(cross_account_principals)}
      },
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "*"
    }
  ]
}