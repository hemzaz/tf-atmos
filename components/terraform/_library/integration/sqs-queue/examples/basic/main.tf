module "order_queue" {
  source = "../../"

  name_prefix = "example"
  queue_name  = "order-processing"

  fifo_queue                  = true
  content_based_deduplication = true
  visibility_timeout_seconds  = 300

  enable_dead_letter_queue = true
  max_receive_count        = 3

  enable_cloudwatch_alarms = true
  alarm_actions            = []

  tags = {
    Environment = "dev"
  }
}
