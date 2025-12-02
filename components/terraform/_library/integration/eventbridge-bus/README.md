# EventBridge Event Bus

Production-ready Amazon EventBridge custom event bus with rules, targets, and schema registry.

## Features

- Custom event buses for application decoupling
- Event rules with pattern matching and scheduling
- Multiple target types (Lambda, SQS, Step Functions, Kinesis, SNS, cross-bus)
- Event archive and replay for disaster recovery
- Cross-account event routing
- Schema registry with automatic discovery
- Dead letter queues for failed targets
- Input transformation for targets
- CloudWatch alarms for failed invocations

## Usage

```hcl
module "event_bus" {
  source = "./_library/integration/eventbridge-bus"

  name_prefix = "prod"
  bus_name    = "order-processing"

  event_rules = [
    {
      name          = "order-created"
      description   = "Route order created events"
      event_pattern = jsonencode({
        source      = ["order.service"]
        detail-type = ["Order Created"]
      })
      lambda_targets = [
        {
          function_arn = aws_lambda_function.processor.arn
          retry_policy = {
            maximum_event_age      = 3600
            maximum_retry_attempts = 2
          }
        }
      ]
      sqs_targets = [
        {
          queue_arn = module.queue.queue_arn
        }
      ]
    }
  ]

  enable_archive         = true
  enable_schema_registry = true
  enable_schema_discovery = true

  tags = {
    Environment = "production"
  }
}
```

## Inputs

See `variables.tf` for complete list of variables.

## Outputs

See `outputs.tf` for complete list of outputs.
