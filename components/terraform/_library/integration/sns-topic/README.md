# SNS Topic

Production-ready Amazon SNS topic module with encryption, subscriptions, and message filtering.

## Features

- Standard and FIFO topics
- Server-side encryption with KMS
- Multiple subscription types (SQS, Lambda, HTTP/HTTPS, Email)
- Message filtering for targeted delivery
- Cross-account access policies
- CloudWatch Events/EventBridge integration
- Delivery status logging
- CloudWatch alarms for failed deliveries

## Usage

```hcl
module "notifications" {
  source = "./_library/integration/sns-topic"

  name_prefix  = "prod"
  topic_name   = "order-notifications"
  display_name = "Order Processing Notifications"

  # Subscriptions with filtering
  sqs_subscriptions = [
    {
      queue_arn     = module.high_priority_queue.queue_arn
      filter_policy = jsonencode({
        priority = ["high", "critical"]
      })
    }
  ]

  lambda_subscriptions = [
    {
      function_arn  = aws_lambda_function.processor.arn
      filter_policy = jsonencode({
        event_type = ["order.created"]
      })
    }
  ]

  # CloudWatch alarms
  enable_cloudwatch_alarms = true
  alarm_actions            = [aws_sns_topic.alerts.arn]

  tags = {
    Environment = "production"
  }
}
```

## Inputs

See `variables.tf` for complete list of variables.

## Outputs

See `outputs.tf` for complete list of outputs.
