# Serverless API Blueprint

Production-ready serverless REST API infrastructure.

## Architecture

```
                    ┌─────────────────────────────────┐
                    │        API Gateway              │
                    │     (REST or HTTP API)          │
                    └───────────────┬─────────────────┘
                                    │
                    ┌───────────────┴─────────────────┐
                    │          Authorizer             │
                    │      (Cognito / Lambda)         │
                    └───────────────┬─────────────────┘
                                    │
    ┌───────────────────────────────┼───────────────────────────────┐
    │                               │                               │
    │  ┌─────────────┐    ┌────────┴────────┐    ┌─────────────┐  │
    │  │   Lambda    │    │     Lambda      │    │   Lambda    │  │
    │  │  (Handler)  │    │   (Processor)   │    │ (Scheduler) │  │
    │  └──────┬──────┘    └────────┬────────┘    └──────┬──────┘  │
    │         │                    │                    │         │
    │         └────────────────────┼────────────────────┘         │
    │                              │                               │
    └──────────────────────────────┼───────────────────────────────┘
                                   │
         ┌─────────────────────────┼─────────────────────────┐
         │                         │                         │
    ┌────┴────┐              ┌────┴────┐              ┌────┴────┐
    │DynamoDB │              │   SQS   │              │   S3    │
    │(NoSQL)  │              │ (Queue) │              │(Storage)│
    └─────────┘              └─────────┘              └─────────┘
```

## Components

| Component | Purpose |
|-----------|---------|
| API Gateway | HTTP/REST API endpoint |
| Cognito | User authentication |
| Lambda | Serverless compute |
| DynamoDB | NoSQL database |
| SQS | Message queue |
| S3 | Object storage |
| CloudWatch | Monitoring |

## Prerequisites

- AWS account
- Terraform >= 1.5.0
- Atmos >= 1.50.0
- Python 3.11 or Node.js 18+

## Quick Start

1. **Deploy Infrastructure**:
```bash
atmos terraform apply iam -s <stack>
atmos terraform apply dynamodb -s <stack>
atmos terraform apply lambda -s <stack>
atmos terraform apply apigateway -s <stack>
```

2. **Deploy Lambda Code**:
```bash
# Package and upload Lambda functions
./scripts/deploy-lambda.sh
```

3. **Test API**:
```bash
curl -X GET https://<api-id>.execute-api.<region>.amazonaws.com/<stage>/health
```

## Cost Estimate

| Traffic | Monthly Cost |
|---------|--------------|
| 1M requests | $5-20 |
| 10M requests | $50-100 |
| 100M requests | $200-500 |

## Features

### API Gateway

- REST or HTTP API options
- Custom domain support
- API keys and usage plans
- Request/response transformation
- CORS configuration

### Lambda

- Python 3.11 / Node.js 18 / Go
- ARM64 architecture support
- Provisioned concurrency option
- X-Ray tracing
- Lambda Powertools integration

### DynamoDB

- Single-table design support
- Global Secondary Indexes
- Point-in-time recovery
- DynamoDB Streams
- TTL support

## API Design Patterns

### Single-Table Design

```
PK          | SK              | Data
------------|-----------------|-------------
USER#123    | PROFILE         | {name, email}
USER#123    | ORDER#456       | {total, status}
ORDER#456   | METADATA        | {created_at}
```

### Lambda Handler Pattern

```python
from aws_lambda_powertools import Logger, Tracer, Metrics
from aws_lambda_powertools.event_handler import APIGatewayRestResolver

logger = Logger()
tracer = Tracer()
metrics = Metrics()
app = APIGatewayRestResolver()

@app.get("/items/<item_id>")
@tracer.capture_method
def get_item(item_id: str):
    return {"item_id": item_id}

@logger.inject_lambda_context
@tracer.capture_lambda_handler
@metrics.log_metrics
def handler(event, context):
    return app.resolve(event, context)
```

## Best Practices

1. **Cold Start Optimization**: Use ARM64, minimize dependencies
2. **Connection Pooling**: Use /tmp for reuse
3. **Error Handling**: Return proper HTTP status codes
4. **Idempotency**: Handle duplicate requests
5. **Logging**: Use structured JSON logs
