# Mock-provider tests for the per-instance naming fix (plateau audit D): every
# real stack runs two instances of this component (monitoring/main,
# monitoring/data), and before var.name existed both named every resource
# from tags.Environment alone, so the second instance's apply failed with
# ResourceAlreadyExists on the SNS topic, dashboard and alarms. Run from the
# component directory with `terraform init -backend=false && terraform test`.

mock_provider "aws" {}

variables {
  region = "eu-west-2"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
  enable_backend_monitoring = false
  create_dashboard          = true
  create_sns_topic          = true
  rds_instances             = ["db-1"]
  ecs_clusters              = ["ecs-1"]
  lambda_functions          = ["fn-1"]
  load_balancers            = ["app/lb-1/0123456789abcdef", "arn:aws:elasticloadbalancing:eu-west-2:123456789012:loadbalancer/app/lb-2/fedcba9876543210"]
  elasticache_clusters      = ["cache-1"]
  eks_cluster_name          = "eks-1"
  api_gateway_name          = "api-1"
  api_gateway_stages        = ["prod"]
  kms_key_id                = "arn:aws:kms:eu-west-2:123456789012:key/abcd1234-ab12-cd34-ef56-1234567890ab"
  cpu_alarms = {
    high_cpu = {
      namespace          = "AWS/EC2"
      evaluation_periods = 2
      period             = 300
      threshold          = 80
      dimensions         = {}
    }
  }
}

run "main_instance_names" {
  command = plan

  variables {
    name = "main"
  }

  assert {
    condition     = aws_sns_topic.alarms[0].name == "test-main-alarms"
    error_message = "The alarm SNS topic is named <Environment>-<name>-alarms."
  }

  assert {
    condition     = aws_cloudwatch_dashboard.main[0].dashboard_name == "test-main-overview"
    error_message = "The overview dashboard is named <Environment>-<name>-overview."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.cpu_high["high_cpu"].alarm_name == "test-main-high_cpu-high-cpu"
    error_message = "cpu_alarms are named <Environment>-<name>-<key>-high-cpu."
  }
}

run "data_instance_names_are_disjoint_from_main" {
  command = plan

  variables {
    name = "data"
  }

  assert {
    condition     = aws_sns_topic.alarms[0].name == "test-data-alarms"
    error_message = "The alarm SNS topic is named <Environment>-<name>-alarms."
  }

  assert {
    condition     = aws_sns_topic.alarms[0].name != "test-main-alarms"
    error_message = "monitoring/main and monitoring/data must not name the alarm topic the same, or the second apply fails with ResourceAlreadyExists."
  }

  assert {
    condition     = aws_cloudwatch_dashboard.main[0].dashboard_name == "test-data-overview"
    error_message = "The overview dashboard is named <Environment>-<name>-overview."
  }

  assert {
    condition     = aws_cloudwatch_dashboard.main[0].dashboard_name != "test-main-overview"
    error_message = "monitoring/main and monitoring/data must not name the dashboard the same."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.cpu_high["high_cpu"].alarm_name != "test-main-high_cpu-high-cpu"
    error_message = "monitoring/main and monitoring/data must not name alarms the same."
  }
}

run "overview_dashboard_has_real_dimensions" {
  command = plan

  variables {
    name = "main"
  }

  # Every widget's metrics, flattened to one list of [namespace, metric,
  # dim_name, dim_value, ...] rows so membership can be checked without
  # depending on widget order.
  assert {
    condition = contains(
      concat([for w in jsondecode(aws_cloudwatch_dashboard.main[0].dashboard_body).widgets : try(w.properties.metrics, [])]...),
      ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "db-1"],
    )
    error_message = "The RDS widget must plot CPUUtilization by DBInstanceIdentifier for each configured instance."
  }

  assert {
    condition = contains(
      concat([for w in jsondecode(aws_cloudwatch_dashboard.main[0].dashboard_body).widgets : try(w.properties.metrics, [])]...),
      ["AWS/ECS", "CPUUtilization", "ClusterName", "ecs-1"],
    )
    error_message = "The ECS widget must plot CPUUtilization by ClusterName."
  }

  assert {
    condition = contains(
      concat([for w in jsondecode(aws_cloudwatch_dashboard.main[0].dashboard_body).widgets : try(w.properties.metrics, [])]...),
      ["AWS/Lambda", "Invocations", "FunctionName", "fn-1"],
    )
    error_message = "The Lambda widget must plot Invocations by FunctionName."
  }

  assert {
    condition = contains(
      concat([for w in jsondecode(aws_cloudwatch_dashboard.main[0].dashboard_body).widgets : try(w.properties.metrics, [])]...),
      ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", "app/lb-1/0123456789abcdef"],
    )
    error_message = "The Load Balancer widget must plot RequestCount by the LoadBalancer dimension; a value already in the short app/<name>/<id> form passes through unchanged."
  }

  assert {
    condition = contains(
      concat([for w in jsondecode(aws_cloudwatch_dashboard.main[0].dashboard_body).widgets : try(w.properties.metrics, [])]...),
      ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", "app/lb-2/fedcba9876543210"],
    )
    error_message = "The LoadBalancer dimension strips a full ELB ARN down to its app/<name>/<id> suffix."
  }

  assert {
    condition = contains(
      concat([for w in jsondecode(aws_cloudwatch_dashboard.main[0].dashboard_body).widgets : try(w.properties.metrics, [])]...),
      ["AWS/ElastiCache", "CPUUtilization", "CacheClusterId", "cache-1"],
    )
    error_message = "The ElastiCache widget must plot CPUUtilization by CacheClusterId."
  }

  assert {
    condition = contains(
      concat([for w in jsondecode(aws_cloudwatch_dashboard.main[0].dashboard_body).widgets : try(w.properties.metrics, [])]...),
      ["ContainerInsights", "node_cpu_utilization", "ClusterName", "eks-1"],
    )
    error_message = "The EKS widget must plot node_cpu_utilization by ClusterName."
  }

  assert {
    condition = contains(
      concat([for w in jsondecode(aws_cloudwatch_dashboard.main[0].dashboard_body).widgets : try(w.properties.metrics, [])]...),
      ["AWS/ApiGateway", "Count", "ApiName", "api-1", "Stage", "prod"],
    )
    error_message = "The API Gateway widget must plot Count by ApiName + Stage."
  }

  assert {
    condition     = alltrue([for w in jsondecode(aws_cloudwatch_dashboard.main[0].dashboard_body).widgets : try(length(w.properties.metrics), 1) > 0])
    error_message = "No metric widget renders with an empty metrics list; a widget backed by an empty resource list is dropped entirely."
  }
}

run "overview_dashboard_drops_widgets_with_no_resources" {
  command = plan

  variables {
    name             = "data"
    rds_instances    = []
    ecs_clusters     = []
    lambda_functions = []
    load_balancers   = []
  }

  # Only elasticache/eks/api-gateway widgets plus the header text widget
  # should remain: 4 widgets, not 8.
  assert {
    condition     = length(jsondecode(aws_cloudwatch_dashboard.main[0].dashboard_body).widgets) == 4
    error_message = "Widgets whose backing list is empty (rds/ecs/lambda/load balancers here) are dropped, not rendered empty."
  }
}

run "sns_topic_is_kms_encrypted" {
  command = plan

  variables {
    name = "main"
  }

  assert {
    condition     = aws_sns_topic.alarms[0].kms_master_key_id == "arn:aws:kms:eu-west-2:123456789012:key/abcd1234-ab12-cd34-ef56-1234567890ab"
    error_message = "The alarm SNS topic must be encrypted with kms_key_id."
  }
}
