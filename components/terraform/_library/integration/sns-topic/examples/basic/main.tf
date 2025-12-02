module "notifications" {
  source = "../../"

  name_prefix  = "example"
  topic_name   = "notifications"
  display_name = "Example Notifications"

  sqs_subscriptions = [
    {
      queue_arn            = "arn:aws:sqs:us-east-1:123456789012:example-queue"
      raw_message_delivery = false
    }
  ]

  email_subscriptions = [
    "admin@example.com"
  ]

  enable_cloudwatch_alarms = true

  tags = {
    Environment = "dev"
  }
}
