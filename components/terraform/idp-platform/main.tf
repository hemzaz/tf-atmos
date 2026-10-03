# Internal Developer Platform Infrastructure Component
# This component provisions the core infrastructure for the IDP platform

locals {
  # Matches the "<Environment>-vpc" naming used by the vpc component
  name_prefix = var.environment
  tags        = merge({ Environment = var.environment }, var.tags, var.resource_tags)

  storage_buckets = toset(["artifacts", "backups", "logs", "techdocs", "uploads"])

  # ../rds forces TLS (rds.force_ssl = 1); verify-full also checks the server
  # certificate against the RDS CA bundle the app images ship.
  database_tls_query = "sslmode=verify-full&sslrootcert=${var.database_ca_bundle_path}"
  database_url       = "postgresql://${module.idp_database.instance_endpoint}/${module.idp_database.instance_name}?${local.database_tls_query}"
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

# EKS cluster for IDP platform (via the eks component, one cluster named
# "<Environment>-idp"). The eks component installs the vpc-cni addon with its IRSA
# role (its vpc_cni_addon default); every other addon belongs to eks-addons.
module "eks_cluster" {
  source = "../eks"

  region     = var.region
  subnet_ids = data.aws_subnets.private.ids

  name                            = "idp"
  cluster_kubernetes_version      = var.cluster_version
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = var.cluster_endpoint_public_access
  # null with the endpoint off. With it on, eks rejects an empty list (AWS
  # would read it as 0.0.0.0/0), so the [] default must be replaced.
  public_access_cidrs       = var.cluster_endpoint_public_access ? var.cluster_endpoint_public_access_cidrs : null
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  node_groups = {
    platform_services = {
      instance_types     = ["m5.xlarge", "m5a.xlarge"]
      capacity_type      = "ON_DEMAND"
      min_group_size     = 3
      max_group_size     = 10
      desired_group_size = 3
      kubernetes_labels = {
        "workload-type" = "platform-services"
      }
      kubernetes_taints = [
        {
          key    = "platform-services"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      ]
    }

    user_workloads = {
      instance_types     = ["m5.large", "m5a.large", "c5.large"]
      capacity_type      = "SPOT"
      min_group_size     = 2
      max_group_size     = 20
      desired_group_size = 5
      kubernetes_labels = {
        "workload-type" = "user-workloads"
      }
      kubernetes_taints = []
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

  allowed_security_groups = [module.eks_cluster.eks_cluster_managed_security_group_id]

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
  referenced_security_group_id = module.eks_cluster.eks_cluster_managed_security_group_id
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

# Encrypted with the stack's CMK (kms/main): its key policy lets
# logs.<region>.amazonaws.com use it for this account's log groups
# (kms allow_cloudwatch_logs, on in kms/defaults).
resource "aws_cloudwatch_log_group" "redis_slow_log" {
  #checkov:skip=CKV_AWS_338:Retention is an input (log_retention_days) and a per-stack cost decision, as on the repo's other log groups
  name              = "/aws/elasticache/${local.name_prefix}-idp-redis/slow-log"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

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
  #checkov:skip=CKV_AWS_191:TODO(owner): at-rest encryption uses the AWS managed key; a CMK (kms_key_id) forces replacement. Goes away with idp-platform's deletion (owner decision D5)
  #checkov:skip=CKV_AWS_31:False positive, the check reads only auth_token; transit encryption is on and the token is set write-only through auth_token_wo (as elasticache/main.tf)
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
  auth_token_wo              = local.redis_auth_token
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

  lifecycle {
    precondition {
      condition     = can(regex("^[A-Za-z0-9!&#$^<>-]{16,128}$", local.redis_auth_token))
      error_message = "The generated Redis AUTH token breaks ElastiCache's rules (16-128 characters, punctuation only from !&#$^<>-); check local.redis_auth_token_generator."
    }
  }
}

# S3 buckets for various IDP needs
resource "aws_s3_bucket" "idp_storage" {
  #checkov:skip=CKV2_AWS_6:TODO(owner): techdocs is deliberately public (aws_s3_bucket_public_access_block.idp_storage); the other four block all public access, which checkov cannot evaluate through for_each. Goes away with idp-platform (D5)
  #checkov:skip=CKV_AWS_18:TODO(owner): no server access logs; they need an SSE-S3 target bucket (new bucket, cost). Goes away with idp-platform (D5)
  #checkov:skip=CKV_AWS_144:Cross-region replication is out of scope for this unsupported component, which owner decision D5 deletes
  #checkov:skip=CKV_AWS_145:The logs bucket uses SSE-S3 because ALB access log delivery does not support SSE-KMS; the other four use KMS
  #checkov:skip=CKV_AWS_21:artifacts, backups and techdocs are versioned (aws_s3_bucket_versioning.idp_storage); logs expire after 90 days and uploads are not versioned
  #checkov:skip=CKV2_AWS_61:Only logs expires (aws_s3_bucket_lifecycle_configuration.idp_logs); the other buckets keep their data until it is deleted
  #checkov:skip=CKV2_AWS_62:Nothing consumes object-created notifications from these buckets
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
#trivy:ignore:AWS-0086 TODO(owner): techdocs is deliberately public; the other four buckets block everything. Goes away with idp-platform (D5)
#trivy:ignore:AWS-0087 TODO(owner): techdocs is deliberately public; the other four buckets block everything. Goes away with idp-platform (D5)
#trivy:ignore:AWS-0091 TODO(owner): techdocs is deliberately public; the other four buckets block everything. Goes away with idp-platform (D5)
#trivy:ignore:AWS-0093 TODO(owner): techdocs is deliberately public; the other four buckets block everything. Goes away with idp-platform (D5)
resource "aws_s3_bucket_public_access_block" "idp_storage" {
  #checkov:skip=CKV_AWS_53:TODO(owner): techdocs is deliberately public; the other four buckets block everything (checkov cannot evaluate each.key). Goes away with idp-platform (D5)
  #checkov:skip=CKV_AWS_54:TODO(owner): techdocs is deliberately public; the other four buckets block everything (checkov cannot evaluate each.key). Goes away with idp-platform (D5)
  #checkov:skip=CKV_AWS_55:TODO(owner): techdocs is deliberately public; the other four buckets block everything (checkov cannot evaluate each.key). Goes away with idp-platform (D5)
  #checkov:skip=CKV_AWS_56:TODO(owner): techdocs is deliberately public; the other four buckets block everything (checkov cannot evaluate each.key). Goes away with idp-platform (D5)
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

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
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
#trivy:ignore:AWS-0052 TODO(owner): invalid header fields are passed through (drop_invalid_header_fields is false, as in Cloud Posse's terraform-aws-alb). Goes away with idp-platform (D5)
#trivy:ignore:AWS-0053 Internet-facing by design: aws_security_group.alb admits 443 only from allowed_cidr_blocks, whose validation rejects a /0
resource "aws_lb" "idp_platform" {
  #checkov:skip=CKV_AWS_131:TODO(owner): invalid header fields are passed through (drop_invalid_header_fields is false, as in Cloud Posse's terraform-aws-alb). Goes away with idp-platform (D5)
  #checkov:skip=CKV_AWS_150:Deletion protection is on in prod (environment == "prod") and off elsewhere so dev and staging can be torn down
  #checkov:skip=CKV2_AWS_28:TODO(owner): no WAF web ACL on this ALB (a waf instance would add cost). Goes away with idp-platform (D5)
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
  #checkov:skip=CKV2_AWS_38:TODO(owner): no DNSSEC (needs an asymmetric KMS key in us-east-1 and a DS record at the registrar). Goes away with idp-platform (D5)
  #checkov:skip=CKV2_AWS_39:TODO(owner): no query logging (new us-east-1 log group, cost); the dns component models it. Goes away with idp-platform (D5)
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
#trivy:ignore:AWS-0095 TODO(owner): unencrypted; a key needs a policy letting cloudwatch.amazonaws.com publish (kms allow_cloudwatch_alarms). Goes away with idp-platform (D5)
resource "aws_sns_topic" "alerts" {
  #checkov:skip=CKV_AWS_26:TODO(owner): unencrypted; a key needs a policy letting cloudwatch.amazonaws.com publish (kms allow_cloudwatch_alarms). Goes away with idp-platform (D5)
  name = "${local.name_prefix}-idp-alerts"

  tags = merge(local.tags, {
    Component = "notifications"
    Service   = "idp-platform"
  })
}

# Subscriptions for that topic. Without at least one, the health alarm above
# publishes into a topic nobody receives - which is how this component sat
# until now: the topic and the alarm existed, the delivery did not.
resource "aws_sns_topic_subscription" "alerts_email" {
  for_each = toset(var.notification_endpoints.email)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

# Slack and Teams take an HTTPS subscription. SNS only starts delivering once
# the endpoint answers a SubscriptionConfirmation POST by fetching the token
# URL inside it. A raw Slack or Teams incoming webhook does NOT do that, so the
# subscription would sit in PendingConfirmation forever. Point these at a
# forwarder that confirms and reshapes the payload (a Lambda function URL or an
# API Gateway), never at the webhook itself - see the README.
resource "aws_sns_topic_subscription" "alerts_https" {
  for_each = {
    for k, v in {
      slack = var.notification_endpoints.slack
      teams = var.notification_endpoints.teams
    } : k => v if v != ""
  }

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "https"
  endpoint  = each.value

  # The forwarder gets the published message itself rather than an SNS envelope
  # it would have to unwrap.
  raw_message_delivery = true
}

# KMS key for encryption
data "aws_kms_key" "s3" {
  key_id = "alias/aws/s3"
}

# Secrets Manager secrets for sensitive configuration
resource "aws_secretsmanager_secret" "idp_config" {
  #checkov:skip=CKV_AWS_149:TODO(owner): encrypted with the AWS managed key; a CMK needs kms:Decrypt for every consumer. Goes away with idp-platform (D5)
  #checkov:skip=CKV2_AWS_57:Rotated by bumping secrets_version (write-only value, re-sent with the Redis token); no rotation Lambda
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
    database_url          = local.database_url
    database_secret_arn   = module.idp_database.password_secret_arn
    redis_url             = "rediss://${aws_elasticache_replication_group.redis.primary_endpoint_address}:6379"
    redis_auth_secret_arn = aws_secretsmanager_secret.redis_auth.arn
    jwt_secret            = ephemeral.random_password.jwt_secret.result
  })
  secret_string_wo_version = var.secrets_version

  # redis_url comes from the cache's endpoint, and secret_string_wo is
  # write-only, so Terraform cannot see it change: a replaced cache (new
  # endpoint, fresh AUTH token) must re-create this version in the same apply,
  # as redis_auth does. On the cache's id only: an in-place update of the cache
  # must not re-create the secret.
  depends_on = [aws_elasticache_replication_group.redis]

  lifecycle {
    replace_triggered_by = [aws_elasticache_replication_group.redis.id]
  }
}

# Redis AUTH token, generated the way elasticache generates its own (#258): an
# ephemeral random_password sent only through the write-only attributes of the
# replication group and the secret version, in the same apply, so the two agree.
# Nothing reads the token back from Secrets Manager: an ephemeral
# aws_secretsmanager_secret_version is opened at plan time once the secret
# exists, and the CI plan role (ReadOnlyAccess) has no
# secretsmanager:GetSecretValue, so every plan would fail. random_password
# (hashicorp/random) is local and needs no AWS call at plan.
# Bump secrets_version to rotate: both write-only values are then re-sent.
resource "aws_secretsmanager_secret" "redis_auth" {
  #checkov:skip=CKV_AWS_149:TODO(owner): encrypted with the AWS managed key; a CMK needs kms:Decrypt for every consumer. Goes away with idp-platform (D5)
  #checkov:skip=CKV2_AWS_57:Rotated by bumping secrets_version, which re-sends the token to the cache and this secret in one apply; no rotation Lambda
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
  secret_string_wo         = local.redis_auth_token
  secret_string_wo_version = var.secrets_version

  # A replaced cache gets a fresh token on create; re-create this version in
  # the same apply so the secret carries that token too. On the cache's id
  # only: an in-place update of the cache must not re-create the secret.
  depends_on = [aws_elasticache_replication_group.redis]

  lifecycle {
    replace_triggered_by = [aws_elasticache_replication_group.redis.id]
  }
}

ephemeral "random_password" "redis_auth_token" {
  length           = local.redis_auth_token_generator.length
  special          = local.redis_auth_token_generator.special
  override_special = local.redis_auth_token_generator.override_special
  min_upper        = local.redis_auth_token_generator.min_upper
  min_lower        = local.redis_auth_token_generator.min_lower
  min_numeric      = local.redis_auth_token_generator.min_numeric
  min_special      = local.redis_auth_token_generator.min_special
}

ephemeral "random_password" "jwt_secret" {
  length  = 64
  special = false
}

locals {
  # A local, not inline: tests cannot assert an ephemeral resource's arguments.
  # Same shape as elasticache's auth_token_generator (Cloud Posse redis_cluster).
  redis_auth_token_generator = {
    length           = 128
    special          = true
    override_special = "#^-"
    min_upper        = 3
    min_lower        = 3
    min_numeric      = 3
    min_special      = 3
  }

  redis_auth_token = ephemeral.random_password.redis_auth_token.result
}
