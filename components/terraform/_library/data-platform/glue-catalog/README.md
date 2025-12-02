# Glue Catalog

Production-ready AWS Glue Data Catalog with database, tables, crawlers, schema registry, and data quality rules.

## Features

- Glue catalog database and tables
- Automated crawlers for S3, JDBC, and DynamoDB
- Schema registry with version control
- Data quality rulesets
- ETL job templates
- Athena integration
- CloudWatch monitoring
- Configurable schema change policies

## Usage

```hcl
module "glue_catalog" {
  source = "./_library/data-platform/glue-catalog"

  database_name        = "analytics"
  database_description = "Analytics data lake"

  crawlers = {
    raw_events = {
      description = "Crawl raw event data"
      schedule    = "cron(0 2 * * ? *)"
      s3_targets = [{
        path = "s3://data-lake/raw/events/"
      }]
    }
  }

  s3_data_locations = [
    "arn:aws:s3:::data-lake",
  ]

  create_schema_registry = true
  schemas = {
    event_schema = {
      data_format       = "AVRO"
      compatibility     = "BACKWARD"
      schema_definition = file("schemas/event.avsc")
    }
  }

  enable_monitoring = true
  alarm_actions     = [aws_sns_topic.alerts.arn]

  tags = {
    Environment = "production"
    Service     = "data-catalog"
  }
}
```

## Inputs

See `variables.tf` for complete list of variables.

## Outputs

See `outputs.tf` for complete list of outputs.
