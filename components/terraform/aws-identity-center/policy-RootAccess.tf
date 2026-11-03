locals {
  root_access_permission_set = local.enabled ? [{
    name             = "RootAccess",
    description      = "Allow centralized root access to member accounts via sts:AssumeRoot",
    relay_state      = "",
    session_duration = var.session_duration,
    tags             = {},
    inline_policy = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid      = "AssumeRootAccess"
        Effect   = "Allow"
        Action   = "sts:AssumeRoot"
        Resource = "arn:${local.aws_partition}:iam::*:root"
        Condition = {
          StringEquals = {
            "sts:TaskPolicyArn" = [
              "arn:${local.aws_partition}:iam::aws:policy/root-task/IAMAuditRootUserCredentials",
              "arn:${local.aws_partition}:iam::aws:policy/root-task/IAMCreateRootUserPassword",
              "arn:${local.aws_partition}:iam::aws:policy/root-task/IAMDeleteRootUserCredentials",
              "arn:${local.aws_partition}:iam::aws:policy/root-task/S3UnlockBucketPolicy",
              "arn:${local.aws_partition}:iam::aws:policy/root-task/SQSUnlockQueuePolicy"
            ]
          }
        }
      }]
    })
    policy_attachments                  = []
    customer_managed_policy_attachments = []
  }] : []
}
