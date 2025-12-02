# CloudWatch Dashboard Module

Production-ready CloudWatch dashboard builder with pre-built widget library and auto-discovery.

## Features

- **Pre-built Dashboard Types**: Infrastructure, application, cost, and security dashboards
- **Auto-Discovery**: Automatically discover EC2, RDS, and ALB resources
- **Widget Library**: Reusable widgets for common metrics
- **Custom Widgets**: Support for custom metric widgets
- **Metric Math**: Advanced metric calculations
- **Cost Tracking**: Built-in cost estimation tracking

## Usage

```hcl
module "dashboard" {
  source = "../../_library/observability/cloudwatch-dashboard"

  name_prefix = "production"
  region      = "us-east-1"

  create_infrastructure_widgets = true
  create_application_widgets    = true
  create_cost_widgets           = true
  create_security_widgets       = true

  enable_auto_discovery = true
  discovery_tags = {
    Environment = "production"
    Monitoring  = "enabled"
  }

  custom_widgets = [
    {
      type = "metric"
      properties = {
        metrics = [
          ["Custom/App", "ResponseTime", { stat = "Average" }]
        ]
        title  = "Application Response Time"
        period = 300
      }
    }
  ]

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

## Dashboard Types

- **Infrastructure**: EC2, RDS, ELB metrics
- **Application**: Lambda, API Gateway metrics and logs
- **Cost**: Billing estimates and resource usage
- **Security**: WAF metrics and security events

## Outputs

- `dashboard_arn` - Dashboard ARN
- `dashboard_name` - Dashboard name
- `dashboard_url` - Console URL
- `discovered_instance_count` - Auto-discovered resources

## Cost Estimation

~$3/month per dashboard with standard refresh rate.
