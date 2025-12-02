module "xray_tracing" {
  source = "../../"

  name_prefix = "example-prod"
  environment = "production"

  create_default_sampling_rule = true
  default_reservoir_size       = 1
  default_fixed_rate           = 0.05

  enable_high_value_sampling = true
  high_value_url_pattern     = "/api/*/critical/*"

  create_error_group         = true
  create_slow_requests_group = true
  slow_request_threshold     = 3

  enable_insights               = true
  enable_insights_notifications = true

  enable_cost_optimization = true

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
    Example     = "basic"
  }
}

output "trace_console_url" {
  value = module.xray_tracing.trace_console_url
}

output "sampling_rate" {
  value = module.xray_tracing.sampling_rate
}
