# Mock-provider tests for metrics.tf: no AWS credentials, no network. Run
# from the component directory with
# `terraform init -backend=false && terraform test`.

mock_provider "aws" {}

variables {
  region = "eu-west-2"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
  # Keep the plan to what these tests look at.
  enable_backend_monitoring = false
}

run "alarm_on_any_metric_and_dimension" {
  command = plan

  variables {
    metric_alarms = {
      api-5xx = {
        namespace           = "AWS/ApiGateway"
        metric_name         = "5xx"
        dimensions          = { ApiId = "a1b2c3d4e5" }
        comparison_operator = "GreaterThanThreshold"
        threshold           = 10
        statistic           = "Sum"
      }
      api-latency-p99 = {
        namespace           = "AWS/ApiGateway"
        metric_name         = "Latency"
        dimensions          = { ApiId = "a1b2c3d4e5" }
        comparison_operator = "GreaterThanThreshold"
        threshold           = 3000
        extended_statistic  = "p99"
        evaluation_periods  = 3
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.metric["api-5xx"].alarm_name == "test-monitoring-api-5xx"
    error_message = "Alarms are named <Environment>-<name>-<key> (name defaults to \"monitoring\")."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.metric["api-5xx"].dimensions == tomap({ ApiId = "a1b2c3d4e5" })
    error_message = "Dimensions are passed through as given."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.metric["api-latency-p99"].extended_statistic == "p99" && aws_cloudwatch_metric_alarm.metric["api-latency-p99"].statistic == null
    error_message = "A percentile alarm sets extended_statistic and no statistic."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.metric["api-5xx"].period == 300 && aws_cloudwatch_metric_alarm.metric["api-5xx"].evaluation_periods == 2
    error_message = "period and evaluation_periods default to 300 and 2."
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.metric["api-5xx"].alarm_actions) == 1
    error_message = "Alarms notify the SNS topic (create_sns_topic defaults to true)."
  }
}

run "dashboard_body_is_cloudwatch_json" {
  command = plan

  variables {
    metric_dashboards = {
      eventbridge = {
        widgets = [
          {
            title = "EventBridge"
            stat  = "Sum"
            metrics = [
              { namespace = "AWS/Events", metric = "Invocations", dimensions = { EventBusName = "test-bus" } },
              { namespace = "AWS/Events", metric = "FailedInvocations", dimensions = { EventBusName = "test-bus" } },
            ]
          },
          {
            title   = "Second"
            metrics = [{ namespace = "AWS/DynamoDB", metric = "ThrottledRequests", dimensions = { TableName = "t", Operation = "PutItem" } }]
          },
          {
            title   = "Third"
            metrics = [{ namespace = "AWS/Events", metric = "Invocations" }]
          },
        ]
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_dashboard.metric["eventbridge"].dashboard_name == "test-monitoring-eventbridge"
    error_message = "Dashboards are named <Environment>-<name>-<key> (name defaults to \"monitoring\")."
  }

  assert {
    condition = jsondecode(aws_cloudwatch_dashboard.metric["eventbridge"].dashboard_body).widgets[0].properties.metrics == [
      ["AWS/Events", "Invocations", "EventBusName", "test-bus"],
      ["AWS/Events", "FailedInvocations", "EventBusName", "test-bus"],
    ]
    error_message = "Each metric is [namespace, metric, dimension name, dimension value, ...]."
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_dashboard.metric["eventbridge"].dashboard_body).widgets[1].properties.metrics[0] == ["AWS/DynamoDB", "ThrottledRequests", "Operation", "PutItem", "TableName", "t"]
    error_message = "Dimensions are emitted sorted by name, so the body is stable."
  }

  assert {
    condition = [for w in jsondecode(aws_cloudwatch_dashboard.metric["eventbridge"].dashboard_body).widgets : [w.x, w.y]] == [
      [0, 0], [12, 0], [0, 6],
    ]
    error_message = "Widgets are laid out two per row."
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_dashboard.metric["eventbridge"].dashboard_body).widgets[0].properties.region == "eu-west-2"
    error_message = "Every metric widget carries the region."
  }
}

run "saved_logs_insights_query" {
  command = plan

  variables {
    log_insights_queries = {
      error-analysis = {
        log_group_names = ["/aws/eks/test-microservices/cluster"]
        query           = "fields @timestamp, @message | filter @message like /error/"
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_query_definition.this["error-analysis"].name == "test-monitoring/error-analysis"
    error_message = "Queries are named <Environment>-<name>/<key> (name defaults to \"monitoring\")."
  }

  assert {
    condition     = aws_cloudwatch_query_definition.this["error-analysis"].log_group_names == tolist(["/aws/eks/test-microservices/cluster"])
    error_message = "Queries are scoped to log_group_names."
  }
}

run "xray_rule_name_fits_the_32_character_limit" {
  command = plan

  variables {
    enable_tracing = true
    tags = {
      Environment = "a-rather-long-environment-name"
      Tenant      = "fnx"
      ManagedBy   = "Terraform"
    }
  }

  assert {
    condition     = length(aws_xray_sampling_rule.backend_services[0].rule_name) <= 32
    error_message = "X-Ray rejects rule names over 32 characters."
  }
}

run "dashboards_render_valid_json_with_several_resources" {
  command = plan

  # The templated dashboards left a trailing comma after the last row of every
  # non-empty list, so any stack listing a cache node, RDS instance, Lambda or
  # load balancer failed at plan with "dashboard_body contains an invalid JSON".
  variables {
    enable_backend_monitoring       = true
    create_dashboard                = true
    create_infrastructure_dashboard = true
    create_application_dashboard    = true
    create_performance_dashboard    = true
    create_security_dashboard       = true
    create_cost_dashboard           = true
    eks_cluster_name                = "test-cluster"
    elasticache_clusters            = ["cache-0001-001", "cache-0002-001"]
    rds_instances                   = ["db-1", "db-2"]
    lambda_functions                = ["fn-1", "fn-2"]
    load_balancers                  = ["app/lb-1/0123456789abcdef"]
    ecs_clusters                    = ["ecs-1", "ecs-2"]
  }

  assert {
    condition     = length(jsondecode(aws_cloudwatch_dashboard.backend_services[0].dashboard_body).widgets[5].properties.metrics) == 8
    error_message = "The backend dashboard's ElastiCache widget has four rows per node, as valid JSON."
  }

  assert {
    condition     = length(jsondecode(aws_cloudwatch_dashboard.infrastructure[0].dashboard_body).widgets) > 0
    error_message = "The infrastructure overview dashboard body is valid JSON."
  }

  assert {
    condition = alltrue([for d in concat(
      aws_cloudwatch_dashboard.infrastructure, aws_cloudwatch_dashboard.application,
      aws_cloudwatch_dashboard.performance, aws_cloudwatch_dashboard.security, aws_cloudwatch_dashboard.cost,
    ) : can(jsondecode(d.dashboard_body))])
    error_message = "Every templated dashboard body is valid JSON with several resources listed."
  }
}

run "rejects_both_statistics" {
  command = plan

  variables {
    metric_alarms = {
      bad = {
        namespace           = "AWS/Events"
        metric_name         = "FailedInvocations"
        comparison_operator = "GreaterThanThreshold"
        threshold           = 1
        statistic           = "Sum"
        extended_statistic  = "p99"
      }
    }
  }

  expect_failures = [var.metric_alarms]
}

run "rejects_a_percentile_as_statistic" {
  command = plan

  variables {
    metric_alarms = {
      bad = {
        namespace           = "AWS/ApiGateway"
        metric_name         = "Latency"
        comparison_operator = "GreaterThanThreshold"
        threshold           = 1
        statistic           = "p99"
      }
    }
  }

  expect_failures = [var.metric_alarms]
}

run "rejects_a_widget_without_metrics" {
  command = plan

  variables {
    metric_dashboards = {
      empty = { widgets = [{ title = "nothing", metrics = [] }] }
    }
  }

  expect_failures = [var.metric_dashboards]
}
