resource "aws_ecs_cluster" "main" {
  name = "${var.tags["Environment"]}-cluster"

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-ecs-cluster"
    }
  )
}

resource "aws_ecs_capacity_provider" "main" {
  count = var.fargate_only ? 0 : 1
  name  = "${var.tags["Environment"]}-capacity-provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn = var.autoscaling_group_arn

    managed_scaling {
      maximum_scaling_step_size = var.max_scaling_step_size
      minimum_scaling_step_size = var.min_scaling_step_size
      status                    = "ENABLED"
      target_capacity           = var.target_capacity
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = concat(
    var.fargate_only ? [] : [aws_ecs_capacity_provider.main[0].name],
    ["FARGATE", "FARGATE_SPOT"]
  )

  default_capacity_provider_strategy {
    capacity_provider = var.fargate_only ? "FARGATE" : aws_ecs_capacity_provider.main[0].name
    weight            = 1
  }

  # Explicit dependency to avoid race condition
  depends_on = [
    aws_ecs_cluster.main,
    aws_ecs_capacity_provider.main
  ]

  lifecycle {
    create_before_destroy = true
  }
}




