module "log_aggregation" {
  source = "../../"

  name_prefix        = "example-prod"
  log_retention_days = 30

  service_log_groups = {
    lambda = {
      retention_days = 7
      filter_pattern = "[ERROR]"
    }
    ecs = {
      retention_days = 30
    }
    api-gateway = {
      retention_days = 14
    }
  }

  enable_kinesis_streaming = true
  kinesis_shard_count      = 1
  kinesis_on_demand        = false

  enable_s3_export            = true
  s3_transition_to_ia_days    = 90
  s3_transition_to_glacier_days = 180
  s3_expiration_days          = 365

  enable_athena_queries = true

  create_error_metric_filter = true

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
    Example     = "basic"
  }
}

output "central_log_group_name" {
  value = module.log_aggregation.central_log_group_name
}

output "s3_bucket_name" {
  value = module.log_aggregation.s3_bucket_name
}

output "athena_database_name" {
  value = module.log_aggregation.athena_database_name
}
