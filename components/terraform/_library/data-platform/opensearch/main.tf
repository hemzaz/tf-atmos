##############################################
# OpenSearch Domain
##############################################

resource "aws_opensearch_domain" "main" {
  domain_name    = var.domain_name
  engine_version = var.engine_version

  cluster_config {
    instance_type            = var.instance_type
    instance_count           = var.instance_count
    dedicated_master_enabled = var.dedicated_master_enabled
    dedicated_master_type    = var.dedicated_master_enabled ? var.dedicated_master_type : null
    dedicated_master_count   = var.dedicated_master_enabled ? var.dedicated_master_count : null
    zone_awareness_enabled   = var.zone_awareness_enabled
    warm_enabled             = var.warm_enabled
    warm_count               = var.warm_enabled ? var.warm_count : null
    warm_type                = var.warm_enabled ? var.warm_type : null

    dynamic "zone_awareness_config" {
      for_each = var.zone_awareness_enabled ? [1] : []
      content {
        availability_zone_count = var.availability_zone_count
      }
    }

    dynamic "cold_storage_options" {
      for_each = var.cold_storage_enabled ? [1] : []
      content {
        enabled = true
      }
    }
  }

  ebs_options {
    ebs_enabled = true
    volume_size = var.ebs_volume_size
    volume_type = var.ebs_volume_type
    iops        = var.ebs_volume_type == "gp3" || var.ebs_volume_type == "io1" ? var.ebs_iops : null
    throughput  = var.ebs_volume_type == "gp3" ? var.ebs_throughput : null
  }

  encrypt_at_rest {
    enabled    = true
    kms_key_id = var.kms_key_id
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https                   = true
    tls_security_policy             = var.tls_security_policy
    custom_endpoint_enabled         = var.custom_endpoint != null
    custom_endpoint                 = var.custom_endpoint
    custom_endpoint_certificate_arn = var.custom_endpoint_certificate_arn
  }

  dynamic "vpc_options" {
    for_each = var.subnet_ids != null ? [1] : []
    content {
      subnet_ids         = var.subnet_ids
      security_group_ids = [aws_security_group.opensearch[0].id]
    }
  }

  advanced_security_options {
    enabled                        = true
    internal_user_database_enabled = var.internal_user_database_enabled
    master_user_options {
      master_user_arn      = var.master_user_arn
      master_user_name     = var.internal_user_database_enabled ? var.master_user_name : null
      master_user_password = var.internal_user_database_enabled ? var.master_user_password : null
    }
  }

  dynamic "cognito_options" {
    for_each = var.cognito_user_pool_id != null ? [1] : []
    content {
      enabled          = true
      user_pool_id     = var.cognito_user_pool_id
      identity_pool_id = var.cognito_identity_pool_id
      role_arn         = aws_iam_role.cognito[0].arn
    }
  }

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.index_slow_logs.arn
    log_type                 = "INDEX_SLOW_LOGS"
  }

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.search_slow_logs.arn
    log_type                 = "SEARCH_SLOW_LOGS"
  }

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.error_logs.arn
    log_type                 = "ES_APPLICATION_LOGS"
  }

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.audit_logs.arn
    log_type                 = "AUDIT_LOGS"
  }

  advanced_options = merge(
    {
      "rest.action.multi.allow_explicit_index" = "true"
      "override_main_response_version"         = "false"
    },
    var.advanced_options
  )

  dynamic "auto_tune_options" {
    for_each = var.auto_tune_enabled ? [1] : []
    content {
      desired_state       = "ENABLED"
      rollback_on_disable = var.auto_tune_rollback_on_disable

      maintenance_schedule {
        start_at = var.auto_tune_start_at
        duration {
          value = var.auto_tune_duration_value
          unit  = var.auto_tune_duration_unit
        }
        cron_expression_for_recurrence = var.auto_tune_cron_expression
      }
    }
  }

  snapshot_options {
    automated_snapshot_start_hour = var.automated_snapshot_start_hour
  }

  tags = merge(
    var.tags,
    {
      Name      = var.domain_name
      Module    = "opensearch"
      ManagedBy = "terraform"
    }
  )

  depends_on = [
    aws_iam_service_linked_role.opensearch
  ]
}

##############################################
# Service-Linked Role
##############################################

resource "aws_iam_service_linked_role" "opensearch" {
  count            = var.create_service_linked_role ? 1 : 0
  aws_service_name = "opensearchservice.amazonaws.com"
  description      = "Service-linked role for OpenSearch"
}

##############################################
# Security Group (VPC deployment)
##############################################

resource "aws_security_group" "opensearch" {
  count = var.subnet_ids != null ? 1 : 0

  name        = "${var.domain_name}-opensearch"
  description = "Security group for OpenSearch domain ${var.domain_name}"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "HTTPS access to OpenSearch"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(
    var.tags,
    {
      Name      = "${var.domain_name}-opensearch"
      ManagedBy = "terraform"
    }
  )
}

##############################################
# Domain Access Policy
##############################################

data "aws_iam_policy_document" "domain_policy" {
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = var.access_principals
    }
    actions = [
      "es:ESHttp*"
    ]
    resources = [
      "${aws_opensearch_domain.main.arn}/*"
    ]
  }
}

resource "aws_opensearch_domain_policy" "main" {
  domain_name     = aws_opensearch_domain.main.domain_name
  access_policies = data.aws_iam_policy_document.domain_policy.json
}

##############################################
# Cognito IAM Role
##############################################

resource "aws_iam_role" "cognito" {
  count = var.cognito_user_pool_id != null ? 1 : 0

  name = "${var.domain_name}-cognito-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "opensearchservice.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "cognito" {
  count = var.cognito_user_pool_id != null ? 1 : 0

  name = "${var.domain_name}-cognito-policy"
  role = aws_iam_role.cognito[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:DescribeUserPool",
          "cognito-idp:CreateUserPoolClient",
          "cognito-idp:DeleteUserPoolClient",
          "cognito-idp:UpdateUserPoolClient",
          "cognito-idp:DescribeUserPoolClient",
          "cognito-idp:AdminInitiateAuth",
          "cognito-idp:AdminUserGlobalSignOut",
          "cognito-idp:ListUserPoolClients",
          "cognito-identity:DescribeIdentityPool",
          "cognito-identity:UpdateIdentityPool",
          "cognito-identity:SetIdentityPoolRoles",
          "cognito-identity:GetIdentityPoolRoles"
        ]
        Resource = "*"
      }
    ]
  })
}

##############################################
# CloudWatch Log Groups
##############################################

resource "aws_cloudwatch_log_group" "index_slow_logs" {
  name              = "/aws/opensearch/${var.domain_name}/index-slow-logs"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_id

  tags = merge(
    var.tags,
    {
      Name      = "${var.domain_name}-index-slow-logs"
      ManagedBy = "terraform"
    }
  )
}

resource "aws_cloudwatch_log_group" "search_slow_logs" {
  name              = "/aws/opensearch/${var.domain_name}/search-slow-logs"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_id

  tags = merge(
    var.tags,
    {
      Name      = "${var.domain_name}-search-slow-logs"
      ManagedBy = "terraform"
    }
  )
}

resource "aws_cloudwatch_log_group" "error_logs" {
  name              = "/aws/opensearch/${var.domain_name}/error-logs"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_id

  tags = merge(
    var.tags,
    {
      Name      = "${var.domain_name}-error-logs"
      ManagedBy = "terraform"
    }
  )
}

resource "aws_cloudwatch_log_group" "audit_logs" {
  name              = "/aws/opensearch/${var.domain_name}/audit-logs"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_id

  tags = merge(
    var.tags,
    {
      Name      = "${var.domain_name}-audit-logs"
      ManagedBy = "terraform"
    }
  )
}

resource "aws_cloudwatch_log_resource_policy" "opensearch" {
  policy_name = "${var.domain_name}-opensearch-logs"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "es.amazonaws.com"
        }
        Action = [
          "logs:PutLogEvents",
          "logs:CreateLogStream"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.index_slow_logs.arn}:*",
          "${aws_cloudwatch_log_group.search_slow_logs.arn}:*",
          "${aws_cloudwatch_log_group.error_logs.arn}:*",
          "${aws_cloudwatch_log_group.audit_logs.arn}:*"
        ]
      }
    ]
  })
}

##############################################
# CloudWatch Alarms
##############################################

resource "aws_cloudwatch_metric_alarm" "cluster_red" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.domain_name}-cluster-red"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ClusterStatus.red"
  namespace           = "AWS/ES"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "OpenSearch cluster status is RED"
  alarm_actions       = var.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    DomainName = aws_opensearch_domain.main.domain_name
    ClientId   = data.aws_caller_identity.current.account_id
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "cluster_yellow" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.domain_name}-cluster-yellow"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  metric_name         = "ClusterStatus.yellow"
  namespace           = "AWS/ES"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "OpenSearch cluster status is YELLOW"
  alarm_actions       = var.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    DomainName = aws_opensearch_domain.main.domain_name
    ClientId   = data.aws_caller_identity.current.account_id
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "free_storage_space" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.domain_name}-low-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/ES"
  period              = 300
  statistic           = "Minimum"
  threshold           = var.free_storage_threshold_mb * 1024
  alarm_description   = "OpenSearch free storage is low"
  alarm_actions       = var.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    DomainName = aws_opensearch_domain.main.domain_name
    ClientId   = data.aws_caller_identity.current.account_id
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.domain_name}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ES"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_utilization_threshold
  alarm_description   = "OpenSearch CPU utilization is high"
  alarm_actions       = var.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    DomainName = aws_opensearch_domain.main.domain_name
    ClientId   = data.aws_caller_identity.current.account_id
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "jvm_memory_pressure" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.domain_name}-high-jvm-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "JVMMemoryPressure"
  namespace           = "AWS/ES"
  period              = 300
  statistic           = "Maximum"
  threshold           = var.jvm_memory_pressure_threshold
  alarm_description   = "OpenSearch JVM memory pressure is high"
  alarm_actions       = var.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    DomainName = aws_opensearch_domain.main.domain_name
    ClientId   = data.aws_caller_identity.current.account_id
  }

  tags = var.tags
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
