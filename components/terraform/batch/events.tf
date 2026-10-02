# EventBridge target role: a Batch job queue target needs a role_arn that
# EventBridge assumes to call batch:SubmitJob (the eventbridge component
# creates none). Same pattern as this repo's stepfunctions events_role_enabled:
# trusted by events.amazonaws.com from this account, allowed only to submit
# this instance's job definitions (any revision, <arn_prefix>:*) to this
# instance's job queues, as the AWS EventBridge Batch target docs require.

locals {
  events_role_enabled = local.enabled && var.events_role_enabled
  events_role_name    = "${local.prefix}-events"
}

resource "aws_iam_role" "events" {
  count = local.events_role_enabled ? 1 : 0

  name = local.events_role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "events.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })

  tags = { Name = local.events_role_name }

  lifecycle {
    precondition {
      condition     = length(local.events_role_name) <= 64
      error_message = "The events role name (<Environment>-<name>-events, \"${local.events_role_name}\") must be 64 characters or fewer."
    }
  }
}

resource "aws_iam_role_policy" "events" {
  count = local.events_role_enabled ? 1 : 0

  name = "${local.events_role_name}-submit"
  role = aws_iam_role.events[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "SubmitThisInstancesJobsOnly"
      Effect = "Allow"
      Action = "batch:SubmitJob"
      Resource = concat(
        [for q in values(aws_batch_job_queue.this) : q.arn],
        [for d in values(aws_batch_job_definition.this) : "${d.arn_prefix}:*"],
      )
    }]
  })
}
