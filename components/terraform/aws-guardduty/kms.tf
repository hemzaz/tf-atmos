data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# KMS key for encrypting the GuardDuty SNS topic
# This is required because of https://github.com/cloudposse/terraform-aws-guardduty/issues/10
# The default AWS-managed key doesn't grant EventBridge permission to decrypt messages.
module "kms_key" {
  count   = local.create_sns_topic ? 1 : 0
  source  = "cloudposse/kms-key/aws"
  version = "0.12.2"

  name                    = "${module.this.id}-guardduty"
  description             = "KMS Key for ${module.this.id}-guardduty"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  alias                   = "alias/${module.this.id}-guardduty"

  policy = jsonencode({
    Version = "2012-10-17",
    Id      = "key-policy",
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow SQS to use the key",
        Effect = "Allow",
        Principal = {
          Service = "sqs.amazonaws.com"
        },
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ],
        Resource = "*"
      },
      {
        Sid    = "Allow CWE to use the key",
        Effect = "Allow",
        Principal = {
          Service = "events.amazonaws.com"
        },
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ],
        Resource = "*"
      },
      {
        Sid    = "Allow access through SNS for all principals in the account that are authorized to use SNS",
        Effect = "Allow",
        Principal = {
          AWS = "*"
        },
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:CreateGrant",
          "kms:ListGrants",
          "kms:DescribeKey"
        ],
        Resource = "*",
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id,
            "kms:ViaService"    = "sns.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      },
      {
        Sid    = "Allow direct access to key metadata to the account",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        Action = [
          "kms:Describe*",
          "kms:Get*",
          "kms:List*",
          "kms:RevokeGrant"
        ],
        Resource = "*"
      },
      {
        Sid    = "Allow SNS to decrypt archived messages",
        Effect = "Allow",
        Principal = {
          Service = "sns.amazonaws.com"
        },
        Action   = "kms:Decrypt",
        Resource = "*",
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          },
          ArnLike = {
            "aws:SourceArn" = "arn:*:sns:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      }
    ]
  })
}
