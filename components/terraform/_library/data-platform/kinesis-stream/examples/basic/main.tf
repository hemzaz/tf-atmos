module "kinesis_stream" {
  source = "../.."

  name_prefix     = "dev-events"
  stream_mode     = "ON_DEMAND"
  retention_hours = 24

  enable_monitoring = true

  tags = {
    Environment = "development"
    Example     = "basic"
  }
}

output "stream_arn" {
  value = module.kinesis_stream.stream_arn
}
