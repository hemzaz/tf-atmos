# IAM roles and policies for the three Lambda functions. Every statement
# below is one of:
#   - a read-only Describe*/List*/Get* statement, Resource "*" and no
#     Condition, because those actions have no resource-level permission
#     support (AWS denies a Describe/List/Get call scoped by a resource
#     Condition rather than allowing it) - see the IAM/service-authorization
#     reference for each service;
#   - a mutating statement scoped by a Condition on the actual resource's
#     tags: tags.Environment AND an opt-in tag (local.opt_in_tag_key), so a
#     resource must be deliberately tagged into this component's blast radius
#     before it can be started/stopped/deleted, being "in the environment"
#     alone is not enough. The condition key namespace is service-specific:
#     EC2 has its own ec2:ResourceTag/<key> key; RDS, EKS, Auto Scaling and
#     ELB do not, and use the aws:ResourceTag/<key> global key instead (ELB
#     in particular does NOT support ec2:ResourceTag - only aws:ResourceTag);
#   - a logs statement scoped to the function's own CloudWatch log group
#     (created in lambda.tf), never the account-wide arn:aws:logs:*:*:*; or
#   - an SNS publish + matching KMS statement, mirroring the pattern this
#     repo's stepfunctions component uses for its own KMS grant: scoped by
#     the actual kms:EncryptionContext SNS sets on the call
#     (kms:EncryptionContext:aws:sns:topicArn), so the role can only use the
#     key for this topic, never another resource sharing the same CMK.

# ========================================
# Instance Scheduler
# ========================================

resource "aws_iam_role" "scheduler" {
  count = local.current_settings.auto_shutdown ? 1 : 0

  name = "${local.name}-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
      }
    ]
  })

  tags = { Name = "${local.name}-scheduler-role" }
}

resource "aws_iam_role_policy" "scheduler" {
  count = local.current_settings.auto_shutdown ? 1 : 0

  name = "${local.name}-scheduler-policy"
  role = aws_iam_role.scheduler[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DescribeTargets"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags",
          "rds:DescribeDBInstances",
          "rds:ListTagsForResource",
          "eks:DescribeNodegroup",
          "autoscaling:DescribeAutoScalingGroups",
        ]
        Resource = "*"
      },
      {
        Sid    = "StartStopEC2"
        Effect = "Allow"
        Action = [
          "ec2:StartInstances",
          "ec2:StopInstances",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/Environment"             = var.tags["Environment"]
            "ec2:ResourceTag/${local.opt_in_tag_key}" = local.scheduler_opt_in_tag_value
          }
        }
      },
      {
        Sid    = "StartStopRDS"
        Effect = "Allow"
        Action = [
          "rds:StartDBInstance",
          "rds:StopDBInstance",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Environment"             = var.tags["Environment"]
            "aws:ResourceTag/${local.opt_in_tag_key}" = local.scheduler_opt_in_tag_value
          }
        }
      },
      {
        Sid      = "ScaleEKSNodegroup"
        Effect   = "Allow"
        Action   = ["eks:UpdateNodegroupConfig"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Environment"             = var.tags["Environment"]
            "aws:ResourceTag/${local.opt_in_tag_key}" = local.scheduler_opt_in_tag_value
          }
        }
      },
      {
        Sid    = "ScaleAutoScalingGroup"
        Effect = "Allow"
        Action = [
          "autoscaling:UpdateAutoScalingGroup",
          # Used by the scheduler to save/restore an ASG's normal capacity as
          # tags on itself (NormalCapacity/NormalMinSize) across a stop/start
          # cycle - a mutation of the ASG's own tags, so it carries the same
          # condition as the capacity change it accompanies.
          "autoscaling:CreateOrUpdateTags",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Environment"             = var.tags["Environment"]
            "aws:ResourceTag/${local.opt_in_tag_key}" = local.scheduler_opt_in_tag_value
          }
        }
      },
      {
        Sid      = "OwnLogGroup"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [local.scheduler_log_group_arn]
      },
    ]
  })
}

# ========================================
# Savings Plans / RI Recommendation Analyzer
# ========================================

resource "aws_iam_role" "savings_analyzer" {
  name = "${local.name}-savings-analyzer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
      }
    ]
  })

  tags = { Name = "${local.name}-savings-analyzer-role" }
}

resource "aws_iam_role_policy" "savings_analyzer" {
  name = "${local.name}-savings-analyzer-policy"
  role = aws_iam_role.savings_analyzer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Account-level recommendation/reporting APIs: no resource-level
        # permission support, so Resource "*" with no Condition is correct
        # (not merely unfixed), as with the Describe statements above.
        Sid    = "ReadCostAndOptimizerData"
        Effect = "Allow"
        Action = [
          "ce:GetSavingsPlansPurchaseRecommendation",
          "ce:GetReservationPurchaseRecommendation",
          "ce:GetRightsizingRecommendation",
          "ce:GetCostAndUsage",
          "ce:GetCostForecast",
          "compute-optimizer:GetEC2InstanceRecommendations",
          "compute-optimizer:GetAutoScalingGroupRecommendations",
          "compute-optimizer:GetEBSVolumeRecommendations",
        ]
        Resource = "*"
      },
      {
        Sid      = "PublishToCostAlerts"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = local.cost_alerts_topic_arn
      },
      {
        Sid      = "UseCostAlertsTopicKey"
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = var.kms_key_arn
        Condition = {
          StringEquals = {
            "kms:EncryptionContext:aws:sns:topicArn" = local.cost_alerts_topic_arn
          }
        }
      },
      {
        Sid      = "OwnLogGroup"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [local.savings_analyzer_log_group_arn]
      },
    ]
  })
}

# ========================================
# Unused Resource Cleanup
# ========================================

resource "aws_iam_role" "resource_cleanup" {
  name = "${local.name}-resource-cleanup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
      }
    ]
  })

  tags = { Name = "${local.name}-resource-cleanup-role" }
}

resource "aws_iam_role_policy" "resource_cleanup" {
  name = "${local.name}-resource-cleanup-policy"
  role = aws_iam_role.resource_cleanup.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DescribeCleanupCandidates"
        Effect = "Allow"
        Action = [
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots",
          "ec2:DescribeAddresses",
          # Checked before deleting a snapshot, so a snapshot still backing a
          # registered AMI is never removed even if it is opt-in tagged.
          "ec2:DescribeImages",
        ]
        Resource = "*"
      },
      {
        Sid    = "DeleteCleanupCandidates"
        Effect = "Allow"
        Action = [
          "ec2:DeleteVolume",
          "ec2:DeleteSnapshot",
          "ec2:ReleaseAddress",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/Environment"             = var.tags["Environment"]
            "ec2:ResourceTag/${local.opt_in_tag_key}" = local.cleanup_opt_in_tag_value
          }
        }
      },
      {
        Sid      = "PublishToCostAlerts"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = local.cost_alerts_topic_arn
      },
      {
        Sid      = "UseCostAlertsTopicKey"
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = var.kms_key_arn
        Condition = {
          StringEquals = {
            "kms:EncryptionContext:aws:sns:topicArn" = local.cost_alerts_topic_arn
          }
        }
      },
      {
        Sid      = "OwnLogGroup"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [local.resource_cleanup_log_group_arn]
      },
    ]
  })
}
