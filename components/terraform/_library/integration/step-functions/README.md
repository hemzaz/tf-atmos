# Step Functions State Machine

Production-ready AWS Step Functions state machine with comprehensive IAM permissions and monitoring.

## Features

- STANDARD and EXPRESS state machine types
- CloudWatch Logs integration with configurable retention
- AWS X-Ray tracing for distributed tracing
- Automatic IAM role creation with least privilege
- Support for Lambda, SQS, SNS, DynamoDB, ECS, EventBridge integrations
- CloudWatch alarms (execution failures, throttling, timeouts)
- Error handling patterns (retry, catch)
- Extensible IAM policy for custom integrations

## Usage

```hcl
module "order_workflow" {
  source = "./_library/integration/step-functions"

  name_prefix        = "prod"
  state_machine_name = "order-processing"

  definition = jsonencode({
    Comment = "Order processing workflow"
    StartAt = "ValidateOrder"
    States = {
      ValidateOrder = {
        Type     = "Task"
        Resource = aws_lambda_function.validator.arn
        Next     = "ProcessPayment"
        Retry = [{
          ErrorEquals     = ["States.TaskFailed"]
          IntervalSeconds = 2
          MaxAttempts     = 3
          BackoffRate     = 2
        }]
      }
      ProcessPayment = {
        Type     = "Task"
        Resource = aws_lambda_function.payment.arn
        End      = true
      }
    }
  })

  # IAM permissions
  lambda_function_arns = [
    aws_lambda_function.validator.arn,
    aws_lambda_function.payment.arn
  ]

  # Logging and tracing
  enable_logging      = true
  log_level           = "ERROR"
  enable_xray_tracing = true

  tags = {
    Environment = "production"
  }
}
```

## Inputs

See `variables.tf` for complete list of variables.

## Outputs

See `outputs.tf` for complete list of outputs.
