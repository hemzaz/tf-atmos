# Offline tests for event_notification_details, Cloud Posse's aws-s3-bucket
# input ported verbatim (cloudposse/terraform-aws-s3-bucket:
# aws_s3_bucket_notification.bucket_notification). Same harness as s3.tftest.hcl:
# the real AWS provider with dummy credentials, plan-only.
# Run: terraform init -backend=false && terraform test

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

override_data {
  target = data.aws_caller_identity.current
  values = {
    account_id = "123456789012"
  }
}

variables {
  region      = "us-east-1"
  name        = "assets"
  kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "no_notification_resource_by_default" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket_notification.this) == 0
    error_message = "No notification resource unless event_notification_details.enabled is set."
  }
}

run "eventbridge_and_queue_notifications_render" {
  command = plan

  variables {
    event_notification_details = {
      enabled     = true
      eventbridge = true
      queue_list = [
        {
          queue_arn     = "arn:aws:sqs:us-east-1:123456789012:test-trigger"
          events        = ["s3:ObjectCreated:*"]
          filter_prefix = "incoming/"
          filter_suffix = ".csv"
        },
      ]
    }
  }

  assert {
    condition     = length(aws_s3_bucket_notification.this) == 1
    error_message = "One notification resource is created when enabled."
  }

  assert {
    condition     = aws_s3_bucket_notification.this[0].eventbridge == true
    error_message = "EventBridge notifications are on when eventbridge = true."
  }

  assert {
    condition     = length(aws_s3_bucket_notification.this[0].queue) == 1
    error_message = "One queue destination renders from queue_list."
  }

  assert {
    condition     = one(aws_s3_bucket_notification.this[0].queue).queue_arn == "arn:aws:sqs:us-east-1:123456789012:test-trigger"
    error_message = "The queue ARN passes through unchanged."
  }

  assert {
    condition     = tolist(one(aws_s3_bucket_notification.this[0].queue).events) == tolist(["s3:ObjectCreated:*"])
    error_message = "The events list passes through unchanged."
  }

  assert {
    condition     = one(aws_s3_bucket_notification.this[0].queue).filter_prefix == "incoming/" && one(aws_s3_bucket_notification.this[0].queue).filter_suffix == ".csv"
    error_message = "Filter prefix and suffix carry through."
  }

  assert {
    condition     = length(aws_s3_bucket_notification.this[0].lambda_function) == 0 && length(aws_s3_bucket_notification.this[0].topic) == 0
    error_message = "No lambda or topic destinations unless lambda_list/topic_list are set."
  }
}

run "lambda_and_topic_notifications_render" {
  command = plan

  variables {
    event_notification_details = {
      enabled = true
      lambda_list = [
        {
          lambda_function_arn = "arn:aws:lambda:us-east-1:123456789012:function:test-fn"
          events              = ["s3:ObjectRemoved:*"]
        },
      ]
      topic_list = [
        {
          topic_arn     = "arn:aws:sns:us-east-1:123456789012:test-topic"
          filter_prefix = "reports/"
        },
      ]
    }
  }

  assert {
    condition     = one(aws_s3_bucket_notification.this[0].lambda_function).lambda_function_arn == "arn:aws:lambda:us-east-1:123456789012:function:test-fn"
    error_message = "The lambda destination ARN renders."
  }

  assert {
    condition     = tolist(one(aws_s3_bucket_notification.this[0].lambda_function).events) == tolist(["s3:ObjectRemoved:*"])
    error_message = "The lambda destination's events render."
  }

  assert {
    condition     = one(aws_s3_bucket_notification.this[0].topic).topic_arn == "arn:aws:sns:us-east-1:123456789012:test-topic" && one(aws_s3_bucket_notification.this[0].topic).filter_prefix == "reports/"
    error_message = "The topic destination and its filter_prefix render, with the default events (s3:ObjectCreated:*)."
  }

  assert {
    condition     = tolist(one(aws_s3_bucket_notification.this[0].topic).events) == tolist(["s3:ObjectCreated:*"])
    error_message = "events defaults to [\"s3:ObjectCreated:*\"] when omitted (Cloud Posse's default)."
  }

  assert {
    condition     = aws_s3_bucket_notification.this[0].eventbridge == false
    error_message = "eventbridge defaults to false."
  }
}

run "disabled_bucket_creates_no_notification" {
  command = plan

  variables {
    enabled = false
    event_notification_details = {
      enabled = true
      queue_list = [
        { queue_arn = "arn:aws:sqs:us-east-1:123456789012:test-trigger" },
      ]
    }
  }

  assert {
    condition     = length(aws_s3_bucket_notification.this) == 0
    error_message = "enabled = false on the bucket must still create no notification resource, even if event_notification_details.enabled is true."
  }
}
