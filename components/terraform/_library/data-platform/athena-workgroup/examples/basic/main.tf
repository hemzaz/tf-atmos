module "athena_workgroup" {
  source = "../.."

  workgroup_name  = "dev-analytics"
  output_location = "s3://example-bucket/athena-results/"

  output_bucket_arn = "arn:aws:s3:::example-bucket"

  encryption_option         = "SSE_S3"
  enforce_workgroup_config  = true
  enable_cloudwatch_metrics = true

  enable_monitoring = true

  tags = {
    Environment = "development"
    Example     = "basic"
  }
}

output "workgroup_name" {
  value = module.athena_workgroup.workgroup_name
}
