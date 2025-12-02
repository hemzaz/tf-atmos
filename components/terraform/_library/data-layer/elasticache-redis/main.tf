locals {
  name_prefix = "${var.name_prefix}-${var.environment}"
  cluster_id  = "${local.name_prefix}-redis"
  
  common_tags = merge(var.tags, {
    Name        = local.cluster_id
    Environment = var.environment
    ManagedBy   = "Terraform"
    Module      = "elasticache-redis"
  })
}

resource "aws_elasticache_subnet_group" "this" {
  name       = "${local.cluster_id}-subnet-group"
  subnet_ids = var.subnet_ids
  
  tags = local.common_tags
}

resource "aws_security_group" "redis" {
  name_prefix = "${local.cluster_id}-"
  description = "Security group for ${local.cluster_id}"
  vpc_id      = var.vpc_id
  
  tags = merge(local.common_tags, {
    Name = "${local.cluster_id}-sg"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "redis_ingress_cidr" {
  count = length(var.allowed_cidr_blocks) > 0 ? 1 : 0
  
  type              = "ingress"
  from_port         = var.port
  to_port           = var.port
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks
  security_group_id = aws_security_group.redis.id
}

resource "aws_security_group_rule" "redis_ingress_sg" {
  for_each = toset(var.allowed_security_group_ids)
  
  type                     = "ingress"
  from_port                = var.port
  to_port                  = var.port
  protocol                 = "tcp"
  source_security_group_id = each.value
  security_group_id        = aws_security_group.redis.id
}

resource "aws_security_group_rule" "redis_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.redis.id
}

resource "aws_elasticache_parameter_group" "this" {
  name_prefix = "${local.cluster_id}-"
  family      = var.parameter_group_family
  description = "Parameter group for ${local.cluster_id}"
  
  # Production-optimized parameters
  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }
  
  parameter {
    name  = "timeout"
    value = "300"
  }
  
  parameter {
    name  = "tcp-keepalive"
    value = "300"
  }
  
  tags = local.common_tags
  
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id       = local.cluster_id
  replication_group_description = "Redis cluster for ${local.cluster_id}"
  
  engine               = "redis"
  engine_version       = var.engine_version
  node_type            = var.node_type
  port                 = var.port
  parameter_group_name = aws_elasticache_parameter_group.this.name
  subnet_group_name    = aws_elasticache_subnet_group.this.name
  security_group_ids   = [aws_security_group.redis.id]
  
  # Cluster configuration
  num_cache_clusters         = var.enable_cluster_mode ? null : var.num_cache_nodes
  num_node_groups            = var.enable_cluster_mode ? var.num_node_groups : null
  replicas_per_node_group    = var.enable_cluster_mode ? var.replicas_per_node_group : null
  
  # High availability
  multi_az_enabled           = var.enable_multi_az
  automatic_failover_enabled = var.enable_automatic_failover
  
  # Security
  at_rest_encryption_enabled = var.enable_encryption_at_rest
  kms_key_id                 = var.kms_key_id
  transit_encryption_enabled = var.enable_encryption_in_transit
  auth_token                 = var.auth_token
  
  # Backups
  snapshot_retention_limit = var.snapshot_retention_limit
  snapshot_window          = var.snapshot_window
  
  # Maintenance
  maintenance_window              = var.maintenance_window
  auto_minor_version_upgrade      = var.enable_auto_minor_version_upgrade
  apply_immediately               = var.apply_immediately
  
  # Notifications
  notification_topic_arn = var.notification_topic_arn
  
  # Logging
  dynamic "log_delivery_configuration" {
    for_each = var.log_delivery_configuration
    content {
      destination      = log_delivery_configuration.value.destination
      destination_type = log_delivery_configuration.value.destination_type
      log_format       = log_delivery_configuration.value.log_format
      log_type         = log_delivery_configuration.value.log_type
    }
  }
  
  tags = local.common_tags
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${local.cluster_id}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = "300"
  statistic           = "Average"
  threshold           = "75"
  alarm_description   = "Redis CPU utilization high"
  
  dimensions = {
    CacheClusterId = aws_elasticache_replication_group.this.id
  }
  
  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "memory_high" {
  alarm_name          = "${local.cluster_id}-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseMemoryUsagePercentage"
  namespace           = "AWS/ElastiCache"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "Redis memory usage high"
  
  dimensions = {
    CacheClusterId = aws_elasticache_replication_group.this.id
  }
  
  tags = local.common_tags
}
