# Streaming Pipeline Blueprint

Real-time data streaming and processing infrastructure.

## Architecture

```
    ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
    │   Producers  │     │   Kinesis    │     │   Kinesis    │
    │  (IoT, Apps, │────►│    Data      │────►│   Analytics  │
    │   Services)  │     │   Streams    │     │   (Flink)    │
    └──────────────┘     └──────────────┘     └──────┬───────┘
                                                      │
                                      ┌───────────────┼───────────────┐
                                      │               │               │
                                      ▼               ▼               ▼
                               ┌──────────┐   ┌──────────┐   ┌──────────┐
                               │ Firehose │   │ Lambda   │   │  Output  │
                               │  (S3)    │   │(Enrich)  │   │  Stream  │
                               └────┬─────┘   └────┬─────┘   └────┬─────┘
                                    │              │              │
                                    ▼              ▼              ▼
                               ┌──────────┐   ┌──────────┐   ┌──────────┐
                               │    S3    │   │ DynamoDB │   │OpenSearch│
                               │(Archive) │   │ (Lookup) │   │(Analytics│
                               └──────────┘   └──────────┘   └──────────┘
```

## Components

| Component | Purpose |
|-----------|---------|
| Kinesis Data Streams | Real-time data ingestion |
| Kinesis Data Analytics | Stream processing (Flink) |
| Lambda | Event enrichment |
| Firehose | Delivery to S3/OpenSearch |
| OpenSearch | Real-time analytics |
| DynamoDB + DAX | Low-latency lookups |
| Timestream | Time-series data |

## Quick Start

1. **Deploy Core Streaming**:
```bash
atmos terraform apply kinesis-ingest -s <stack>
atmos terraform apply kinesis-output -s <stack>
```

2. **Deploy Processing**:
```bash
atmos terraform apply kinesis-analytics -s <stack>
atmos terraform apply lambda-enrichment -s <stack>
```

3. **Deploy Delivery**:
```bash
atmos terraform apply firehose-s3 -s <stack>
atmos terraform apply firehose-opensearch -s <stack>
```

## Cost Estimate

| Throughput | Monthly Cost |
|------------|--------------|
| 1 MB/s | $100-200 |
| 10 MB/s | $500-1,000 |
| 100 MB/s | $3,000-5,000 |

## Processing Patterns

### Windowed Aggregation (Flink)

```java
DataStream<Event> events = env.addSource(kinesisSource);

events
    .keyBy(Event::getCustomerId)
    .window(TumblingEventTimeWindows.of(Time.minutes(5)))
    .aggregate(new CountAggregator())
    .addSink(kinesisSink);
```

### Event Enrichment (Lambda)

```python
import boto3
from functools import lru_cache

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('lookup')

@lru_cache(maxsize=1000)
def get_customer_info(customer_id):
    response = table.get_item(Key={'pk': customer_id})
    return response.get('Item', {})

def handler(event, context):
    for record in event['Records']:
        data = json.loads(base64.b64decode(record['data']))
        customer = get_customer_info(data['customer_id'])
        data['customer_name'] = customer.get('name')
        # ... emit enriched record
```

### Real-Time Analytics Query

```sql
-- OpenSearch query
GET events-*/_search
{
  "query": {
    "range": {
      "timestamp": {
        "gte": "now-5m"
      }
    }
  },
  "aggs": {
    "events_per_minute": {
      "date_histogram": {
        "field": "timestamp",
        "fixed_interval": "1m"
      }
    }
  }
}
```

## Monitoring

### Key Metrics

| Metric | Alert Threshold |
|--------|-----------------|
| Iterator Age | > 1 minute |
| Write Throttling | > 0 |
| Processing Lag | > 5 minutes |
| Error Rate | > 1% |
| DLQ Messages | > 0 |

### Dashboard Widgets

- Stream throughput (records/sec)
- Processing latency (p99)
- Batch processing time
- Error count
- Consumer lag

## Best Practices

1. **Shard Scaling**: Use on-demand mode or auto-scaling
2. **Checkpointing**: Enable frequent checkpoints
3. **Error Handling**: Configure DLQ for failed records
4. **Exactly-Once**: Use Flink checkpointing
5. **Backpressure**: Monitor and handle slow consumers
