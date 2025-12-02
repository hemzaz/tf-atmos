module "event_bus" {
  source = "../../"

  name_prefix = "example"
  bus_name    = "app-events"

  event_rules = [
    {
      name          = "scheduled-task"
      description   = "Run task every 5 minutes"
      schedule_expression = "rate(5 minutes)"
      lambda_targets = [
        {
          function_arn = "arn:aws:lambda:us-east-1:123456789012:function:example"
        }
      ]
    }
  ]

  enable_archive = true
  enable_cloudwatch_alarms = true

  tags = {
    Environment = "dev"
  }
}
