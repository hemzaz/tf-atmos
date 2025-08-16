# Internal Developer Platform Infrastructure Component
# This component provisions the core infrastructure for the IDP platform

# EKS cluster for IDP platform
module "eks_cluster" {
  source = "../eks"

  # Inherit context and variables
  context = local.context

  cluster_name                         = "${local.name_prefix}-idp-cluster"
  cluster_version                      = var.cluster_version
  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access       = var.cluster_endpoint_public_access
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # Enhanced security settings for production IDP
  cluster_enabled_log_types     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cluster_log_retention_in_days = 30

  # Node groups configuration
  node_groups = {
    platform_services = {
      instance_types = ["m5.xlarge", "m5a.xlarge"]
      capacity_type  = "ON_DEMAND"
      min_size       = 3
      max_size       = 10
      desired_size   = 3

      k8s_labels = {
        "workload-type"                    = "platform-services"
        "node.kubernetes.io/instance-type" = "platform"
      }

      taints = [
        {
          key    = "platform-services"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      ]
    }

    user_workloads = {
      instance_types = ["m5.large", "m5a.large", "c5.large"]
      capacity_type  = "SPOT"
      min_size       = 2
      max_size       = 20
      desired_size   = 5

      k8s_labels = {
        "workload-type"                    = "user-workloads"
        "node.kubernetes.io/instance-type" = "user"
      }
    }
  }

  # Add-ons for IDP functionality
  addons = {
    vpc-cni = {
      addon_version               = "v1.15.1-eksbuild.1"
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"

      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }

    kube-proxy = {
      addon_version               = "v1.28.2-eksbuild.2"
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
    }

    coredns = {
      addon_version               = "v1.10.1-eksbuild.4"
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"

      configuration_values = jsonencode({
        computeType = "Fargate"
        resources = {
          limits = {
            cpu    = "0.25"
            memory = "256Mi"
          }
          requests = {
            cpu    = "0.25"
            memory = "256Mi"
          }
        }
      })
    }

    aws-ebs-csi-driver = {
      addon_version               = "v1.24.0-eksbuild.1"
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
    }
  }

  # Security groups
  additional_security_group_rules = {
    ingress_nodes_443 = {
      description = "HTTPS from load balancer"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      type        = "ingress"
      cidr_blocks = [data.aws_vpc.selected.cidr_block]
    }

    ingress_nodes_80 = {
      description = "HTTP from load balancer"
      protocol    = "tcp"
      from_port   = 80
      to_port     = 80
      type        = "ingress"
      cidr_blocks = [data.aws_vpc.selected.cidr_block]
    }

    ingress_prometheus = {
      description = "Prometheus metrics"
      protocol    = "tcp"
      from_port   = 9090
      to_port     = 9100
      type        = "ingress"
      cidr_blocks = [data.aws_vpc.selected.cidr_block]
    }
  }

  tags = local.tags
}

# RDS instance for Backstage and Platform API
module "idp_database" {
  source = "../rds"

  context = local.context

  identifier = "${local.name_prefix}-idp-db"

  # Database configuration
  engine         = "postgres"
  engine_version = var.database_engine_version
  instance_class = var.database_instance_class

  allocated_storage     = var.database_allocated_storage
  max_allocated_storage = var.database_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  # Multi-AZ for high availability
  multi_az            = var.environment == "prod" ? true : false
  publicly_accessible = false

  # Database settings
  db_name  = "backstage"
  username = "idp_admin"

  # Backup configuration
  backup_window           = "03:00-04:00"
  backup_retention_period = var.environment == "prod" ? 30 : 7

  maintenance_window = "sun:04:00-sun:05:00"

  # Performance Insights
  performance_insights_enabled          = true
  performance_insights_retention_period = var.environment == "prod" ? 731 : 7

  # Monitoring
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_enhanced_monitoring.arn

  # Parameter and option groups
  parameter_group_name = aws_db_parameter_group.postgres_params.name
  option_group_name    = null

  # Security
  vpc_security_group_ids = [aws_security_group.database.id]
  db_subnet_group_name   = aws_db_subnet_group.database.name

  # Deletion protection for production
  deletion_protection       = var.environment == "prod" ? true : false
  skip_final_snapshot       = var.environment == "prod" ? false : true
  final_snapshot_identifier = var.environment == "prod" ? "${local.name_prefix}-idp-db-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}" : null

  # Automated backups already configured above

  tags = merge(local.tags, {
    Component = "database"
    Service   = "idp-platform"
  })
}

# ElastiCache Redis cluster for caching and session storage
resource "aws_elasticache_subnet_group" "redis" {
  name       = "${local.name_prefix}-redis-subnet-group"
  subnet_ids = data.aws_subnets.private.ids

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-redis-subnet-group"
  })
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "${local.name_prefix}-redis"
  description          = "Redis cluster for IDP platform"

  # Redis configuration
  node_type            = var.redis_node_type
  port                 = 6379
  parameter_group_name = aws_elasticache_parameter_group.redis.name

  # Clustering
  num_cache_clusters = var.redis_num_cache_clusters

  # Security
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.redis_auth_token.result

  # Network
  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = [aws_security_group.redis.id]

  # Backup
  snapshot_retention_limit = var.environment == "prod" ? 14 : 3
  snapshot_window          = "03:00-05:00"

  # Maintenance
  maintenance_window = "sun:05:00-sun:07:00"

  # Automatic failover
  automatic_failover_enabled = var.redis_num_cache_clusters > 1 ? true : false
  multi_az_enabled           = var.redis_num_cache_clusters > 1 ? true : false

  # Logging
  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis_slow_log.name
    destination_type = "cloudwatch-logs"
    log_format       = "text"
    log_type         = "slow-log"
  }

  tags = merge(local.tags, {
    Name      = "${local.name_prefix}-redis"
    Component = "cache"
    Service   = "idp-platform"
  })
}

# S3 buckets for various IDP needs
module "idp_storage" {
  source = "../s3"

  for_each = toset([
    "artifacts",
    "backups",
    "logs",
    "techdocs",
    "uploads"
  ])

  context = local.context

  bucket_name = "${local.name_prefix}-idp-${each.key}"

  # Versioning for important buckets
  versioning_enabled = contains(["artifacts", "backups", "techdocs"], each.key)

  # Lifecycle policies
  lifecycle_rules = each.key == "logs" ? [
    {
      id      = "delete_old_logs"
      enabled = true

      expiration = [{
        days = 90
      }]

      noncurrent_version_expiration = [{
        noncurrent_days = 30
      }]
    }
  ] : []

  # Public access for techdocs
  block_public_acls       = each.key != "techdocs"
  block_public_policy     = each.key != "techdocs"
  ignore_public_acls      = each.key != "techdocs"
  restrict_public_buckets = each.key != "techdocs"

  # CORS for uploads bucket
  cors_rules = each.key == "uploads" ? [
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET", "HEAD", "PUT", "POST", "DELETE"]
      allowed_origins = ["https://${var.domain_name}", "https://api.${var.domain_name}"]
      expose_headers  = ["ETag"]
      max_age_seconds = 3000
    }
  ] : []

  # Server-side encryption
  server_side_encryption_configuration = [
    {
      rule = {
        apply_server_side_encryption_by_default = {
          kms_master_key_id = data.aws_kms_key.s3.arn
          sse_algorithm     = "aws:kms"
        }
        bucket_key_enabled = true
      }
    }
  ]

  tags = merge(local.tags, {
    Component = "storage"
    Service   = "idp-platform"
    Purpose   = each.key
  })
}

# Load balancer for IDP services
resource "aws_lb" "idp_platform" {
  name               = "${local.name_prefix}-idp-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.public.ids

  enable_deletion_protection = var.environment == "prod" ? true : false

  # Access logs
  access_logs {
    bucket  = module.idp_storage["logs"].bucket_name
    prefix  = "alb-access-logs"
    enabled = true
  }

  tags = merge(local.tags, {
    Name      = "${local.name_prefix}-idp-alb"
    Component = "load-balancer"
    Service   = "idp-platform"
  })
}

# ACM certificate for HTTPS
module "acm_certificate" {
  source = "../acm"

  context = local.context

  domain_name = var.domain_name
  subject_alternative_names = [
    "api.${var.domain_name}",
    "grafana.${var.domain_name}",
    "prometheus.${var.domain_name}",
    "jaeger.${var.domain_name}"
  ]

  validation_method = "DNS"

  tags = merge(local.tags, {
    Component = "certificate"
    Service   = "idp-platform"
  })
}

# Route53 hosted zone and records
resource "aws_route53_zone" "main" {
  name          = var.domain_name
  force_destroy = false

  tags = merge(local.tags, {
    Name      = var.domain_name
    Component = "dns"
    Service   = "idp-platform"
  })
}

# Route53 health checks for monitoring
resource "aws_route53_health_check" "idp_platform" {
  fqdn              = var.domain_name
  port              = 443
  type              = "HTTPS"
  resource_path     = "/api/catalog/health"
  failure_threshold = 3
  request_interval  = 30

  tags = merge(local.tags, {
    Name      = "${var.domain_name} Health Check"
    Component = "health-check"
    Service   = "idp-platform"
  })
}

# CloudWatch alarms for health monitoring
resource "aws_cloudwatch_metric_alarm" "idp_platform_health" {
  alarm_name          = "${local.name_prefix}-idp-health"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "1"
  alarm_description   = "This metric monitors IDP platform health"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    HealthCheckId = aws_route53_health_check.idp_platform.id
  }

  tags = local.tags
}

# SNS topic for alerts
resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-idp-alerts"

  tags = merge(local.tags, {
    Component = "notifications"
    Service   = "idp-platform"
  })
}

# KMS key for encryption
data "aws_kms_key" "s3" {
  key_id = "alias/aws/s3"
}

# Secrets Manager secrets for sensitive configuration
resource "aws_secretsmanager_secret" "idp_config" {
  name                    = "${local.name_prefix}/idp-platform/config"
  description             = "Configuration secrets for IDP platform"
  recovery_window_in_days = var.environment == "prod" ? 30 : 0

  tags = merge(local.tags, {
    Component = "secrets"
    Service   = "idp-platform"
  })
}

resource "aws_secretsmanager_secret_version" "idp_config" {
  secret_id = aws_secretsmanager_secret.idp_config.id
  secret_string = jsonencode({
    database_url = "postgresql://${module.idp_database.username}:${module.idp_database.password}@${module.idp_database.endpoint}:${module.idp_database.port}/${module.idp_database.db_name}"
    redis_url    = "redis://:${random_password.redis_auth_token.result}@${aws_elasticache_replication_group.redis.configuration_endpoint_address}:6379"
    jwt_secret   = random_password.jwt_secret.result
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# Random passwords
resource "random_password" "redis_auth_token" {
  length  = 32
  special = true
}

resource "random_password" "jwt_secret" {
  length  = 64
  special = true
}