# API Gateway REST API

Production-ready Amazon API Gateway REST API with Lambda integration, authentication, and monitoring.

## Features

- REST API with configurable endpoint types (EDGE, REGIONAL, PRIVATE)
- Deployment stages with versioning
- API keys and usage plans with quotas and throttling
- Request/response validation
- CloudWatch Logs integration with access logging
- AWS X-Ray tracing
- Response caching with encryption
- WAF integration for security
- Custom domain support with ACM certificates
- CloudWatch alarms (5XX errors, latency)
- Throttling and rate limiting

## Usage

```hcl
module "api" {
  source = "./_library/integration/api-gateway-rest"

  name_prefix = "prod"
  api_name    = "orders-api"
  stage_name  = "v1"

  endpoint_type   = "REGIONAL"
  api_description = "Orders REST API"

  # Logging and tracing
  enable_access_logging = true
  enable_xray_tracing   = true
  logging_level         = "INFO"

  # Throttling
  throttling_burst_limit = 5000
  throttling_rate_limit  = 10000

  # API keys and usage plans
  api_keys = [
    { name = "mobile-app", description = "Mobile app key" },
    { name = "web-app", description = "Web app key" }
  ]

  usage_plans = [
    {
      name                 = "basic"
      description          = "Basic tier"
      quota_limit          = 10000
      quota_period         = "DAY"
      throttle_burst_limit = 200
      throttle_rate_limit  = 100
      api_key_names        = ["mobile-app"]
    }
  ]

  # Custom domain
  custom_domain_name = "api.example.com"
  certificate_arn    = aws_acm_certificate.api.arn

  # WAF
  waf_acl_arn = module.waf.web_acl_arn

  # Request validation
  request_validators = [
    {
      name                        = "validate-body"
      validate_request_body       = true
      validate_request_parameters = true
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

## Inputs

See `variables.tf` for complete list of variables.

## Outputs

See `outputs.tf` for complete list of outputs.
