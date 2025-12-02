# Kinesis Stream

Production-ready Kinesis Data Stream with auto-scaling, enhanced fan-out, and Lambda consumer integration.

## Features

- ON_DEMAND or PROVISIONED capacity modes
- Auto-scaling for provisioned streams
- Enhanced fan-out consumers for low-latency processing
- KMS encryption at rest
- Lambda event source mapping with filtering
- CloudWatch monitoring with alarms
- Iterator age and throughput monitoring
- Configurable retention (24h to 365 days)

## Usage

```hcl
module "kinesis_stream" {
  source = "./_library/data-platform/kinesis-stream"

  name_prefix      = "prod-events"
  stream_mode      = "ON_DEMAND"
  retention_hours  = 168
  kms_key_id       = aws_kms_key.stream.id

  enhanced_fanout_consumers = ["analytics", "monitoring"]

  lambda_consumers = {
    processor = {
      function_name          = aws_lambda_function.processor.function_name
      batch_size             = 100
      parallelization_factor = 2
      filter_pattern         = jsonencode({
        eventType = ["order", "payment"]
      })
    }
  }

  enable_monitoring = true
  alarm_actions     = [aws_sns_topic.alerts.arn]

  tags = {
    Environment = "production"
    Service     = "event-streaming"
  }
}
```

## Inputs

See `variables.tf` for complete list of variables.

## Outputs

See `outputs.tf` for complete list of outputs.
