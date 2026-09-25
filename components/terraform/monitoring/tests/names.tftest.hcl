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
  enable_backend_monitoring       = false
  create_infrastructure_dashboard = true
  create_sns_topic                = true
  rds_instances                   = ["db-1"]
  ecs_clusters                    = ["ecs-1"]
  lambda_functions                = ["fn-1"]
  load_balancers                  = ["app/lb-1/0123456789abcdef", "arn:aws:elasticloadbalancing:eu-west-2:123456789012:loadbalancer/app/lb-2/fedcba9876543210"]
  elasticache_clusters            = ["cache-1"]
  eks_cluster_name                = "eks-1"
  api_gateway_name                = "api-1"
  api_gateway_stages              = ["prod"]
  kms_key_id                      = "arn:aws:kms:eu-west-2:123456789012:key/abcd1234-ab12-cd34-ef56-1234567890ab"
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
    condition     = aws_cloudwatch_dashboard.infrastructure[0].dashboard_name == "test-main-infrastructure-overview"
    error_message = "The infrastructure dashboard is named <Environment>-<name>-infrastructure-overview."
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
    condition     = aws_cloudwatch_dashboard.infrastructure[0].dashboard_name == "test-data-infrastructure-overview"
    error_message = "The infrastructure dashboard is named <Environment>-<name>-infrastructure-overview."
  }

  assert {
    condition     = aws_cloudwatch_dashboard.infrastructure[0].dashboard_name != "test-main-infrastructure-overview"
    error_message = "monitoring/main and monitoring/data must not name the dashboard the same."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.cpu_high["high_cpu"].alarm_name != "test-main-high_cpu-high-cpu"
    error_message = "monitoring/main and monitoring/data must not name alarms the same."
  }
}

run "infrastructure_dashboard_has_real_dimensions" {
  command = plan

  variables {
    name = "main"
  }

  # Every widget's metrics, flattened to one list of [namespace, metric,
  # dim_name, dim_value, ...] rows so membership can be checked without
  # depending on widget order.
  assert {
    condition = contains(
      concat([for w in jsondecode(aws_cloudwatch_dashboard.infrastructure[0].dashboard_body).widgets : try(w.properties.metrics, [])]...),
      ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "db-1"],
    )
    error_message = "The RDS widget must plot CPUUtilization by DBInstanceIdentifier for each configured instance."
  }

  assert {
    condition = contains(
      concat([for w in jsondecode(aws_cloudwatch_dashboard.infrastructure[0].dashboard_body).widgets : try(w.properties.metrics, [])]...),
      ["AWS/ECS", "CPUUtilization", "ClusterName", "ecs-1"],
    )
    error_message = "The ECS widget must plot CPUUtilization by ClusterName."
  }

  assert {
    condition = contains(
      concat([for w in jsondecode(aws_cloudwatch_dashboard.infrastructure[0].dashboard_body).widgets : try(w.properties.metrics, [])]...),
      ["AWS/Lambda", "Invocations", "FunctionName", "fn-1"],
    )
    error_message = "The Lambda widget must plot Invocations by FunctionName."
  }

  assert {
    condition = contains(
      concat([for w in jsondecode(aws_cloudwatch_dashboard.infrastructure[0].dashboard_body).widgets : try(w.properties.metrics, [])]...),
      ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", "app/lb-1/0123456789abcdef"],
    )
    error_message = "The Load Balancer widget must plot RequestCount by the LoadBalancer dimension; a value already in the short app/<name>/<id> form passes through unchanged."
  }

  assert {
    condition = contains(
      concat([for w in jsondecode(aws_cloudwatch_dashboard.infrastructure[0].dashboard_body).widgets : try(w.properties.metrics, [])]...),
      ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", "app/lb-2/fedcba9876543210"],
    )
    error_message = "The LoadBalancer dimension strips a full ELB ARN down to its app/<name>/<id> suffix."
  }

  assert {
    condition = contains(
      concat([for w in jsondecode(aws_cloudwatch_dashboard.infrastructure[0].dashboard_body).widgets : try(w.properties.metrics, [])]...),
      ["AWS/ElastiCache", "CPUUtilization", "CacheClusterId", "cache-1"],
    )
    error_message = "The ElastiCache widget must plot CPUUtilization by CacheClusterId."
  }

  assert {
    condition = contains(
      concat([for w in jsondecode(aws_cloudwatch_dashboard.infrastructure[0].dashboard_body).widgets : try(w.properties.metrics, [])]...),
      ["ContainerInsights", "node_cpu_utilization", "ClusterName", "eks-1"],
    )
    error_message = "The EKS widget must plot node_cpu_utilization by ClusterName."
  }

  assert {
    condition = contains(
      concat([for w in jsondecode(aws_cloudwatch_dashboard.infrastructure[0].dashboard_body).widgets : try(w.properties.metrics, [])]...),
      ["AWS/ApiGateway", "Count", "ApiName", "api-1", "Stage", "prod"],
    )
    error_message = "The API Gateway widget must plot Count by ApiName + Stage."
  }

  assert {
    condition     = alltrue([for w in jsondecode(aws_cloudwatch_dashboard.infrastructure[0].dashboard_body).widgets : try(length(w.properties.metrics), 1) > 0])
    error_message = "No metric widget renders with an empty metrics list; a widget backed by an empty resource list is dropped entirely."
  }
}

run "infrastructure_dashboard_drops_widgets_with_no_resources" {
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
    condition     = length(jsondecode(aws_cloudwatch_dashboard.infrastructure[0].dashboard_body).widgets) == 4
    error_message = "Widgets whose backing list is empty (rds/ecs/lambda/load balancers here) are dropped, not rendered empty."
  }
}

run "performance_and_application_dashboards_have_real_dimensions" {
  command = plan

  variables {
    name                         = "main"
    create_performance_dashboard = true
    create_application_dashboard = true
    api_gateway_stages           = ["prod"]
  }

  assert {
    condition = contains(
      concat([for w in jsondecode(aws_cloudwatch_dashboard.performance[0].dashboard_body).widgets : try(w.properties.metrics, [])]...),
      ["AWS/RDS", "ReadLatency", "DBInstanceIdentifier", "db-1"],
    )
    error_message = "The performance dashboard's RDS latency widget must plot ReadLatency by DBInstanceIdentifier, not one metric averaged over the account."
  }

  assert {
    condition = contains(
      concat([for w in jsondecode(aws_cloudwatch_dashboard.performance[0].dashboard_body).widgets : try(w.properties.metrics, [])]...),
      ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", "app/lb-1/0123456789abcdef"],
    )
    error_message = "The performance dashboard's ALB widget must plot TargetResponseTime by LoadBalancer."
  }

  assert {
    condition = contains(
      concat([for w in jsondecode(aws_cloudwatch_dashboard.application[0].dashboard_body).widgets : try(w.properties.metrics, [])]...),
      ["AWS/Lambda", "Errors", "FunctionName", "fn-1"],
    )
    error_message = "The application dashboard's Lambda widget must plot Errors by FunctionName."
  }

  assert {
    condition = contains(
      concat([for w in jsondecode(aws_cloudwatch_dashboard.application[0].dashboard_body).widgets : try(w.properties.metrics, [])]...),
      ["AWS/ApiGateway", "5XXError", "ApiName", "api-1", "Stage", "prod"],
    )
    error_message = "The application dashboard's API Gateway widget must plot 5XXError by ApiName + Stage."
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

run "backend_dashboard_has_real_dimensions_and_no_empty_widgets" {
  command = plan

  variables {
    name                      = "main"
    enable_backend_monitoring = true
  }

  assert {
    condition = contains(
      concat([for w in jsondecode(aws_cloudwatch_dashboard.backend_services[0].dashboard_body).widgets : try(w.properties.metrics, [])]...),
      ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "db-1"],
    )
    error_message = "The backend dashboard's RDS widget must plot CPUUtilization by DBInstanceIdentifier."
  }

  assert {
    condition = contains(
      concat([for w in jsondecode(aws_cloudwatch_dashboard.backend_services[0].dashboard_body).widgets : try(w.properties.metrics, [])]...),
      ["AWS/Lambda", "Duration", "FunctionName", "fn-1"],
    )
    error_message = "The backend dashboard's Lambda widget must plot Duration by FunctionName."
  }

  assert {
    condition = contains(
      concat([for w in jsondecode(aws_cloudwatch_dashboard.backend_services[0].dashboard_body).widgets : try(w.properties.metrics, [])]...),
      ["AWS/ApiGateway", "Count", "ApiName", "api-1", "Stage", "prod"],
    )
    error_message = "The backend dashboard's API Gateway widget must plot Count by ApiName + Stage."
  }

  assert {
    condition = contains(
      concat([for w in jsondecode(aws_cloudwatch_dashboard.backend_services[0].dashboard_body).widgets : try(w.properties.metrics, [])]...),
      ["ContainerInsights", "pod_cpu_utilization", "ClusterName", "eks-1", "Namespace", "backend-services"],
    )
    error_message = "The backend dashboard's EKS widget must plot pod_cpu_utilization by ClusterName + Namespace."
  }

  assert {
    condition = contains(
      concat([for w in jsondecode(aws_cloudwatch_dashboard.backend_services[0].dashboard_body).widgets : try(w.properties.metrics, [])]...),
      ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", "app/lb-1/0123456789abcdef"],
    )
    error_message = "The backend dashboard's ALB widget must plot TargetResponseTime by LoadBalancer, stripped down to app/<name>/<id>."
  }

  assert {
    condition = contains(
      concat([for w in jsondecode(aws_cloudwatch_dashboard.backend_services[0].dashboard_body).widgets : try(w.properties.metrics, [])]...),
      ["AWS/ElastiCache", "CPUUtilization", "CacheClusterId", "cache-1"],
    )
    error_message = "The backend dashboard's ElastiCache widget must plot CPUUtilization by CacheClusterId."
  }

  assert {
    condition     = alltrue([for w in jsondecode(aws_cloudwatch_dashboard.backend_services[0].dashboard_body).widgets : try(length(w.properties.metrics), 1) > 0])
    error_message = "No backend dashboard widget renders with an empty metrics list; a widget backed by an empty resource list is dropped entirely."
  }
}

run "backend_alb_alarm_names_and_dimensions_use_load_balancer_ids" {
  command = plan

  variables {
    name                      = "main"
    enable_backend_monitoring = true
  }

  # load_balancers includes both the short "app/<name>/<id>" form and a full
  # ELB ARN; both alarms must dimension on the short form and sanitize "/" out
  # of the alarm name.
  assert {
    condition     = aws_cloudwatch_metric_alarm.alb_response_time["app/lb-2/fedcba9876543210"].dimensions["LoadBalancer"] == "app/lb-2/fedcba9876543210"
    error_message = "alb_response_time must dimension on the app/<name>/<id> suffix, even when load_balancers is given a full ARN."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.alb_response_time["app/lb-2/fedcba9876543210"].alarm_name == "test-main-alb-app-lb-2-fedcba9876543210-response-time"
    error_message = "alb_response_time's alarm_name must sanitize the \"/\" characters CloudWatch alarm names reject."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.alb_unhealthy_hosts["app/lb-1/0123456789abcdef"].alarm_name == "test-main-alb-app-lb-1-0123456789abcdef-unhealthy-hosts"
    error_message = "alb_unhealthy_hosts's alarm_name must sanitize the \"/\" characters CloudWatch alarm names reject."
  }
}

run "metrics_tf_names_use_name_prefix_and_are_disjoint" {
  command = plan

  variables {
    name = "main"
    metric_alarms = {
      queue-depth = {
        namespace           = "AWS/SQS"
        metric_name         = "ApproximateNumberOfMessagesVisible"
        dimensions          = { QueueName = "q1" }
        comparison_operator = "GreaterThanThreshold"
        threshold           = 100
        statistic           = "Average"
      }
    }
    metric_dashboards = {
      queue = {
        widgets = [
          { title = "Queue depth", metrics = [{ namespace = "AWS/SQS", metric = "ApproximateNumberOfMessagesVisible", dimensions = { QueueName = "q1" } }] },
        ]
      }
    }
    log_insights_queries = {
      slow-requests = {
        log_group_names = ["/aws/lambda/test"]
        query           = "fields @timestamp | limit 10"
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.metric["queue-depth"].alarm_name == "test-main-queue-depth"
    error_message = "metric_alarms are named <Environment>-<name>-<key>, not <Environment>-<key> alone (metrics.tf must use local.name_prefix, or monitoring/main and monitoring/data would collide on the same metric_alarms key)."
  }

  assert {
    condition     = aws_cloudwatch_dashboard.metric["queue"].dashboard_name == "test-main-queue"
    error_message = "metric_dashboards are named <Environment>-<name>-<key>."
  }

  assert {
    condition     = aws_cloudwatch_query_definition.this["slow-requests"].name == "test-main/slow-requests"
    error_message = "log_insights_queries are named <Environment>-<name>/<key>."
  }
}

run "metrics_tf_names_disjoint_between_main_and_data" {
  command = plan

  variables {
    name = "data"
    metric_alarms = {
      queue-depth = {
        namespace           = "AWS/SQS"
        metric_name         = "ApproximateNumberOfMessagesVisible"
        dimensions          = { QueueName = "q1" }
        comparison_operator = "GreaterThanThreshold"
        threshold           = 100
        statistic           = "Average"
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.metric["queue-depth"].alarm_name != "test-main-queue-depth"
    error_message = "monitoring/main and monitoring/data must not name a metric_alarms entry the same, or the second apply fails with ResourceAlreadyExists."
  }
}

run "every_dashboard_name_is_unique_with_all_flags_on" {
  command = plan

  variables {
    name                            = "main"
    create_infrastructure_dashboard = true
    create_security_dashboard       = true
    create_cost_dashboard           = true
    create_performance_dashboard    = true
    create_application_dashboard    = true
    create_certificate_dashboard    = true
    enable_backend_monitoring       = true
    enable_certificate_monitoring   = true
    certificate_arns                = ["arn:aws:acm:eu-west-2:123456789012:certificate/abc"]
    certificate_names               = ["example"]
  }

  # dashboards.tf's aws_cloudwatch_dashboard.backend and .certificates were
  # both removed as duplicates of main.tf's aws_cloudwatch_dashboard.backend_services
  # and .certificate_monitoring (each pair used to name the exact same
  # dashboard); only the latter address of each pair exists now, so
  # referencing it here also guards against a duplicate resource being
  # reintroduced (a re-added "backend"/"certificates" resource would not be
  # part of this list and the collision would show up as a duplicate name).
  assert {
    condition = length(distinct(concat(
      [aws_cloudwatch_dashboard.infrastructure[0].dashboard_name],
      [aws_cloudwatch_dashboard.security[0].dashboard_name],
      [aws_cloudwatch_dashboard.cost[0].dashboard_name],
      [aws_cloudwatch_dashboard.performance[0].dashboard_name],
      [aws_cloudwatch_dashboard.application[0].dashboard_name],
      [aws_cloudwatch_dashboard.certificate_monitoring[0].dashboard_name],
      [aws_cloudwatch_dashboard.backend_services[0].dashboard_name],
    ))) == 7
    error_message = "Every dashboard this instance creates must have a unique name; a duplicate means two Terraform resources manage the same CloudWatch dashboard."
  }

  assert {
    condition = alltrue([
      for n in [
        aws_cloudwatch_dashboard.infrastructure[0].dashboard_name,
        aws_cloudwatch_dashboard.security[0].dashboard_name,
        aws_cloudwatch_dashboard.cost[0].dashboard_name,
        aws_cloudwatch_dashboard.performance[0].dashboard_name,
        aws_cloudwatch_dashboard.application[0].dashboard_name,
        aws_cloudwatch_dashboard.backend_services[0].dashboard_name,
      ] : startswith(n, "test-main-")
    ])
    error_message = "Every dashboard name must start with <Environment>-<name>."
  }
}

run "null_eks_and_api_gateway_names_fall_back_to_empty_string" {
  command = plan

  # Round 4 review finding: eks_cluster_name and api_gateway_name are fed from
  # !terraform.state outputs that can genuinely be null (eks's eks_cluster_id
  # is one(aws_eks_cluster.default[*].name), null when eks is disabled;
  # apigateway's api_name is null for an HTTP API). Both variables are
  # `nullable = false`, so an explicit null argument must fall back to the ""
  # default instead of staying null and breaking the `!= ""` gates below.
  variables {
    name                      = "main"
    enable_backend_monitoring = true
    eks_cluster_name          = null
    api_gateway_name          = null
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.eks_cluster_failed_requests) == 0
    error_message = "A null eks_cluster_name must fall back to \"\" and drop the EKS failed-requests alarm, not plan with a null ClusterName dimension."
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.api_gateway_latency) == 0
    error_message = "A null api_gateway_name must fall back to \"\" and drop the API Gateway latency alarm, not plan with a null ApiName dimension."
  }

  assert {
    condition = alltrue([
      for w in jsondecode(aws_cloudwatch_dashboard.backend_services[0].dashboard_body).widgets :
      try(length(w.properties.metrics), 1) > 0
    ])
    error_message = "The backend dashboard must still plan (dropping the EKS and API Gateway widgets, not planning them with a null dimension value)."
  }
}
