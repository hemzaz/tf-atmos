# Streaming Pipelines Pattern

## Overview

The Streaming Pipeline pattern provides a complete real-time data processing infrastructure using AWS Kinesis services. This pattern enables high-throughput data ingestion, real-time stream processing, and delivery to multiple destinations including S3 data lakes, OpenSearch, and Redshift.

## Architecture Diagram

```
                              +------------------+
                              |   Data Sources   |
                              |   (IoT, Apps,    |
                              |   Logs, Events)  |
                              +--------+---------+
                                       |
              +------------------------+------------------------+
              |                        |                        |
              v                        v                        v
      +-------+------+        +-------+-------+        +-------+-------+
      |   Kinesis    |        |   API Gateway  |        |   Kinesis    |
      |   Agent      |        |   (HTTP PUT)   |        |   SDK        |
      +--------------+        +-------+-------+        +---------------+
              |                        |                        |
              +------------------------+------------------------+
                                       |
                                       v
                           +-----------+-----------+
                           |   Kinesis Data       |
                           |   Streams            |
                           |   (Ingest Stream)    |
                           +-----------+-----------+
                                       |
              +------------------------+------------------------+
              |                        |                        |
              v                        v                        v
      +-------+------+        +-------+-------+        +-------+-------+
      |   Lambda     |        |   Kinesis      |        |   Enhanced   |
      |   Processor  |        |   Analytics    |        |   Fan-Out    |
      +--------------+        +---------------+        +---------------+
              |                        |                        |
              +------------------------+------------------------+
                                       |
                                       v
                           +-----------+-----------+
                           |   Kinesis Data       |
                           |   Streams            |
                           |   (Enriched Stream)  |
                           +-----------+-----------+
                                       |
              +------------------------+------------------------+
              |                        |                        |
              v                        v                        v
      +-------+------+        +-------+-------+        +-------+-------+
      |   Firehose   |        |   Firehose    |        |   Firehose   |
      |   to S3      |        |   to OS       |        |   to Redshift|
      +--------------+        +---------------+        +---------------+
              |                        |                        |
              v                        v                        v
      +-------+------+        +-------+-------+        +-------+-------+
      |   S3         |        |   OpenSearch  |        |   Redshift   |
      |   Data Lake  |        |   Analytics   |        |   Warehouse  |
      +--------------+        +---------------+        +---------------+
```

## Components

### Ingestion Layer

| Component | Description | Purpose |
|-----------|-------------|---------|
| Kinesis Data Streams | High-throughput data stream | Ingest millions of records/second |
| API Gateway | HTTP ingestion endpoint | REST-based data ingestion |
| Kinesis Agent | Log file shipper | Automated log ingestion |

### Processing Layer

| Component | Description | Purpose |
|-----------|-------------|---------|
| Lambda Processor | Serverless processing | Record enrichment, transformation |
| Kinesis Data Analytics | Flink-based analytics | Real-time aggregations, windowing |
| DynamoDB DAX | Low-latency lookups | Reference data enrichment |

### Delivery Layer

| Component | Description | Purpose |
|-----------|-------------|---------|
| Kinesis Firehose | Managed delivery | Reliable data delivery |
| Lambda Transformer | Record transformation | Format conversion |
| Glue Data Catalog | Schema management | Parquet conversion |

### Storage Layer

| Component | Description | Purpose |
|-----------|-------------|---------|
| S3 Data Lake | Long-term storage | Analytics, ML training |
| OpenSearch | Search and analytics | Real-time dashboards |
| Redshift | Data warehouse | Business intelligence |
| DynamoDB | State storage | Processing state |

## Deployment

### Prerequisites

- AWS Account with appropriate permissions
- VPC with private subnets
- Atmos CLI installed and configured
- (Optional) Flink application JAR for Kinesis Analytics

### Deploy the Pattern

```bash
# Plan the deployment
atmos workflow plan-streaming-pipeline -f patterns.yaml stack=<tenant>-<environment>

# Deploy all components
atmos workflow deploy-streaming-pipeline -f patterns.yaml stack=<tenant>-<environment>

# Validate deployment
atmos workflow validate-pattern -f patterns.yaml pattern=streaming-pipeline stack=<tenant>-<environment>
```

### Environment-Specific Configurations

#### Development
- Provisioned mode with 1 shard
- No enhanced fan-out
- No Kinesis Analytics
- Single ElastiCache node
- Short data retention (24 hours)

#### Staging
- On-demand capacity mode
- Enhanced fan-out enabled
- OpenSearch enabled
- Standard ElastiCache

#### Production
- On-demand capacity mode
- Enhanced fan-out enabled
- Kinesis Analytics enabled
- Multi-node ElastiCache cluster
- Extended data retention (7 days)
- Long-term S3 archival (7 years)

## Data Flow

### Record Processing Pipeline

1. **Data Ingestion**
   ```json
   {
     "event_id": "evt-123",
     "event_type": "page_view",
     "timestamp": "2024-01-15T10:30:00Z",
     "user_id": "user-456",
     "page": "/products/123",
     "metadata": {
       "browser": "Chrome",
       "device": "mobile"
     }
   }
   ```

2. **Stream Processing**
   - Lambda enriches with user profile data
   - Adds derived fields (session_id, geo_location)
   - Validates and normalizes data

3. **Delivery to Destinations**
   - S3: Parquet format, partitioned by date
   - OpenSearch: Real-time indexing
   - Redshift: Batch loading

### Kinesis Data Streams Configuration

```yaml
kinesis-ingest:
  stream_name: "company-prod-ingest-stream"
  stream_mode: "ON_DEMAND"  # or PROVISIONED
  retention_period: 168     # 7 days
  encryption_type: "KMS"

  # Shard-level metrics
  shard_level_metrics:
    - "IncomingBytes"
    - "IncomingRecords"
    - "IteratorAgeMilliseconds"
```

### Lambda Stream Processor

```python
import json
import boto3
from aws_lambda_powertools import Logger, Tracer

logger = Logger()
tracer = Tracer()

@logger.inject_lambda_context
@tracer.capture_lambda_handler
def handler(event, context):
    output_records = []

    for record in event['Records']:
        # Decode record data
        payload = json.loads(
            base64.b64decode(record['kinesis']['data']).decode('utf-8')
        )

        # Enrich with reference data
        enriched = enrich_record(payload)

        # Transform for output
        output_records.append({
            'recordId': record['eventID'],
            'result': 'Ok',
            'data': base64.b64encode(
                json.dumps(enriched).encode('utf-8')
            ).decode('utf-8')
        })

    return {'records': output_records}
```

### Firehose Configuration

```yaml
firehose-s3:
  delivery_stream_name: "company-prod-s3-delivery"

  extended_s3_configuration:
    prefix: "data/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"
    error_output_prefix: "errors/!{firehose:error-output-type}/"

    # Buffering
    buffering_size: 128    # MB
    buffering_interval: 300 # seconds

    # Format conversion
    data_format_conversion:
      output_format: PARQUET
      compression: GZIP
```

## Cost Estimation

### Monthly Cost Breakdown

| Component | Minimum | Typical | Maximum |
|-----------|---------|---------|---------|
| Kinesis Data Streams | $15 | $75 | $500 |
| Kinesis Firehose | $10 | $50 | $300 |
| Kinesis Analytics | $0 | $80 | $500 |
| Lambda | $0 | $30 | $200 |
| S3 | $5 | $50 | $500 |
| OpenSearch | $70 | $200 | $1,000 |
| DynamoDB | $1 | $20 | $100 |
| ElastiCache | $25 | $100 | $400 |
| Glue | $1 | $5 | $50 |
| CloudWatch | $5 | $30 | $100 |
| KMS | $1 | $1 | $10 |
| **TOTAL** | **$133** | **$641** | **$3,660** |

### Cost Optimization Tips

1. **On-Demand Capacity**: Use for variable workloads
2. **Data Compression**: Compress before ingestion
3. **S3 Intelligent-Tiering**: Automatic storage optimization
4. **Reserved Capacity**: For predictable workloads
5. **Firehose Buffering**: Larger buffers = fewer S3 requests
6. **Right-size OpenSearch**: Match instance to workload

### Cost Calculation Examples

```
# Kinesis Data Streams (On-Demand)
Records: 10 million/day
Data: 1 KB/record = 10 GB/day
PUT payload units: 10M / day * 31 = 310M/month
Cost: 310M * $0.014/million = $4.34/month + shard hours

# Kinesis Firehose
Data ingested: 10 GB/day * 31 = 310 GB/month
Cost: 310 GB * $0.029/GB = $8.99/month

# S3 Storage
Daily ingestion: 5 GB (after compression)
Monthly storage: 5 GB * 31 = 155 GB
Cost: 155 GB * $0.023/GB = $3.57/month
```

## Testing Strategy

### Unit Tests

```bash
# Test Lambda processors
pytest tests/unit/processors/ -v

# Test transformers
pytest tests/unit/transformers/ -v
```

### Integration Tests

```bash
# End-to-end pipeline test
atmos workflow test-pattern-integration -f patterns.yaml \
  pattern=streaming-pipeline \
  stack=<tenant>-<environment>
```

### Load Tests

```bash
# Generate load test data
atmos workflow test-pattern-load -f patterns.yaml \
  pattern=streaming-pipeline \
  stack=<tenant>-<environment> \
  rate=10000 \
  duration=10m
```

### Data Quality Tests

```python
# Validate data in S3
import awswrangler as wr

df = wr.s3.read_parquet(
    path='s3://company-prod-data-lake/data/',
    partition_filter=lambda x: x['year'] == '2024'
)

# Check for nulls
assert df['event_id'].notna().all()

# Check for duplicates
assert df['event_id'].is_unique

# Validate timestamps
assert (df['timestamp'] > '2024-01-01').all()
```

## Monitoring

### CloudWatch Dashboard

The pattern deploys a comprehensive dashboard with:

- Kinesis throughput (records/bytes per second)
- Iterator age (processing lag)
- Lambda invocations and errors
- Firehose delivery success rate
- Data freshness metrics
- DLQ message count

### Key Metrics

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| GetRecords.IteratorAgeMilliseconds | Processing lag | > 5 minutes |
| WriteProvisionedThroughputExceeded | Write throttling | > 0 |
| ReadProvisionedThroughputExceeded | Read throttling | > 0 |
| Lambda Errors | Processing failures | > 10 in 5 min |
| DeliveryToS3.DataFreshness | Firehose lag | > 15 minutes |
| DLQ Messages | Failed records | >= 1 |

### Alarms

```yaml
alarms:
  kinesis-iterator-age:
    metric_name: "GetRecords.IteratorAgeMilliseconds"
    threshold: 300000  # 5 minutes
    period: 300
    alarm_description: "Processing is falling behind"

  kinesis-write-throttled:
    metric_name: "WriteProvisionedThroughputExceeded"
    threshold: 0
    alarm_description: "Write throttling detected"

  lambda-errors:
    metric_name: "Errors"
    threshold: 10
    alarm_description: "Lambda processing errors"

  firehose-freshness:
    metric_name: "DeliveryToS3.DataFreshness"
    threshold: 900  # 15 minutes
    alarm_description: "Firehose delivery falling behind"
```

## Scaling

### Kinesis Data Streams

| Mode | Scaling | Use Case |
|------|---------|----------|
| On-Demand | Automatic | Variable workloads |
| Provisioned | Manual/UpdateShardCount | Predictable workloads |

### Scaling Calculations

```
# Calculate required shards (Provisioned mode)
Write capacity per shard: 1 MB/s or 1,000 records/s
Read capacity per shard: 2 MB/s or 2,000 records/s

# Example: 5 MB/s input
Shards needed: max(5/1, 5/2) = 5 shards

# With 20% headroom
Recommended: 5 * 1.2 = 6 shards
```

### Lambda Scaling

```yaml
lambda-stream-processor:
  # Parallelization factor for Kinesis trigger
  parallelization_factor: 4  # Up to 10

  # Reserved concurrency (cap)
  reserved_concurrent_executions: 100

  # Batch settings
  batch_size: 100
  maximum_batching_window_in_seconds: 5
```

### OpenSearch Scaling

| Workload | Instance Type | Count |
|----------|---------------|-------|
| Development | r6g.large | 2 |
| Staging | r6g.large | 2 |
| Production | r6g.xlarge | 3 + 3 masters |

## Security

### Encryption

- **In Transit**: TLS for all connections
- **At Rest**: KMS encryption for Kinesis, S3, OpenSearch

### IAM Policies

```yaml
# Lambda stream processor
policies:
  kinesis:
    - Action:
        - "kinesis:GetRecords"
        - "kinesis:GetShardIterator"
        - "kinesis:DescribeStream"
        - "kinesis:PutRecord"
        - "kinesis:PutRecords"
      Resource:
        - "arn:aws:kinesis:*:*:stream/company-*"

  dynamodb:
    - Action:
        - "dynamodb:GetItem"
        - "dynamodb:Query"
      Resource:
        - "arn:aws:dynamodb:*:*:table/company-*-lookup"
```

### Network Security

- VPC endpoints for Kinesis, DynamoDB, S3
- Security groups restrict access
- Private subnets for Lambda, OpenSearch

## Troubleshooting

### Common Issues

#### High Iterator Age

1. Check Lambda errors
2. Increase parallelization factor
3. Optimize Lambda performance
4. Check for hot shards

```bash
# Check iterator age
aws cloudwatch get-metric-statistics \
  --namespace AWS/Kinesis \
  --metric-name GetRecords.IteratorAgeMilliseconds \
  --dimensions Name=StreamName,Value=company-prod-ingest-stream \
  --start-time 2024-01-15T00:00:00Z \
  --end-time 2024-01-15T01:00:00Z \
  --period 60 \
  --statistics Maximum
```

#### Write Throttling

1. Switch to On-Demand mode
2. Add more shards (Provisioned)
3. Implement better partition keys
4. Use batching

```bash
# Check throttling
aws cloudwatch get-metric-statistics \
  --namespace AWS/Kinesis \
  --metric-name WriteProvisionedThroughputExceeded \
  --dimensions Name=StreamName,Value=company-prod-ingest-stream \
  --start-time 2024-01-15T00:00:00Z \
  --end-time 2024-01-15T01:00:00Z \
  --period 60 \
  --statistics Sum
```

#### Firehose Delivery Failures

1. Check S3 bucket permissions
2. Verify transformation Lambda
3. Check Glue table schema
4. Review error logs

```bash
# Check Firehose errors
aws firehose describe-delivery-stream \
  --delivery-stream-name company-prod-s3-delivery

# Check CloudWatch Logs
aws logs filter-log-events \
  --log-group-name /aws/kinesisfirehose/company-prod \
  --filter-pattern "ERROR"
```

### Debugging Commands

```bash
# List shards
aws kinesis list-shards \
  --stream-name company-prod-ingest-stream

# Get shard iterator
SHARD_ITERATOR=$(aws kinesis get-shard-iterator \
  --stream-name company-prod-ingest-stream \
  --shard-id shardId-000000000000 \
  --shard-iterator-type LATEST \
  --query 'ShardIterator' --output text)

# Get records
aws kinesis get-records \
  --shard-iterator $SHARD_ITERATOR

# Check DLQ
aws sqs receive-message \
  --queue-url https://sqs.us-east-1.amazonaws.com/123456789012/company-prod-stream-dlq \
  --max-number-of-messages 10
```

## Best Practices

### Data Ingestion

1. **Use Batching**: PutRecords vs PutRecord
2. **Good Partition Keys**: Distribute evenly across shards
3. **Compress Data**: Reduce costs and throughput
4. **Validate Early**: Reject bad data at ingestion

### Stream Processing

1. **Idempotent Processing**: Handle duplicates
2. **Checkpointing**: Track processed records
3. **Error Handling**: Use DLQs, don't lose data
4. **Timeouts**: Set appropriate Lambda timeouts

### Data Lake

1. **Partitioning**: By date for efficient queries
2. **File Format**: Parquet for analytics
3. **Compression**: Gzip or Snappy
4. **Schema Evolution**: Plan for changes

### Performance

1. **Right-size Lambda**: Memory = CPU
2. **Batch Processing**: Process multiple records
3. **Caching**: Use ElastiCache/DAX for lookups
4. **Connection Pooling**: Reuse connections

## Related Patterns

- [Event-Driven Architecture](./EVENT_DRIVEN_ARCHITECTURE.md): Event processing with EventBridge
- [API Gateway Pattern](./API_GATEWAY_PATTERNS.md): API-based data ingestion
- [Data Lake Stack](../library/templates/data-lake-stack.md): Complete data lake infrastructure

## References

- [Amazon Kinesis Data Streams Developer Guide](https://docs.aws.amazon.com/streams/latest/dev/)
- [Amazon Kinesis Data Firehose Developer Guide](https://docs.aws.amazon.com/firehose/latest/dev/)
- [Amazon Kinesis Data Analytics Developer Guide](https://docs.aws.amazon.com/kinesisanalytics/latest/java/)
- [AWS Lambda with Kinesis](https://docs.aws.amazon.com/lambda/latest/dg/with-kinesis.html)
