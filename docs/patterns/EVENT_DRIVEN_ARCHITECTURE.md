# Event-Driven Architecture Pattern

## Overview

The Event-Driven Architecture pattern provides a complete serverless event processing infrastructure using AWS services. This pattern enables loosely coupled microservices communication, asynchronous workflow orchestration, and reliable event delivery.

## Architecture Diagram

```
                                    +------------------+
                                    |   Event          |
                                    |   Producers      |
                                    +--------+---------+
                                             |
                                             v
+----------------+              +------------------------+
|   Event        |   Rules     |                        |
|   Archive      |<------------|    EventBridge         |
|   (S3)         |             |    Event Bus           |
+----------------+              +------------------------+
                                    |    |    |    |
                    +---------------+    |    |    +----------------+
                    |                    |    |                     |
                    v                    v    v                     v
            +-------+-------+    +------+----+----+         +------+------+
            |   SQS Queue   |    |   Lambda       |         |   Step      |
            |   (Buffered)  |    |   Direct       |         |   Functions |
            +-------+-------+    +------+---------+         +------+------+
                    |                    |                         |
                    v                    v                         v
            +-------+-------+    +------+---------+         +------+------+
            |   Lambda      |    |   DynamoDB     |         |   Complex   |
            |   Consumer    |    |   State        |         |   Workflow  |
            +-------+-------+    +----------------+         +-------------+
                    |
                    v
            +-------+-------+              +------------------+
            |   SNS Topic   |------------->|   Subscribers    |
            |   (Fan-out)   |              |   (Email, SQS,   |
            +---------------+              |   Lambda, HTTP)  |
                                           +------------------+
                    |
                    v
            +-------+-------+
            |   DLQ         |
            |   (Failed)    |
            +---------------+
```

## Components

### Event Bus Layer

| Component | Description | Purpose |
|-----------|-------------|---------|
| EventBridge Event Bus | Central event routing hub | Routes events to appropriate targets based on rules |
| EventBridge Rules | Event filtering and routing | Match events and forward to targets |
| Event Archive | Long-term event storage | Compliance, replay, debugging |
| Schema Registry | Event schema discovery | Documentation, validation |

### Consumer Layer

| Component | Description | Purpose |
|-----------|-------------|---------|
| Lambda Consumers | Serverless event processors | Process events with auto-scaling |
| SQS Queues | Event buffering | Decouple producers from consumers |
| DLQ | Dead letter queue | Capture failed events for retry |

### Orchestration Layer

| Component | Description | Purpose |
|-----------|-------------|---------|
| Step Functions | Workflow orchestration | Coordinate multi-step processes |
| State Machines | Visual workflow definition | Define complex business logic |

### Fan-out Layer

| Component | Description | Purpose |
|-----------|-------------|---------|
| SNS Topics | Pub/sub messaging | Distribute events to multiple subscribers |
| Subscriptions | Topic subscriptions | Connect topics to targets |

## Deployment

### Prerequisites

- AWS Account with appropriate permissions
- Atmos CLI installed and configured
- Stack configuration completed

### Deploy the Pattern

```bash
# Plan the deployment
atmos workflow plan-event-driven -f patterns.yaml stack=<tenant>-<environment>

# Deploy all components
atmos workflow deploy-event-driven -f patterns.yaml stack=<tenant>-<environment>

# Validate deployment
atmos workflow validate-pattern -f patterns.yaml pattern=event-driven stack=<tenant>-<environment>
```

### Environment-Specific Configurations

#### Development
- Reduced log retention (7 days)
- Lower Lambda memory allocation
- Verbose logging enabled
- No provisioned concurrency

#### Staging
- Moderate log retention (14 days)
- Standard Lambda memory
- Standard logging

#### Production
- Extended log retention (90 days)
- Increased Lambda memory and concurrency
- Provisioned concurrency enabled
- ERROR level logging for Step Functions

## Event Flow

### Standard Event Processing

1. **Event Production**: Services publish events to EventBridge
   ```json
   {
     "Source": "com.company.orders",
     "DetailType": "OrderCreated",
     "Detail": {
       "orderId": "123",
       "customerId": "456",
       "amount": 99.99
     }
   }
   ```

2. **Event Routing**: EventBridge rules match and route events
   ```yaml
   EventPattern:
     source:
       - "com.company.orders"
     detail-type:
       - "OrderCreated"
   ```

3. **Queue Buffering**: SQS queues buffer events for reliable processing
   - Configurable visibility timeout
   - Automatic retry with backoff
   - DLQ for failed messages

4. **Event Processing**: Lambda consumers process events
   - Batch processing support
   - Partial batch failure reporting
   - X-Ray tracing enabled

5. **State Updates**: DynamoDB stores processing state
   - Single-table design
   - TTL for automatic cleanup

### Workflow Orchestration

For complex, multi-step processes:

```
START
  |
  v
[Validate Input] --> Error? --> [Handle Error] --> FAIL
  |
  v
[Choice]
  |
  +-- Requires Approval? --> [Wait for Approval] --> Timeout? --> [Handle Timeout] --> FAIL
  |                                |
  +-- High Priority? -------------+
  |                               |
  v                               v
[Sequential Processing]    [Parallel Processing]
  |                               |
  +<------------------------------+
  |
  v
[Publish Result]
  |
  v
END
```

## Cost Estimation

### Monthly Cost Breakdown

| Component | Minimum | Typical | Maximum |
|-----------|---------|---------|---------|
| EventBridge | $1 | $10 | $100 |
| Lambda | $0 | $20 | $200 |
| SQS | $0 | $5 | $50 |
| SNS | $0 | $5 | $50 |
| Step Functions | $0 | $25 | $250 |
| DynamoDB | $1 | $10 | $100 |
| S3 (Audit) | $1 | $10 | $100 |
| CloudWatch | $5 | $25 | $100 |
| KMS | $1 | $1 | $10 |
| Firehose | $0 | $20 | $200 |
| **TOTAL** | **$9** | **$131** | **$1,160** |

### Cost Optimization Tips

1. **Use SQS Batching**: Process multiple messages per Lambda invocation
2. **Event Filtering**: Filter events at EventBridge level to reduce Lambda invocations
3. **Express Workflows**: Use Step Functions Express for high-volume, short-duration workflows
4. **Archive to S3**: Use S3 for long-term event storage instead of keeping in EventBridge

## Testing Strategy

### Unit Tests

```bash
# Run Lambda handler tests
pytest tests/unit/lambda/ -v

# Validate Step Functions definition
aws stepfunctions validate-state-machine-definition \
  --definition file://state-machine.json
```

### Integration Tests

```bash
# Test complete event flow
atmos workflow test-pattern-integration -f patterns.yaml \
  pattern=event-driven \
  stack=<tenant>-<environment>
```

### Load Tests

```bash
# Run load tests
atmos workflow test-pattern-load -f patterns.yaml \
  pattern=event-driven \
  stack=<tenant>-<environment> \
  rate=1000 \
  duration=5m
```

## Monitoring

### CloudWatch Dashboard

The pattern deploys a comprehensive dashboard with:

- EventBridge metrics (matched events, failed invocations)
- Lambda metrics (invocations, errors, duration)
- SQS metrics (messages visible, age of oldest message)
- Step Functions metrics (executions started/failed)
- DLQ monitoring (immediate alerting)

### Alarms

| Alarm | Threshold | Description |
|-------|-----------|-------------|
| EventBridge Failed Invocations | > 10 in 5 min | Target invocation failures |
| Lambda Error Rate | > 10 errors in 5 min | Processing errors |
| Lambda Duration P99 | > 10 seconds | Performance degradation |
| SQS Queue Depth | > 10,000 messages | Processing backlog |
| DLQ Messages | >= 1 message | Failed events requiring attention |
| Step Functions Failed | >= 1 failure | Workflow execution failures |
| Step Functions Throttled | > 5 in 5 min | Throttling detected |

## Security

### Encryption

- All data encrypted at rest using KMS
- SQS messages encrypted with KMS
- SNS topics encrypted with KMS
- S3 buckets encrypted with KMS
- EventBridge archive encrypted with KMS

### IAM Policies

The pattern implements least-privilege IAM policies:

- Lambda functions only have access to their required resources
- EventBridge can only invoke specified targets
- Step Functions can only invoke approved Lambda functions

### Audit Trail

- All events archived to S3 via Firehose
- CloudWatch Logs for all Lambda functions
- Step Functions execution history
- EventBridge event archive for replay

## Troubleshooting

### Common Issues

#### Events Not Being Processed

1. Check EventBridge rule is enabled
2. Verify event pattern matches incoming events
3. Check target permissions
4. Review CloudWatch Logs for errors

#### High DLQ Count

1. Check Lambda error logs
2. Verify downstream service availability
3. Check for data format issues
4. Review retry configuration

#### Step Functions Failures

1. Check state machine execution history
2. Review individual state errors
3. Verify IAM permissions
4. Check timeout configurations

### Debugging Commands

```bash
# Check EventBridge rules
aws events list-rules --event-bus-name <event-bus-name>

# Check Lambda errors
aws logs filter-log-events \
  --log-group-name /aws/lambda/<function-name> \
  --filter-pattern "ERROR"

# Check DLQ messages
aws sqs receive-message \
  --queue-url <dlq-url> \
  --max-number-of-messages 10

# Check Step Functions executions
aws stepfunctions list-executions \
  --state-machine-arn <state-machine-arn> \
  --status-filter FAILED
```

## Best Practices

### Event Design

1. **Use Meaningful Event Types**: `OrderCreated`, not `Event1`
2. **Include Correlation IDs**: For tracing across services
3. **Version Your Events**: Include schema version for evolution
4. **Keep Events Small**: Store large payloads in S3, include reference

### Error Handling

1. **Implement Retry Logic**: Use exponential backoff
2. **Use DLQs**: Never lose events
3. **Set Appropriate Timeouts**: Match business requirements
4. **Handle Partial Failures**: Use batch item failure reporting

### Performance

1. **Right-size Lambda Memory**: More memory = more CPU
2. **Use Provisioned Concurrency**: For consistent latency
3. **Batch Processing**: Process multiple events per invocation
4. **Filter Early**: Use EventBridge filtering, not Lambda filtering

## Related Patterns

- [API Gateway Pattern](./API_GATEWAY_PATTERNS.md): REST/HTTP APIs with event publishing
- [Streaming Pipeline Pattern](./STREAMING_PIPELINES.md): Real-time data processing
- [Microservices Platform](../library/patterns/microservices-platform.md): Complete microservices infrastructure

## References

- [AWS Event-Driven Architecture](https://aws.amazon.com/event-driven-architecture/)
- [Amazon EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)
- [AWS Step Functions Developer Guide](https://docs.aws.amazon.com/step-functions/latest/dg/)
- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
