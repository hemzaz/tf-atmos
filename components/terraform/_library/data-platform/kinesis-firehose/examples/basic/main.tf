module "firehose" {
  source = "../.."

  name_prefix   = "dev-logs"
  destination   = "extended_s3"
  s3_bucket_arn = "arn:aws:s3:::example-bucket"
  s3_prefix     = "logs/"

  buffer_size_mb          = 5
  buffer_interval_seconds = 300

  enable_monitoring = true

  tags = {
    Environment = "development"
    Example     = "basic"
  }
}

output "delivery_stream_arn" {
  value = module.firehose.delivery_stream_arn
}
