resource "aws_iam_policy" "resource_management" {
  name        = "${var.policy_name}-resource-management"
  path        = "/"
  description = "Policy for managing AWS resources within account"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ec2:*",
          "s3:*",
          "rds:*",
          "dynamodb:*",
          "elasticloadbalancing:*",
          "logs:*",
          "cloudwatch:*",
          "sns:*"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "resource_management" {
  role       = aws_iam_role.cross_account_role.name
  policy_arn = aws_iam_policy.resource_management.arn
}