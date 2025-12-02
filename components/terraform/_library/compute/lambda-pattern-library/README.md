# Lambda Pattern Library Module

Comprehensive Lambda module supporting 5 deployment patterns with API Gateway, EventBridge, SQS, SNS, and stream integrations.

## Deployment Patterns

### 1. REST API Pattern
API Gateway → Lambda → Backend Services

### 2. Event-Driven Pattern
EventBridge → Lambda (Scheduled or Event-based)

### 3. Stream Processing Pattern
Kinesis/DynamoDB Streams → Lambda → Processing

### 4. Queue Processing Pattern
SQS → Lambda → Async Processing

### 5. VPC-Integrated Pattern
Private Lambda → VPC Resources (RDS, ElastiCache, etc.)

## Features

- **Multiple Triggers**: API Gateway, EventBridge, SQS, SNS, Kinesis, DynamoDB Streams
- **Auto-Scaling**: Provisioned concurrency and reserved concurrent executions
- **Monitoring**: CloudWatch Logs, X-Ray tracing, Container Insights
- **Security**: IAM roles, Secrets Manager, KMS encryption, VPC integration
- **Cost Optimization**: ARM64 architecture, right-sizing, Spot instances
- **High Availability**: Multi-AZ deployment, DLQ for failed invocations
- **Observability**: Structured logging, distributed tracing, metrics

## Quick Start

```hcl
module "lambda_api" {
  source = "../../_library/compute/lambda-pattern-library"

  name_prefix       = "myapp"
  environment       = "production"
  function_name     = "api-handler"
  deployment_pattern = "rest-api"

  # Function configuration
  runtime           = "python3.11"
  handler           = "app.handler"
  source_code_path  = "./lambda-code"
  memory_size       = 512
  timeout           = 30

  # API Gateway integration
  enable_api_gateway = true
  api_gateway_type   = "REST"

  # Auto-scaling
  enable_provisioned_concurrency      = true
  provisioned_concurrent_executions  = 5

  # Monitoring
  enable_xray_tracing = true
  log_retention_days  = 7

  tags = {
    Project = "MyApp"
  }
}
```

## Cost Comparison

| Memory | Requests/Month | Monthly Cost | Use Case |
|--------|----------------|--------------|----------|
| 128 MB | 1M | $0.20 | Lightweight APIs |
| 512 MB | 10M | $8.33 | Standard APIs |
| 1024 MB | 100M | $166.67 | Heavy processing |
| 2048 MB | 1B | $3,334 | Enterprise scale |

**Cost Optimization:**
- Use ARM64 for 20% cost reduction: `architectures = ["arm64"]`
- Right-size memory based on actual usage
- Use provisioned concurrency only for critical functions
- Enable SnapStart for Java/Kotlin (faster cold starts)

## Examples

See [examples/](./examples/) directory for complete examples of all patterns.

## License

See [LICENSE](../../LICENSE)
