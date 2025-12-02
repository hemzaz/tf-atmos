# X-Ray Tracing Module

Production-ready AWS X-Ray configuration with sampling rules, groups, and service integrations.

## Features

- **Sampling Rules**: Cost-optimized sampling strategies by environment
- **X-Ray Groups**: Pre-configured groups for errors and slow requests
- **Service Integration**: Lambda, ECS, API Gateway support
- **Insights**: X-Ray Insights with notifications
- **Cost Optimization**: Environment-based sampling rates
- **Service Map**: Automatic service dependency mapping

## Usage

```hcl
module "xray_tracing" {
  source = "../../_library/observability/xray-tracing"

  name_prefix = "production"
  environment = "production"

  create_default_sampling_rule = true
  enable_high_value_sampling   = true
  high_value_url_pattern       = "/api/v1/payment/*"

  create_error_group         = true
  create_slow_requests_group = true
  slow_request_threshold     = 3

  enable_insights               = true
  enable_insights_notifications = true

  enable_lambda_integration = true
  lambda_function_names = [
    "api-handler",
    "data-processor"
  ]

  enable_api_gateway_integration = true
  api_gateway_names = [
    "main-api"
  ]

  enable_cost_optimization = true
  create_trace_alarms      = true

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

## Sampling Strategies

- **Production**: 5% sampling, 1 trace/sec reservoir
- **Staging**: 20% sampling, 5 traces/sec reservoir
- **Development**: 100% sampling, 10 traces/sec reservoir

## Cost Estimation

~$5 per 1M traces recorded + $0.50 per 1M traces scanned.
