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
          "ec2:Describe*",
          "ec2:List*",
          "ec2:Get*",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "rds:Describe*",
          "rds:List*",
          "dynamodb:Describe*",
          "dynamodb:List*",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "elasticloadbalancing:Describe*",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:Describe*",
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "sns:Publish",
          "sns:Subscribe",
          "sns:ListTopics"
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