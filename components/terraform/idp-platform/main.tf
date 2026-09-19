# Internal Developer Platform Infrastructure Component
# This component provisions the core infrastructure for the IDP platform

locals {
  # Matches the "<Environment>-vpc" naming used by the vpc component
  name_prefix = var.environment
  tags        = merge({ Environment = var.environment }, var.tags, var.resource_tags)

  storage_buckets = toset(["artifacts", "backups", "logs", "techdocs", "uploads"])
}

# UNSUPPORTED: this component nests the eks, rds and acm root components (each with its
# own provider block), a legacy-module pattern. No stack deploys it; planning fails
# unless acknowledge_unsupported is set, until the shared logic moves to modules/terraform.
resource "terraform_data" "unsupported" {
  lifecycle {
    precondition {
      condition     = var.acknowledge_unsupported
      error_message = "idp-platform is unsupported: it nests root components with their own provider blocks. See README.md; set acknowledge_unsupported = true only for experiments."
    }
  }
}

# EKS cluster for IDP platform (via the eks component; EKS addons and public-access CIDRs
# are not supported by that component and are managed by eks-addons instead)
module "eks_cluster" {
  source = "../eks"

  region     = var.region
  subnet_ids = data.aws_subnets.private.ids

  clusters = {
    idp = {
      kubernetes_version        = var.cluster_version
      endpoint_private_access   = true
      endpoint_public_access    = var.cluster_endpoint_public_access
      public_access_cidrs       = var.cluster_endpoint_public_access_cidrs
      enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

      node_groups = {
        platform_services = {
          instance_types = ["m5.xlarge", "m5a.xlarge"]
          capacity_type  = "ON_DEMAND"
          min_size       = 3
          max_size       = 10
          desired_size   = 3
          labels = {
            "workload-type" = "platform-services"
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
          labels = {
            "workload-type" = "user-workloads"
          }
          taints = []
        }
      }
    }
  }

  tags = local.tags
}

# RDS instance for Backstage and Platform API (via the rds component, which owns its
# security group, subnet group, parameter group, monitoring role and password secret)
module "idp_database" {
  source = "../rds"

  region      = var.region
  environment = var.environment
  vpc_id      = data.aws_vpc.selected.id
  subnet_ids  = data.aws_subnets.private.ids

  allowed_security_groups = [module.eks_cluster.cluster_security_group_ids["idp"]]

  identifier     = "idp-db"
  engine         = "postgres"
  engine_version = var.database_engine_version
  family         = "postgres${split(".", var.database_engine_version)[0]}"
  instance_class = var.database_instance_class
  port           = 5432

  allocated_storage     = var.database_allocated_storage
  max_allocated_storage = var.database_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  multi_az            = var.environment == "prod"
  publicly_accessible = false

  db_name  = "backstage"
  username = "idp_admin"

  backup_window           = var.backup_window
  backup_retention_period = var.environment == "prod" ? 30 : 7
  maintenance_window      = var.maintenance_window.database

  performance_insights_enabled          = true
  performance_insights_retention_period = var.performance_insights_retention_period
  monitoring_interval                   = 60

  deletion_protection = coalesce(var.enable_deletion_protection, var.environment == "prod")
  prevent_destroy     = coalesce(var.enable_deletion_protection, var.environment == "prod")
  skip_final_snapshot = var.environment != "prod"

  tags = merge(local.tags, {
    Component = "database"
    Service   = "idp-platform"
  })
}

# Security groups (previously referenced but never declared)
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-idp-alb-sg"
  description = "IDP platform application load balancer"
  vpc_id      = data.aws_vpc.selected.id

  tags = merge(local.tags, { Name = "${local.name_prefix}-idp-alb-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  for_each = toset(var.allowed_cidr_blocks)

  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from allowed networks"
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_vpc" {
  security_group_id = aws_security_group.alb.id
  description       = "Traffic to targets inside the VPC"
  cidr_ipv4         = data.aws_vpc.selected.cidr_block
  ip_protocol       = "-1"
}

resource "aws_security_group" "redis" {
  name        = "${local.name_prefix}-idp-redis-sg"
  description = "IDP platform Redis"
  vpc_id      = data.aws_vpc.selected.id

  tags = merge(local.tags, { Name = "${local.name_prefix}-idp-redis-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_eks" {
  security_group_id            = aws_security_group.redis.id
  description                  = "Redis from the IDP EKS cluster"
  referenced_security_group_id = module.eks_cluster.cluster_security_group_ids["idp"]
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}

# ElastiCache Redis cluster for caching and session storage
resource "aws_elasticache_parameter_group" "redis" {
  name   = "${local.name_prefix}-idp-redis"
  family = "redis7"

  tags = local.tags
}

resource "aws_cloudwatch_log_group" "redis_slow_log" {
  name              = "/aws/elasticache/${local.name_prefix}-idp-redis/slow-log"
  retention_in_days = var.log_retention_days

  tags = local.tags
}

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
  engine               = "redis"
  engine_version       = "7.1"
  node_type            = var.redis_node_type
  port                 = 6379
  parameter_group_name = aws_elasticache_parameter_group.redis.name

  # Clustering
  num_cache_clusters = var.redis_num_cache_clusters

  # Security
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token_wo              = ephemeral.aws_secretsmanager_secret_version.redis_auth.secret_string
  auth_token_wo_version      = var.secrets_version
  auth_token_update_strategy = "ROTATE"

  # Network
  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = [aws_security_group.redis.id]

  # Backup
  snapshot_retention_limit = var.environment == "prod" ? 14 : 3
  snapshot_window          = "03:00-05:00"

  # Maintenance
  maintenance_window = var.maintenance_window.redis

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
resource "aws_s3_bucket" "idp_storage" {
  for_each = local.storage_buckets

  bucket = "${local.name_prefix}-idp-${each.key}"

  tags = merge(local.tags, {
    Component = "storage"
    Service   = "idp-platform"
    Purpose   = each.key
  })
}

resource "aws_s3_bucket_ownership_controls" "idp_storage" {
  for_each = local.storage_buckets

  bucket = aws_s3_bucket.idp_storage[each.key].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# techdocs stays publicly readable, as before
resource "aws_s3_bucket_public_access_block" "idp_storage" {
  for_each = local.storage_buckets

  bucket = aws_s3_bucket.idp_storage[each.key].id

  block_public_acls       = each.key != "techdocs"
  block_public_policy     = each.key != "techdocs"
  ignore_public_acls      = each.key != "techdocs"
  restrict_public_buckets = each.key != "techdocs"
}

resource "aws_s3_bucket_versioning" "idp_storage" {
  for_each = toset(["artifacts", "backups", "techdocs"])

  bucket = aws_s3_bucket.idp_storage[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

# ALB access logs only support SSE-S3, so the logs bucket does not use the KMS key
resource "aws_s3_bucket_server_side_encryption_configuration" "idp_storage" {
  for_each = local.storage_buckets

  bucket = aws_s3_bucket.idp_storage[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = each.key == "logs" ? "AES256" : "aws:kms"
      kms_master_key_id = each.key == "logs" ? null : data.aws_kms_key.s3.arn
    }
    bucket_key_enabled = each.key != "logs"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "idp_logs" {
  bucket = aws_s3_bucket.idp_storage["logs"].id

  rule {
    id     = "delete_old_logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 90
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "idp_uploads" {
  bucket = aws_s3_bucket.idp_storage["uploads"].id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    allowed_origins = ["https://${var.domain_name}", "https://api.${var.domain_name}"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_policy" "idp_logs" {
  bucket = aws_s3_bucket.idp_storage["logs"].id
  policy = data.aws_iam_policy_document.alb_logs.json

  depends_on = [aws_s3_bucket_public_access_block.idp_storage]
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
    bucket  = aws_s3_bucket.idp_storage["logs"].id
    prefix  = "alb-access-logs"
    enabled = true
  }

  tags = merge(local.tags, {
    Name      = "${local.name_prefix}-idp-alb"
    Component = "load-balancer"
    Service   = "idp-platform"
  })
}

# ACM certificate for HTTPS (via the acm component, which also creates the DNS validation records)
module "acm_certificate" {
  source = "../acm"

  region  = var.region
  zone_id = aws_route53_zone.main.zone_id

  dns_domains = {
    idp = {
      domain_name = var.domain_name
      subject_alternative_names = [
        "api.${var.domain_name}",
        "grafana.${var.domain_name}",
        "prometheus.${var.domain_name}",
        "jaeger.${var.domain_name}"
      ]
      validation_method = "DNS"
    }
  }

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

# Config consumers resolve credentials from their own secrets instead of copies
resource "aws_secretsmanager_secret_version" "idp_config" {
  secret_id = aws_secretsmanager_secret.idp_config.id
  secret_string_wo = jsonencode({
    database_url          = "postgresql://${module.idp_database.instance_endpoint}/${module.idp_database.instance_name}"
    database_secret_arn   = module.idp_database.password_secret_arn
    redis_url             = "rediss://${aws_elasticache_replication_group.redis.primary_endpoint_address}:6379"
    redis_auth_secret_arn = aws_secretsmanager_secret.redis_auth.arn
    jwt_secret            = ephemeral.aws_secretsmanager_random_password.jwt_secret.random_password
  })
  secret_string_wo_version = var.secrets_version
}

# Redis AUTH token: generated once into Secrets Manager (the single source of truth) and
# read back ephemerally for ElastiCache. Bump secrets_version to rotate it.
resource "aws_secretsmanager_secret" "redis_auth" {
  name                    = "${local.name_prefix}/idp-platform/redis-auth-token"
  description             = "ElastiCache AUTH token for the IDP platform Redis"
  recovery_window_in_days = var.environment == "prod" ? 30 : 0

  tags = merge(local.tags, {
    Component = "secrets"
    Service   = "idp-platform"
  })
}

resource "aws_secretsmanager_secret_version" "redis_auth" {
  secret_id                = aws_secretsmanager_secret.redis_auth.id
  secret_string_wo         = ephemeral.aws_secretsmanager_random_password.redis_auth_token.random_password
  secret_string_wo_version = var.secrets_version
}

ephemeral "aws_secretsmanager_random_password" "redis_auth_token" {
  password_length     = 32
  exclude_punctuation = true # ElastiCache rejects "@", "/" and '"' in AUTH tokens
}

ephemeral "aws_secretsmanager_secret_version" "redis_auth" {
  secret_id = aws_secretsmanager_secret.redis_auth.id

  depends_on = [aws_secretsmanager_secret_version.redis_auth]
}

ephemeral "aws_secretsmanager_random_password" "jwt_secret" {
  password_length = 64
}
