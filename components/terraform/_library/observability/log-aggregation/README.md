# Log Aggregation Module

Production-ready CloudWatch Logs centralization with Kinesis streaming, S3 export, and Athena queries.

## Features

- **Centralized Logging**: Aggregate logs from multiple services
- **Kinesis Streaming**: Real-time log streaming
- **S3 Export**: Automated export with lifecycle policies
- **Athena Queries**: SQL-based log analysis
- **Metric Filters**: Extract metrics from logs
- **Subscription Filters**: Route logs to external systems
- **Retention Policies**: Automated log retention management

## Usage

```hcl
module "log_aggregation" {
  source = "../../_library/observability/log-aggregation"

  name_prefix         = "production"
  log_retention_days  = 30

  service_log_groups = {
    lambda = {
      retention_days = 7
      filter_pattern = "[ERROR]"
    }
    ecs = {
      retention_days = 30
      filter_pattern = ""
    }
    api-gateway = {
      retention_days = 14
    }
  }

  enable_kinesis_streaming = true
  kinesis_shard_count      = 2
  kinesis_on_demand        = false

  enable_s3_export            = true
  s3_transition_to_ia_days    = 90
  s3_transition_to_glacier_days = 180
  s3_expiration_days          = 365

  enable_athena_queries = true

  create_error_metric_filter = true
  error_filter_pattern       = "[ERROR]"

  custom_metric_filters = {
    "warning-count" = {
      pattern     = "[WARN]"
      metric_name = "WarningCount"
      value       = "1"
      unit        = "Count"
    }
  }

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

## Architecture

- **CloudWatch Logs**: Central log storage
- **Kinesis**: Real-time streaming
- **Lambda**: Automated S3 export
- **S3**: Long-term archival with lifecycle
- **Athena**: SQL queries on archived logs

## Cost Estimation

- Log ingestion: ~$0.50/GB
- Kinesis: ~$0.015/shard-hour + $0.014/GB
- S3 storage: ~$0.023/GB (transitions to IA/Glacier)
- Athena: ~$5/TB scanned
