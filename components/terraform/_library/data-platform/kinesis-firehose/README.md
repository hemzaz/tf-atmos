# Kinesis Firehose

Production-ready Kinesis Firehose delivery stream with data transformation, compression, and multiple destination support.

## Features

- Delivery to S3, OpenSearch, or Redshift
- Lambda data transformation
- Compression (GZIP, Snappy, etc.)
- JSON to Parquet conversion
- Buffering configuration
- S3 backup for all records or failures
- KMS encryption
- CloudWatch monitoring with alarms
- Error handling and retry logic

## Usage

```hcl
module "firehose" {
  source = "./_library/data-platform/kinesis-firehose"

  name_prefix             = "prod-events"
  destination             = "extended_s3"
  kinesis_source_stream_arn = aws_kinesis_stream.events.arn

  s3_bucket_arn          = aws_s3_bucket.data_lake.arn
  s3_prefix              = "events/year=!{timestamp:yyyy}/month=!{timestamp:MM}/"
  s3_compression_format  = "GZIP"

  buffer_size_mb          = 5
  buffer_interval_seconds = 300

  enable_transformation      = true
  transformation_lambda_arn  = aws_lambda_function.transformer.arn

  enable_parquet_conversion = true
  glue_database_name        = "analytics"
  glue_table_name           = "events"

  kms_key_arn = aws_kms_key.data.arn

  enable_monitoring = true
  alarm_actions     = [aws_sns_topic.alerts.arn]

  tags = {
    Environment = "production"
    Service     = "data-pipeline"
  }
}
```

## Inputs

See `variables.tf` for complete list of variables.

## Outputs

See `outputs.tf` for complete list of outputs.
