# CloudWatch Alarms Module

Production-ready CloudWatch alarm factory with templates, composite alarms, and auto-remediation.

## Features

- **Alarm Templates**: Pre-configured alarms for CPU, memory, disk
- **Anomaly Detection**: ML-powered anomaly detection alarms
- **Composite Alarms**: Complex alarm conditions
- **Auto-Remediation**: Lambda-based automatic remediation
- **SNS Integration**: Built-in SNS topic and subscriptions
- **Custom Alarms**: Flexible custom alarm configuration

## Usage

```hcl
module "alarms" {
  source = "../../_library/observability/cloudwatch-alarms"

  name_prefix = "production"

  create_cpu_alarms    = true
  create_memory_alarms = true
  create_disk_alarms   = true

  cpu_threshold    = 80
  memory_threshold = 85
  disk_threshold   = 90

  enable_anomaly_detection  = true
  create_composite_alarms   = true
  enable_auto_remediation   = true

  alarm_email_endpoints = [
    "ops@example.com",
    "oncall@example.com"
  ]

  custom_alarms = {
    "api-latency" = {
      comparison_operator = "GreaterThanThreshold"
      evaluation_periods  = 2
      metric_name         = "Latency"
      namespace           = "AWS/ApiGateway"
      period              = 300
      statistic           = "Average"
      threshold           = 1000
      description         = "API latency exceeds 1 second"
    }
  }

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

## Alarm Types

- **Standard**: CPU, memory, disk
- **Anomaly Detection**: ML-based threshold detection
- **Composite**: Multiple conditions combined
- **Custom**: User-defined metric alarms

## Cost Estimation

~$0.10/month per alarm + SNS notification costs.
