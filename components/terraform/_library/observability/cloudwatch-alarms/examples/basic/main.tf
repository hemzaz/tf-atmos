module "cloudwatch_alarms" {
  source = "../../"

  name_prefix = "example-prod"

  create_cpu_alarms    = true
  create_memory_alarms = true
  create_disk_alarms   = true

  cpu_threshold    = 80
  memory_threshold = 85
  disk_threshold   = 90

  alarm_email_endpoints = [
    "ops-team@example.com"
  ]

  enable_anomaly_detection = true
  create_composite_alarms  = true

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
    Example     = "basic"
  }
}

output "sns_topic_arn" {
  value = module.cloudwatch_alarms.sns_topic_arn
}

output "alarm_count" {
  value = module.cloudwatch_alarms.alarm_count
}
