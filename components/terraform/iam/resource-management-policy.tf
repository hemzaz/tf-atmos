resource "aws_iam_policy" "resource_management" {
  count = var.create_cross_account_role ? 1 : 0

  name        = "${var.policy_name}-resource-management"
  path        = "/"
  description = "Policy for managing AWS resources within account with least privilege"

  # Statements whose resource list is empty are dropped: IAM rejects empty Resource arrays.
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [for statement in [
      {
        Sid    = "ReadOnlyAccess"
        Effect = "Allow",
        Action = [
          "ec2:Describe*",
          "ec2:List*",
          "ec2:Get*",
          "rds:Describe*",
          "rds:List*",
          "dynamodb:Describe*",
          "dynamodb:List*",
          "elasticloadbalancing:Describe*",
          "logs:Describe*",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "sns:ListTopics"
        ],
        Resource = "*" # Read-only actions are acceptable with wildcard
      },
      {
        Sid    = "S3ObjectAccess"
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ],
        Resource = var.managed_s3_bucket_arns != null ? [
          for bucket_arn in var.managed_s3_bucket_arns : "${bucket_arn}/*"
        ] : []
        Condition = {
          StringEquals = {
            "s3:ExistingObjectTag/ManagedBy" = "terraform"
          }
        }
      },
      {
        Sid    = "S3BucketListing"
        Effect = "Allow",
        Action = [
          "s3:ListBucket"
        ],
        Resource = var.managed_s3_bucket_arns != null ? var.managed_s3_bucket_arns : []
      },
      {
        Sid    = "DynamoDBTableAccess"
        Effect = "Allow",
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ],
        Resource = var.managed_dynamodb_table_arns != null ? var.managed_dynamodb_table_arns : []
      },
      {
        Sid    = "CloudWatchLogsAccess"
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = var.log_group_arns != null ? var.log_group_arns : [
          "arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/${var.environment}/*"
        ]
      },
      {
        Sid    = "CloudWatchMetrics"
        Effect = "Allow",
        Action = [
          "cloudwatch:PutMetricData"
        ],
        Resource = "*" # CloudWatch metrics don't support resource-level permissions
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = var.allowed_cloudwatch_namespaces
          }
        }
      },
      {
        Sid    = "SNSPublishAccess"
        Effect = "Allow",
        Action = [
          "sns:Publish",
          "sns:Subscribe"
        ],
        Resource = var.managed_sns_topic_arns != null ? var.managed_sns_topic_arns : []
      }
    ] : statement if length(flatten([statement.Resource])) > 0]
  })

  # No precondition requiring a managed_* ARN list. The filter above already
  # drops empty statements, and ReadOnlyAccess, CloudWatchLogsAccess and
  # CloudWatchMetrics always remain, so the document is valid without them. A
  # guard that forces extra write grants just to plan is the opposite of least
  # privilege, and it made every catalog/iam/defaults instance unplannable.
  # Cloud Posse's aws-iam-role likewise accepts an empty resource list.
}

resource "aws_iam_role_policy_attachment" "resource_management" {
  count = var.create_cross_account_role ? 1 : 0

  role       = aws_iam_role.cross_account_role[0].name
  policy_arn = aws_iam_policy.resource_management[0].arn
}