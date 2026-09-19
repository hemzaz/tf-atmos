# RDS master credential rotation
#
# The master password is managed by RDS (manage_master_user_password), which owns the
# Secrets Manager secret and its rotation function. Only the schedule is set here.

resource "aws_secretsmanager_secret_rotation" "db_password" {
  count = var.enable_secrets_rotation ? 1 : 0

  secret_id = aws_db_instance.main.master_user_secret[0].secret_arn

  rotation_rules {
    automatically_after_days = var.rotation_days
  }
}

# SNS topic for rotation notifications (optional)
resource "aws_sns_topic" "rotation_notifications" {
  count = var.enable_secrets_rotation && var.create_rotation_sns_topic ? 1 : 0

  name              = "${var.tags["Environment"]}-${var.identifier}-rotation-notifications"
  kms_master_key_id = var.sns_kms_key_id

  tags = merge(
    var.tags,
    {
      Name    = "${var.tags["Environment"]}-${var.identifier}-rotation-notifications"
      Purpose = "rotation-notifications"
    }
  )
}

# SNS topic subscription (email example)
resource "aws_sns_topic_subscription" "rotation_notifications_email" {
  count = var.enable_secrets_rotation && var.create_rotation_sns_topic && length(var.rotation_notification_emails) > 0 ? length(var.rotation_notification_emails) : 0

  topic_arn = aws_sns_topic.rotation_notifications[0].arn
  protocol  = "email"
  endpoint  = var.rotation_notification_emails[count.index]
}

# EventBridge rule for successful rotations
resource "aws_cloudwatch_event_rule" "rotation_success" {
  count = var.enable_secrets_rotation && var.enable_rotation_events ? 1 : 0

  name        = "${var.tags["Environment"]}-${var.identifier}-rotation-success"
  description = "Capture successful RDS secret rotations"

  event_pattern = jsonencode({
    source      = ["aws.secretsmanager"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["secretsmanager.amazonaws.com"]
      eventName   = ["RotateSecret"]
      requestParameters = {
        secretId = [aws_db_instance.main.master_user_secret[0].secret_arn]
      }
      responseElements = {
        versionId = [{ exists = true }]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "rotation_success" {
  count = var.enable_secrets_rotation && var.enable_rotation_events && var.create_rotation_sns_topic ? 1 : 0

  rule      = aws_cloudwatch_event_rule.rotation_success[0].name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.rotation_notifications[0].arn
}

# SNS topic policy for EventBridge
resource "aws_sns_topic_policy" "rotation_notifications" {
  count = var.enable_secrets_rotation && var.create_rotation_sns_topic ? 1 : 0

  arn = aws_sns_topic.rotation_notifications[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.rotation_notifications[0].arn
      }
    ]
  })
}
