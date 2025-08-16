# IDP Auto-scaling Configuration Module
# Implements horizontal and vertical scaling policies for the IDP platform

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

locals {
  name_prefix = "${var.tenant}-${var.environment}-idp"

  common_tags = merge(
    var.tags,
    {
      Tenant      = var.tenant
      Environment = var.environment
      Component   = "idp-autoscaling"
      ManagedBy   = "Terraform"
    }
  )
}

# EKS Cluster Auto-scaler
resource "aws_iam_role" "cluster_autoscaler" {
  name = "${local.name_prefix}-cluster-autoscaler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = var.eks_oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${replace(var.eks_oidc_provider_arn, "/^(.*provider/)/", "")}:sub" = "system:serviceaccount:kube-system:cluster-autoscaler"
            "${replace(var.eks_oidc_provider_arn, "/^(.*provider/)/", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "cluster_autoscaler" {
  name = "${local.name_prefix}-cluster-autoscaler"
  role = aws_iam_role.cluster_autoscaler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
          "ec2:DescribeImages",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:GetInstanceTypesFromInstanceRequirements",
          "eks:DescribeNodegroup"
        ]
        Resource = "*"
      }
    ]
  })
}

# Kubernetes Cluster Autoscaler Deployment
resource "kubernetes_service_account" "cluster_autoscaler" {
  metadata {
    name      = "cluster-autoscaler"
    namespace = "kube-system"

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.cluster_autoscaler.arn
    }

    labels = {
      "app.kubernetes.io/name"       = "cluster-autoscaler"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "kubernetes_deployment" "cluster_autoscaler" {
  metadata {
    name      = "cluster-autoscaler"
    namespace = "kube-system"

    labels = {
      "app.kubernetes.io/name" = "cluster-autoscaler"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        "app.kubernetes.io/name" = "cluster-autoscaler"
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "cluster-autoscaler"
        }

        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "8085"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.cluster_autoscaler.metadata[0].name

        container {
          name  = "cluster-autoscaler"
          image = "registry.k8s.io/autoscaling/cluster-autoscaler:v${var.cluster_autoscaler_version}"

          resources {
            limits = {
              cpu    = "100m"
              memory = "300Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "300Mi"
            }
          }

          args = [
            "--v=4",
            "--stderrthreshold=info",
            "--cloud-provider=aws",
            "--skip-nodes-with-local-storage=false",
            "--expander=least-waste",
            "--node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/${var.eks_cluster_name}",
            "--balance-similar-node-groups",
            "--skip-nodes-with-system-pods=false",
            "--scale-down-delay-after-add=${var.scale_down_delay}",
            "--scale-down-unneeded-time=${var.scale_down_unneeded_time}",
            "--max-node-provision-time=15m"
          ]

          env {
            name  = "AWS_REGION"
            value = data.aws_region.current.name
          }
        }

        affinity {
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 100
              pod_affinity_term {
                label_selector {
                  match_labels = {
                    "app.kubernetes.io/name" = "cluster-autoscaler"
                  }
                }
                topology_key = "kubernetes.io/hostname"
              }
            }
          }
        }
      }
    }
  }
}

# Data source for current region
data "aws_region" "current" {}

# Horizontal Pod Autoscaler for key services
resource "kubernetes_horizontal_pod_autoscaler_v2" "api_gateway" {
  metadata {
    name      = "api-gateway-hpa"
    namespace = var.application_namespace
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = "api-gateway"
    }

    min_replicas = var.api_gateway_min_replicas
    max_replicas = var.api_gateway_max_replicas

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }

    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = 80
        }
      }
    }

    metric {
      type = "Pods"
      pods {
        metric {
          name = "http_requests_per_second"
        }
        target {
          type          = "AverageValue"
          average_value = "1000"
        }
      }
    }

    behavior {
      scale_up {
        stabilization_window_seconds = 60
        select_policy                = "Max"

        policy {
          type           = "Percent"
          value          = 100
          period_seconds = 60
        }

        policy {
          type           = "Pods"
          value          = 4
          period_seconds = 60
        }
      }

      scale_down {
        stabilization_window_seconds = 300
        select_policy                = "Min"

        policy {
          type           = "Percent"
          value          = 50
          period_seconds = 60
        }

        policy {
          type           = "Pods"
          value          = 1
          period_seconds = 60
        }
      }
    }
  }
}

# Vertical Pod Autoscaler for resource optimization
resource "kubernetes_manifest" "vpa_api_gateway" {
  manifest = {
    apiVersion = "autoscaling.k8s.io/v1"
    kind       = "VerticalPodAutoscaler"

    metadata = {
      name      = "api-gateway-vpa"
      namespace = var.application_namespace
    }

    spec = {
      targetRef = {
        apiVersion = "apps/v1"
        kind       = "Deployment"
        name       = "api-gateway"
      }

      updatePolicy = {
        updateMode = var.vpa_update_mode
      }

      resourcePolicy = {
        containerPolicies = [
          {
            containerName = "*"
            minAllowed = {
              cpu    = "100m"
              memory = "128Mi"
            }
            maxAllowed = {
              cpu    = "2"
              memory = "8Gi"
            }
            controlledResources = ["cpu", "memory"]
          }
        ]
      }
    }
  }
}

# Application Auto-scaling for RDS Aurora
resource "aws_appautoscaling_target" "aurora_replicas" {
  service_namespace  = "rds"
  scalable_dimension = "rds:cluster:ReadReplicaCount"
  resource_id        = "cluster:${var.aurora_cluster_id}"
  min_capacity       = var.aurora_min_replicas
  max_capacity       = var.aurora_max_replicas
}

resource "aws_appautoscaling_policy" "aurora_cpu" {
  name               = "${local.name_prefix}-aurora-cpu-scaling"
  service_namespace  = aws_appautoscaling_target.aurora_replicas.service_namespace
  scalable_dimension = aws_appautoscaling_target.aurora_replicas.scalable_dimension
  resource_id        = aws_appautoscaling_target.aurora_replicas.resource_id
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "RDSReaderAverageCPUUtilization"
    }

    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

resource "aws_appautoscaling_policy" "aurora_connections" {
  name               = "${local.name_prefix}-aurora-connection-scaling"
  service_namespace  = aws_appautoscaling_target.aurora_replicas.service_namespace
  scalable_dimension = aws_appautoscaling_target.aurora_replicas.scalable_dimension
  resource_id        = aws_appautoscaling_target.aurora_replicas.resource_id
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "RDSReaderAverageDatabaseConnections"
    }

    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# ElastiCache Redis Auto-scaling
resource "aws_appautoscaling_target" "redis_shards" {
  count              = var.enable_redis_autoscaling ? 1 : 0
  service_namespace  = "elasticache"
  scalable_dimension = "elasticache:replication-group:NodeGroups"
  resource_id        = "replication-group/${var.redis_replication_group_id}"
  min_capacity       = var.redis_min_shards
  max_capacity       = var.redis_max_shards
}

resource "aws_appautoscaling_policy" "redis_cpu" {
  count              = var.enable_redis_autoscaling ? 1 : 0
  name               = "${local.name_prefix}-redis-cpu-scaling"
  service_namespace  = aws_appautoscaling_target.redis_shards[0].service_namespace
  scalable_dimension = aws_appautoscaling_target.redis_shards[0].scalable_dimension
  resource_id        = aws_appautoscaling_target.redis_shards[0].resource_id
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ElastiCachePrimaryEngineCPUUtilization"
    }

    target_value       = 60.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# Lambda Function Concurrency Auto-scaling
resource "aws_lambda_provisioned_concurrency_config" "api_functions" {
  for_each = var.lambda_functions

  function_name                     = each.key
  provisioned_concurrent_executions = each.value.provisioned_concurrency
  qualifier                         = each.value.qualifier
}

resource "aws_appautoscaling_target" "lambda_concurrency" {
  for_each = var.lambda_functions

  service_namespace  = "lambda"
  scalable_dimension = "lambda:function:ProvisionedConcurrency"
  resource_id        = "function:${each.key}:${each.value.qualifier}"
  min_capacity       = each.value.min_concurrency
  max_capacity       = each.value.max_concurrency
}

resource "aws_appautoscaling_policy" "lambda_provisioned_concurrency" {
  for_each = var.lambda_functions

  name               = "${local.name_prefix}-${each.key}-concurrency-scaling"
  service_namespace  = aws_appautoscaling_target.lambda_concurrency[each.key].service_namespace
  scalable_dimension = aws_appautoscaling_target.lambda_concurrency[each.key].scalable_dimension
  resource_id        = aws_appautoscaling_target.lambda_concurrency[each.key].resource_id
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "LambdaProvisionedConcurrencyUtilization"
    }

    target_value = 0.7
  }
}

# CloudWatch Dashboard for Auto-scaling Metrics
resource "aws_cloudwatch_dashboard" "autoscaling" {
  dashboard_name = "${local.name_prefix}-autoscaling"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/EKS", "cluster_node_count", { stat = "Average", label = "Node Count" }],
            ["AWS/ApplicationELB", "ActiveConnectionCount", { stat = "Sum", label = "Active Connections" }],
            ["AWS/RDS", "DatabaseConnections", { stat = "Average", label = "DB Connections" }]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Auto-scaling Metrics"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Lambda", "ConcurrentExecutions", { stat = "Maximum", label = "Lambda Concurrent" }],
            ["AWS/ElastiCache", "CPUUtilization", { stat = "Average", label = "Redis CPU" }],
            ["AWS/EKS", "cluster_failed_node_count", { stat = "Sum", label = "Failed Nodes" }]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Resource Utilization"
        }
      }
    ]
  })
}

# Outputs
output "cluster_autoscaler_role_arn" {
  description = "IAM role ARN for cluster autoscaler"
  value       = aws_iam_role.cluster_autoscaler.arn
}

output "autoscaling_dashboard_url" {
  description = "CloudWatch dashboard URL for auto-scaling metrics"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.autoscaling.dashboard_name}"
}