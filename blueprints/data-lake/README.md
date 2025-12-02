# Data Lake Blueprint

Modern data lake architecture for analytics and machine learning.

## Architecture

```
           Ingestion                Processing               Consumption
    ┌─────────────────────┐   ┌─────────────────────┐   ┌─────────────────┐
    │                     │   │                     │   │                 │
    │  Kinesis Streams    │   │     AWS Glue        │   │     Athena      │
    │  Kinesis Firehose   │──►│   (ETL Jobs)        │──►│  (SQL Query)    │
    │  Direct S3 Upload   │   │                     │   │                 │
    │                     │   │   Step Functions    │   │  QuickSight     │
    │  API Gateway        │   │   (Orchestration)   │   │  (BI Dashboard) │
    │                     │   │                     │   │                 │
    └─────────────────────┘   └─────────────────────┘   └─────────────────┘
              │                         │                       │
              └─────────────────────────┼───────────────────────┘
                                        │
    ┌───────────────────────────────────┼───────────────────────────────────┐
    │                                   │                                   │
    │    ┌───────────┐    ┌────────────┴────────────┐    ┌───────────┐    │
    │    │    Raw    │───►│      Processed          │───►│  Curated  │    │
    │    │   Zone    │    │        Zone             │    │   Zone    │    │
    │    │   (S3)    │    │        (S3)             │    │   (S3)    │    │
    │    └───────────┘    └─────────────────────────┘    └───────────┘    │
    │                                                                      │
    │                         Data Lake Storage                            │
    └──────────────────────────────────────────────────────────────────────┘
                                        │
                           ┌────────────┴────────────┐
                           │      Glue Catalog       │
                           │    (Data Governance)    │
                           │      Lake Formation     │
                           └─────────────────────────┘
```

## Data Zones

| Zone | Purpose | Format | Retention |
|------|---------|--------|-----------|
| Raw | Original data as received | JSON, CSV | 90 days |
| Processed | Cleaned, validated data | Parquet | 1 year |
| Curated | Business-ready datasets | Parquet | 5+ years |

## Components

| Component | Purpose |
|-----------|---------|
| S3 | Data storage (raw, processed, curated) |
| Kinesis | Real-time data ingestion |
| Firehose | Stream to S3 delivery |
| Glue | ETL jobs, crawlers, catalog |
| Lake Formation | Data governance |
| Athena | SQL analytics |

## Quick Start

1. **Deploy Storage**:
```bash
atmos terraform apply s3-raw -s <stack>
atmos terraform apply s3-processed -s <stack>
atmos terraform apply s3-curated -s <stack>
```

2. **Deploy Ingestion**:
```bash
atmos terraform apply kinesis-stream -s <stack>
atmos terraform apply firehose -s <stack>
```

3. **Deploy Processing**:
```bash
atmos terraform apply glue-database -s <stack>
atmos terraform apply glue-crawler -s <stack>
atmos terraform apply glue-etl -s <stack>
```

4. **Deploy Query Layer**:
```bash
atmos terraform apply athena -s <stack>
```

## Cost Estimate

| Data Volume | Monthly Cost |
|-------------|--------------|
| 100 GB | $50-100 |
| 1 TB | $200-400 |
| 10 TB | $1,000-2,000 |

## Data Governance

### Lake Formation Permissions

```yaml
permissions:
  data_engineers:
    - database: ALL
    - table: ALL
  data_analysts:
    - database: SELECT, DESCRIBE
    - table: SELECT
  data_scientists:
    - database: SELECT, DESCRIBE
    - table: SELECT
    - column: specific columns only
```

### Data Classification

- **Public**: No restrictions
- **Internal**: Employee access only
- **Confidential**: Need-to-know basis
- **Restricted**: Highly sensitive (PII, financial)

## ETL Patterns

### Incremental Load

```python
# Glue job - incremental processing
job = glueContext.create_dynamic_frame.from_catalog(
    database="raw",
    table_name="events",
    push_down_predicate="partition_0 >= '2024-01-01'"
)
```

### Data Quality Checks

```python
# Data quality validation
from awsglue.transforms import *
from pydeequ.checks import *

check = Check(spark, CheckLevel.Error, "Data Quality")
check.hasSize(lambda x: x > 0)
check.isComplete("customer_id")
check.isUnique("order_id")
```

## Best Practices

1. **Partitioning**: Use date-based partitions
2. **File Format**: Parquet with snappy compression
3. **File Size**: 128MB - 1GB per file
4. **Schema Evolution**: Use Glue Schema Registry
5. **Cost Control**: Enable S3 Intelligent-Tiering
