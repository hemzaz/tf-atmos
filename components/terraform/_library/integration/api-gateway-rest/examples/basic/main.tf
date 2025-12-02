module "api" {
  source = "../../"

  name_prefix = "example"
  api_name    = "simple-api"
  stage_name  = "dev"

  endpoint_type = "REGIONAL"

  enable_access_logging = true
  enable_xray_tracing   = true
  logging_level         = "INFO"

  api_keys = [
    { name = "test-key" }
  ]

  usage_plans = [
    {
      name              = "basic"
      quota_limit       = 1000
      quota_period      = "DAY"
      api_key_names     = ["test-key"]
    }
  ]

  tags = {
    Environment = "dev"
  }
}
