# Athena Workgroup

Production-ready Amazon Athena workgroup with query limits, encryption, cost control, and CloudWatch monitoring.

## Features

- Workgroup with per-query data limits
- S3 output location with encryption
- CloudWatch metrics and alarms
- Cost control settings
- Named queries for common operations
- Data catalog integration
- Prepared statements
- IAM policy generation
- Query execution monitoring

## Usage

```hcl
module "athena_workgroup" {
  source = "./_library/data-platform/athena-workgroup"

  workgroup_name  = "analytics-workgroup"
  output_location = "s3://athena-results/queries/"

  encryption_option = "SSE_KMS"
  kms_key_arn       = aws_kms_key.athena.arn

  bytes_scanned_cutoff      = 10737418240
  enforce_workgroup_config  = true
  enable_cloudwatch_metrics = true

  named_queries = {
    daily_summary = {
      database    = "analytics"
      query       = file("queries/daily_summary.sql")
      description = "Daily analytics summary"
    }
  }

  enable_cost_control        = true
  daily_cost_threshold_bytes = 1099511627776

  output_bucket_arn = aws_s3_bucket.results.arn
  source_bucket_arns = [
    aws_s3_bucket.data_lake.arn
  ]

  enable_monitoring = true
  alarm_actions     = [aws_sns_topic.alerts.arn]

  tags = {
    Environment = "production"
    Service     = "analytics"
  }
}
```

## Inputs

See `variables.tf` for complete list of variables.

## Outputs

See `outputs.tf` for complete list of outputs.
