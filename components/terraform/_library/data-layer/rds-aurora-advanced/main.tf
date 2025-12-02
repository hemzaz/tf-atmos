locals {
  name_prefix      = "${var.name_prefix}-${var.environment}"
  cluster_id       = "${local.name_prefix}-aurora"
  is_postgresql    = startswith(var.engine, "aurora-postgresql")
  is_mysql         = startswith(var.engine, "aurora-mysql")
  port             = var.port != null ? var.port : (local.is_postgresql ? 5432 : 3306)
  create_sg        = length(var.security_group_ids) == 0
  create_secret    = var.master_password_secret_arn == null

  # CloudWatch log exports based on engine
  default_log_exports = local.is_postgresql ? ["postgresql"] : ["error", "general", "slowquery"]
  log_exports         = var.enable_cloudwatch_logs_exports != null ? var.enable_cloudwatch_logs_exports : local.default_log_exports

  # Default optimized cluster parameters
  default_cluster_parameters_postgresql = [
    {
      name         = "shared_preload_libraries"
      value        = "pg_stat_statements,auto_explain"
      apply_method = "pending-reboot"
    },
    {
      name         = "log_min_duration_statement"
      value        = "1000" # Log queries > 1 second
      apply_method = "immediate"
    },
    {
      name         = "log_connections"
      value        = "1"
      apply_method = "immediate"
    },
    {
      name         = "log_disconnections"
      value        = "1"
      apply_method = "immediate"
    },
    {
      name         = "log_lock_waits"
      value        = "1"
      apply_method = "immediate"
    },
    {
      name         = "log_statement"
      value        = "ddl"
      apply_method = "immediate"
    },
    {
      name         = "auto_explain.log_min_duration"
      value        = "5000" # Explain queries > 5 seconds
      apply_method = "immediate"
    },
    {
      name         = "rds.force_ssl"
      value        = "1"
      apply_method = "immediate"
    }
  ]

  default_cluster_parameters_mysql = [
    {
      name         = "slow_query_log"
      value        = "1"
      apply_method = "immediate"
    },
    {
      name         = "long_query_time"
      value        = "1"
      apply_method = "immediate"
    },
    {
      name         = "log_queries_not_using_indexes"
      value        = "1"
      apply_method = "immediate"
    },
    {
      name         = "require_secure_transport"
      value        = "ON"
      apply_method = "immediate"
    }
  ]

  cluster_parameters = length(var.cluster_parameters) > 0 ? var.cluster_parameters : (
    local.is_postgresql ? local.default_cluster_parameters_postgresql : local.default_cluster_parameters_mysql
  )

  # Common tags
  common_tags = merge(
    {
      Name        = local.cluster_id
      Environment = var.environment
      ManagedBy   = "Terraform"
      Module      = "rds-aurora-advanced"
      Engine      = var.engine
    },
    var.tags
  )
}

#------------------------------------------------------------------------------
# Data Sources
#------------------------------------------------------------------------------

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

#------------------------------------------------------------------------------
# Random Password (if secret not provided)
#------------------------------------------------------------------------------

resource "random_password" "master" {
  count = local.create_secret ? 1 : 0

  length  = 32
  special = true
  # Exclude characters that might cause issues
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

#------------------------------------------------------------------------------
# Secrets Manager Secret
#------------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "master_password" {
  count = local.create_secret ? 1 : 0

  name        = "${local.cluster_id}-master-password"
  description = "Master password for ${local.cluster_id} Aurora cluster"
  kms_key_id  = var.kms_key_id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_id}-master-password"
    }
  )
}

resource "aws_secretsmanager_secret_version" "master_password" {
  count = local.create_secret ? 1 : 0

  secret_id = aws_secretsmanager_secret.master_password[0].id
  secret_string = jsonencode({
    username            = var.master_username
    password            = random_password.master[0].result
    engine              = var.engine
    host                = aws_rds_cluster.this.endpoint
    port                = local.port
    dbClusterIdentifier = aws_rds_cluster.this.cluster_identifier
  })
}

#------------------------------------------------------------------------------
# Secrets Rotation
#------------------------------------------------------------------------------

resource "aws_secretsmanager_secret_rotation" "master_password" {
  count = var.enable_secrets_rotation && local.create_secret ? 1 : 0

  secret_id           = aws_secretsmanager_secret.master_password[0].id
  rotation_lambda_arn = aws_lambda_function.rotate_secret[0].arn

  rotation_rules {
    automatically_after_days = var.secrets_rotation_days
  }

  depends_on = [
    aws_lambda_permission.allow_secret_rotation
  ]
}

#------------------------------------------------------------------------------
# Get existing secret (if provided)
#------------------------------------------------------------------------------

data "aws_secretsmanager_secret" "existing_password" {
  count = local.create_secret ? 0 : 1
  arn   = var.master_password_secret_arn
}

data "aws_secretsmanager_secret_version" "existing_password" {
  count     = local.create_secret ? 0 : 1
  secret_id = data.aws_secretsmanager_secret.existing_password[0].id
}

#------------------------------------------------------------------------------
# Security Group
#------------------------------------------------------------------------------

resource "aws_security_group" "aurora" {
  count = local.create_sg ? 1 : 0

  name_prefix = "${local.cluster_id}-"
  description = "Security group for ${local.cluster_id} Aurora cluster"
  vpc_id      = var.vpc_id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_id}-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "aurora_ingress_cidr" {
  count = local.create_sg && length(var.allowed_cidr_blocks) > 0 ? 1 : 0

  type              = "ingress"
  from_port         = local.port
  to_port           = local.port
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks
  security_group_id = aws_security_group.aurora[0].id
  description       = "Allow Aurora access from specified CIDR blocks"
}

resource "aws_security_group_rule" "aurora_ingress_sg" {
  for_each = local.create_sg ? toset(var.allowed_security_group_ids) : []

  type                     = "ingress"
  from_port                = local.port
  to_port                  = local.port
  protocol                 = "tcp"
  source_security_group_id = each.value
  security_group_id        = aws_security_group.aurora[0].id
  description              = "Allow Aurora access from security group ${each.value}"
}

resource "aws_security_group_rule" "aurora_egress" {
  count = local.create_sg ? 1 : 0

  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.aurora[0].id
  description       = "Allow all outbound traffic"
}

#------------------------------------------------------------------------------
# DB Subnet Group
#------------------------------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name       = "${local.cluster_id}-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_id}-subnet-group"
    }
  )
}

#------------------------------------------------------------------------------
# Cluster Parameter Group
#------------------------------------------------------------------------------

resource "aws_rds_cluster_parameter_group" "this" {
  count = var.cluster_parameter_group_name == null ? 1 : 0

  name_prefix = "${local.cluster_id}-cluster-"
  family      = local.is_postgresql ? "aurora-postgresql15" : "aurora-mysql8.0"
  description = "Cluster parameter group for ${local.cluster_id}"

  dynamic "parameter" {
    for_each = local.cluster_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_id}-cluster-params"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

#------------------------------------------------------------------------------
# DB Parameter Group
#------------------------------------------------------------------------------

resource "aws_db_parameter_group" "this" {
  count = var.db_parameter_group_name == null ? 1 : 0

  name_prefix = "${local.cluster_id}-db-"
  family      = local.is_postgresql ? "aurora-postgresql15" : "aurora-mysql8.0"
  description = "DB parameter group for ${local.cluster_id} instances"

  dynamic "parameter" {
    for_each = var.db_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_id}-db-params"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

#------------------------------------------------------------------------------
# IAM Role for Enhanced Monitoring
#------------------------------------------------------------------------------

resource "aws_iam_role" "enhanced_monitoring" {
  count = var.enable_enhanced_monitoring && var.monitoring_role_arn == null ? 1 : 0

  name_prefix = "${local.cluster_id}-mon-"
  description = "IAM role for RDS Enhanced Monitoring of ${local.cluster_id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
  ]

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# Global Cluster (optional)
#------------------------------------------------------------------------------

resource "aws_rds_global_cluster" "this" {
  count = var.enable_global_cluster && var.is_primary_cluster ? 1 : 0

  global_cluster_identifier = var.global_cluster_identifier
  engine                    = var.engine
  engine_version            = var.engine_version
  database_name             = var.database_name
  storage_encrypted         = var.storage_encrypted

  lifecycle {
    prevent_destroy = true
  }
}

#------------------------------------------------------------------------------
# Aurora Cluster
#------------------------------------------------------------------------------

resource "aws_rds_cluster" "this" {
  cluster_identifier     = local.cluster_id
  engine                 = var.engine
  engine_version         = var.engine_version
  engine_mode            = var.engine_mode
  database_name          = var.database_name
  master_username        = var.master_username
  master_password        = local.create_secret ? random_password.master[0].result : jsondecode(data.aws_secretsmanager_secret_version.existing_password[0].secret_string)["password"]
  port                   = local.port
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = local.create_sg ? [aws_security_group.aurora[0].id] : var.security_group_ids

  # High Availability
  availability_zones = var.enable_multi_az ? null : []

  # Backup Configuration
  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = var.copy_tags_to_snapshot
  skip_final_snapshot          = var.skip_final_snapshot
  final_snapshot_identifier    = var.enable_final_snapshot ? "${local.cluster_id}-final-${formatdate("YYYY-MM-DD-hhmm", timestamp())}" : null
  snapshot_identifier          = var.snapshot_identifier

  # Security
  storage_encrypted               = var.storage_encrypted
  kms_key_id                      = var.kms_key_id
  iam_database_authentication_enabled = var.enable_iam_database_authentication
  deletion_protection             = var.enable_deletion_protection
  enabled_cloudwatch_logs_exports = local.log_exports

  # Parameter Groups
  db_cluster_parameter_group_name = var.cluster_parameter_group_name != null ? var.cluster_parameter_group_name : aws_rds_cluster_parameter_group.this[0].name

  # Serverless v2 Scaling Configuration
  dynamic "serverlessv2_scaling_configuration" {
    for_each = var.enable_serverlessv2 ? [1] : []
    content {
      min_capacity = var.serverlessv2_min_capacity
      max_capacity = var.serverlessv2_max_capacity
    }
  }

  # Global Cluster
  global_cluster_identifier = var.enable_global_cluster ? var.global_cluster_identifier : null

  # Updates
  apply_immediately          = var.apply_immediately
  allow_major_version_upgrade = false
  auto_minor_version_upgrade = var.auto_minor_version_upgrade

  tags = merge(
    local.common_tags,
    {
      Name = local.cluster_id
    }
  )

  lifecycle {
    ignore_changes = [
      # Ignore snapshot_identifier after creation
      snapshot_identifier,
      # Ignore final_snapshot_identifier timestamp
      final_snapshot_identifier,
    ]
  }

  depends_on = [
    aws_db_subnet_group.this,
    aws_rds_cluster_parameter_group.this,
  ]
}

#------------------------------------------------------------------------------
# Aurora Cluster Instances
#------------------------------------------------------------------------------

resource "aws_rds_cluster_instance" "this" {
  count = var.instance_count

  identifier              = "${local.cluster_id}-${count.index + 1}"
  cluster_identifier      = aws_rds_cluster.this.id
  instance_class          = var.enable_serverlessv2 ? "db.serverless" : var.instance_class
  engine                  = aws_rds_cluster.this.engine
  engine_version          = aws_rds_cluster.this.engine_version
  db_parameter_group_name = var.db_parameter_group_name != null ? var.db_parameter_group_name : aws_db_parameter_group.this[0].name

  # Performance Insights
  performance_insights_enabled    = var.enable_performance_insights
  performance_insights_kms_key_id = var.enable_performance_insights ? var.performance_insights_kms_key_id : null
  performance_insights_retention_period = var.enable_performance_insights ? var.performance_insights_retention_period : null

  # Enhanced Monitoring
  monitoring_interval = var.enable_enhanced_monitoring ? var.monitoring_interval : 0
  monitoring_role_arn = var.enable_enhanced_monitoring ? (
    var.monitoring_role_arn != null ? var.monitoring_role_arn : aws_iam_role.enhanced_monitoring[0].arn
  ) : null

  # Updates
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately
  promotion_tier             = count.index

  # Make writer instance (first one) publicly accessible in dev environments
  publicly_accessible = false

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_id}-${count.index + 1}"
      Role = count.index == 0 ? "writer" : "reader"
    }
  )

  depends_on = [
    aws_rds_cluster.this,
    aws_db_parameter_group.this,
  ]
}

#------------------------------------------------------------------------------
# Auto Scaling for Read Replicas
#------------------------------------------------------------------------------

resource "aws_appautoscaling_target" "read_replica" {
  count = var.enable_autoscaling && var.instance_count > 1 ? 1 : 0

  max_capacity       = var.autoscaling_max_capacity
  min_capacity       = var.autoscaling_min_capacity
  resource_id        = "cluster:${aws_rds_cluster.this.cluster_identifier}"
  scalable_dimension = "rds:cluster:ReadReplicaCount"
  service_namespace  = "rds"
}

resource "aws_appautoscaling_policy" "read_replica_cpu" {
  count = var.enable_autoscaling && var.instance_count > 1 ? 1 : 0

  name               = "${local.cluster_id}-read-replica-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.read_replica[0].resource_id
  scalable_dimension = aws_appautoscaling_target.read_replica[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.read_replica[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "RDSReaderAverageCPUUtilization"
    }
    target_value       = var.autoscaling_target_cpu
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

resource "aws_appautoscaling_policy" "read_replica_connections" {
  count = var.enable_autoscaling && var.instance_count > 1 ? 1 : 0

  name               = "${local.cluster_id}-read-replica-connections"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.read_replica[0].resource_id
  scalable_dimension = aws_appautoscaling_target.read_replica[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.read_replica[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "RDSReaderAverageDatabaseConnections"
    }
    target_value       = var.autoscaling_target_connections
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

#------------------------------------------------------------------------------
# CloudWatch Alarms
#------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${local.cluster_id}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors RDS CPU utilization"
  alarm_actions       = []

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.this.cluster_identifier
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "freeable_memory_low" {
  alarm_name          = "${local.cluster_id}-memory-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "1000000000" # 1GB in bytes
  alarm_description   = "This metric monitors RDS freeable memory"
  alarm_actions       = []

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.this.cluster_identifier
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "database_connections_high" {
  alarm_name          = "${local.cluster_id}-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors RDS database connections"
  alarm_actions       = []

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.this.cluster_identifier
  }

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# Lambda for Secret Rotation (simplified)
#------------------------------------------------------------------------------

# Note: In production, use AWS SecretsManager rotation lambda or custom implementation
# This is a placeholder showing the structure

resource "aws_lambda_function" "rotate_secret" {
  count = var.enable_secrets_rotation && local.create_secret ? 1 : 0

  filename      = "${path.module}/lambda_rotation_stub.zip"
  function_name = "${local.cluster_id}-rotate-secret"
  role          = aws_iam_role.lambda_rotation[0].arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 30

  environment {
    variables = {
      CLUSTER_ARN = aws_rds_cluster.this.arn
    }
  }

  tags = local.common_tags

  lifecycle {
    ignore_changes = [filename]
  }
}

resource "aws_iam_role" "lambda_rotation" {
  count = var.enable_secrets_rotation && local.create_secret ? 1 : 0

  name_prefix = "${local.cluster_id}-rotation-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "lambda_rotation_basic" {
  count = var.enable_secrets_rotation && local.create_secret ? 1 : 0

  role       = aws_iam_role.lambda_rotation[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_rotation_secrets" {
  count = var.enable_secrets_rotation && local.create_secret ? 1 : 0

  name = "${local.cluster_id}-rotation-secrets"
  role = aws_iam_role.lambda_rotation[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage"
        ]
        Resource = aws_secretsmanager_secret.master_password[0].arn
      },
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBClusters",
          "rds:ModifyDBCluster"
        ]
        Resource = aws_rds_cluster.this.arn
      }
    ]
  })
}

resource "aws_lambda_permission" "allow_secret_rotation" {
  count = var.enable_secrets_rotation && local.create_secret ? 1 : 0

  statement_id  = "AllowExecutionFromSecretsManager"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rotate_secret[0].function_name
  principal     = "secretsmanager.amazonaws.com"
}

# Create a stub lambda deployment package
resource "null_resource" "lambda_stub" {
  count = var.enable_secrets_rotation && local.create_secret ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ${path.module}/lambda_tmp
      cat > ${path.module}/lambda_tmp/index.py << 'EOF'
def handler(event, context):
    # Placeholder for secret rotation logic
    # In production, implement actual rotation logic
    return {"statusCode": 200}
EOF
      cd ${path.module}/lambda_tmp && zip ${path.module}/lambda_rotation_stub.zip index.py
      rm -rf ${path.module}/lambda_tmp
    EOT
  }

  triggers = {
    always_run = timestamp()
  }
}
