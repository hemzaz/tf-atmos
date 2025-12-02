# SQS Queue

Production-ready Amazon SQS queue module with encryption, dead letter queue, and monitoring.

## Features

- Standard and FIFO queues
- Server-side encryption with KMS (automatic key creation or BYO key)
- Dead letter queue with configurable redrive policy
- Cross-account access via queue policies
- SNS topic integration
- CloudWatch alarms (queue depth, message age, DLQ messages)
- Long polling support
- Message delay and visibility timeout configuration

## Usage

```hcl
module "order_queue" {
  source = "./_library/integration/sqs-queue"

  name_prefix = "prod"
  queue_name  = "order-processing"

  # FIFO configuration
  fifo_queue                  = true
  content_based_deduplication = true

  # Message settings
  visibility_timeout_seconds = 300
  message_retention_seconds  = 604800  # 7 days

  # Dead letter queue
  enable_dead_letter_queue = true
  max_receive_count        = 3

  # CloudWatch alarms
  enable_cloudwatch_alarms     = true
  alarm_queue_depth_threshold  = 1000
  alarm_message_age_threshold  = 900
  alarm_actions                = [aws_sns_topic.alerts.arn]

  tags = {
    Environment = "production"
    Team        = "platform"
  }
}
```

## Inputs

See `variables.tf` for complete list of variables.

## Outputs

See `outputs.tf` for complete list of outputs.
