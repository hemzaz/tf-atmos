# components/terraform/rds/main.tf

# Local variables for performance optimization
locals {
  # Performance optimization parameters based on engine
  performance_parameters = var.engine == "postgres" ? {
    shared_preload_libraries = {
      name  = "shared_preload_libraries"
      value = "pg_stat_statements"
    }
    log_statement = {
      name  = "log_statement"
      value = "all"
    }
    log_min_duration_statement = {
      name  = "log_min_duration_statement"
      value = "1000" # Log queries taking longer than 1 second
    }
    max_connections = {
      name  = "max_connections"
      value = tostring(var.max_connections)
    }
    work_mem = {
      name  = "work_mem"
      value = "${var.work_mem_mb}MB"
    }
    maintenance_work_mem = {
      name  = "maintenance_work_mem"
      value = "${var.maintenance_work_mem_mb}MB"
    }
    effective_cache_size = {
      name  = "effective_cache_size"
      value = "${var.effective_cache_size_mb}MB"
    }
    random_page_cost = {
      name  = "random_page_cost"
      value = tostring(var.random_page_cost)
    }
    checkpoint_completion_target = {
      name  = "checkpoint_completion_target"
      value = tostring(var.checkpoint_completion_target)
    }
  } : {
    # MySQL performance parameters
    innodb_buffer_pool_size = {
      name  = "innodb_buffer_pool_size"
      value = "{DBInstanceClassMemory*3/4}"
    }
    max_connections = {
      name  = "max_connections"
      value = tostring(var.max_connections)
    }
    innodb_log_file_size = {
      name  = "innodb_log_file_size"
      value = "268435456" # 256MB
    }
    query_cache_type = {
      name  = "query_cache_type"
      value = "1"
    }
    query_cache_size = {
      name  = "query_cache_size"
      value = "67108864" # 64MB
    }
    slow_query_log = {
      name  = "slow_query_log"
      value = "1"
    }
    long_query_time = {
      name  = "long_query_time"
      value = "1"
    }
  }
}

resource "aws_db_subnet_group" "main" {
  name        = "${var.tags["Environment"]}-${var.identifier}-subnet-group"
  description = "Subnet group for ${var.identifier} RDS instance"
  subnet_ids  = var.subnet_ids

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-${var.identifier}-subnet-group"
    }
  )
}

# Enhanced security group with detailed rules
resource "aws_security_group" "rds" {
  name        = "${var.tags["Environment"]}-${var.identifier}-sg"
  description = "Security group for ${var.identifier} RDS instance"
  vpc_id      = var.vpc_id

  # Main database access from application security groups
  ingress {
    description     = "Database access from allowed security groups"
    from_port       = var.port
    to_port         = var.port
    protocol        = "tcp"
    security_groups = var.allowed_security_groups
  }

  # RDS Proxy access (if enabled)
  dynamic "ingress" {
    for_each = var.enable_rds_proxy ? [1] : []
    content {
      description = "RDS Proxy access"
      from_port   = var.port
      to_port     = var.port
      protocol    = "tcp"
      self        = true
    }
  }

  # Custom ingress rules
  dynamic "ingress" {
    for_each = var.custom_ingress_rules
    content {
      description     = ingress.value.description
      from_port       = ingress.value.from_port
      to_port         = ingress.value.to_port
      protocol        = ingress.value.protocol
      cidr_blocks     = lookup(ingress.value, "cidr_blocks", null)
      security_groups = lookup(ingress.value, "security_groups", null)
    }
  }

  # Restrictive egress - only necessary outbound connections
  egress {
    description = "HTTPS for AWS API calls"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Additional egress rules if needed
  dynamic "egress" {
    for_each = var.additional_egress_rules
    content {
      description     = lookup(egress.value, "description", "Custom egress rule")
      from_port       = egress.value.from_port
      to_port         = egress.value.to_port
      protocol        = egress.value.protocol
      prefix_list_ids = lookup(egress.value, "prefix_list_ids", null)
      security_groups = lookup(egress.value, "security_groups", null)
      cidr_blocks     = lookup(egress.value, "cidr_blocks", null)
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-${var.identifier}-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Security group for RDS Proxy (if enabled)
resource "aws_security_group" "rds_proxy" {
  count = var.enable_rds_proxy ? 1 : 0

  name        = "${var.tags["Environment"]}-${var.identifier}-proxy-sg"
  description = "Security group for ${var.identifier} RDS Proxy"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Database proxy access from applications"
    from_port       = var.port
    to_port         = var.port
    protocol        = "tcp"
    security_groups = var.allowed_security_groups
  }

  egress {
    description     = "Database access to RDS instance"
    from_port       = var.port
    to_port         = var.port
    protocol        = "tcp"
    security_groups = [aws_security_group.rds.id]
  }

  egress {
    description = "HTTPS for Secrets Manager"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-${var.identifier}-proxy-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Enhanced parameter group with performance optimizations
resource "aws_db_parameter_group" "main" {
  name   = "${var.tags["Environment"]}-${var.identifier}-pg"
  family = var.family

  # Performance optimization parameters
  dynamic "parameter" {
    for_each = merge(var.parameters, local.performance_parameters)
    content {
      name  = parameter.value.name
      value = parameter.value.value
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-${var.identifier}-pg"
    }
  )
}

# Connection pooling with RDS Proxy
resource "aws_db_proxy" "main" {
  count = var.enable_rds_proxy ? 1 : 0

  name                   = "${var.tags["Environment"]}-${var.identifier}-proxy"
  engine_family         = var.engine == "postgres" ? "POSTGRESQL" : "MYSQL"
  auth {
    auth_scheme = "SECRETS"
    secret_arn  = aws_secretsmanager_secret.db_password.arn
  }
  role_arn               = aws_iam_role.rds_proxy[0].arn
  vpc_subnet_ids         = var.subnet_ids
  require_tls            = var.proxy_require_tls
  idle_client_timeout    = var.proxy_idle_client_timeout
  max_connections_percent = var.proxy_max_connections_percent
  max_idle_connections_percent = var.proxy_max_idle_connections_percent

  target {
    db_instance_identifier = aws_db_instance.main.id
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-${var.identifier}-proxy"
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.rds_proxy
  ]
}

# IAM role for RDS Proxy
resource "aws_iam_role" "rds_proxy" {
  count = var.enable_rds_proxy ? 1 : 0

  name = "${var.tags["Environment"]}-${var.identifier}-rds-proxy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-${var.identifier}-rds-proxy-role"
    }
  )
}

resource "aws_iam_policy" "rds_proxy" {
  count = var.enable_rds_proxy ? 1 : 0

  name        = "${var.tags["Environment"]}-${var.identifier}-rds-proxy-policy"
  description = "Policy for RDS Proxy to access Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.db_password.arn
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "rds_proxy" {
  count = var.enable_rds_proxy ? 1 : 0

  role       = aws_iam_role.rds_proxy[0].name
  policy_arn = aws_iam_policy.rds_proxy[0].arn
}

resource "random_password" "password" {
  length  = 16
  special = false
}

resource "aws_secretsmanager_secret" "db_password" {
  name        = "${var.tags["Environment"]}/${var.identifier}/password"
  description = "Password for ${var.identifier} RDS instance"

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-${var.identifier}-secret"
    }
  )
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({
    username = var.username
    password = random_password.password.result
    engine   = var.engine
    host     = aws_db_instance.main.address
    port     = var.port
    dbname   = var.db_name
  })
}

resource "aws_iam_role" "monitoring" {
  count = var.monitoring_interval > 0 && var.create_monitoring_role ? 1 : 0

  name = "${var.tags["Environment"]}-${var.identifier}-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-${var.identifier}-monitoring-role"
    }
  )
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  count = var.monitoring_interval > 0 && var.create_monitoring_role ? 1 : 0

  role       = aws_iam_role.monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Read replica for performance scaling
resource "aws_db_instance" "read_replica" {
  count = var.create_read_replica ? 1 : 0

  identifier                  = "${var.tags["Environment"]}-${var.identifier}-read-replica"
  replicate_source_db         = aws_db_instance.main.id
  instance_class              = var.read_replica_instance_class != null ? var.read_replica_instance_class : var.instance_class
  monitoring_interval         = var.monitoring_interval
  monitoring_role_arn         = var.monitoring_interval > 0 ? (var.create_monitoring_role ? aws_iam_role.monitoring[0].arn : var.monitoring_role_arn) : null
  performance_insights_enabled = var.performance_insights_enabled
  skip_final_snapshot         = true

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-${var.identifier}-read-replica"
      Role = "read-replica"
    }
  )
}

resource "aws_db_instance" "main" {
  identifier                   = "${var.tags["Environment"]}-${var.identifier}"
  engine                       = var.engine
  engine_version               = var.engine_version
  instance_class               = var.instance_class
  allocated_storage            = var.allocated_storage
  max_allocated_storage        = var.max_allocated_storage
  storage_type                 = var.storage_type
  storage_encrypted            = var.storage_encrypted
  kms_key_id                   = var.kms_key_id
  username                     = var.username
  password                     = random_password.password.result
  port                         = var.port
  db_name                      = var.db_name
  parameter_group_name         = aws_db_parameter_group.main.name
  db_subnet_group_name         = aws_db_subnet_group.main.name
  vpc_security_group_ids       = [aws_security_group.rds.id]
  availability_zone            = var.availability_zone
  multi_az                     = var.multi_az
  publicly_accessible          = var.publicly_accessible
  allow_major_version_upgrade  = var.allow_major_version_upgrade
  auto_minor_version_upgrade   = var.auto_minor_version_upgrade
  backup_retention_period      = var.backup_retention_period
  backup_window                = var.backup_window
  maintenance_window           = var.maintenance_window
  skip_final_snapshot          = var.skip_final_snapshot
  final_snapshot_identifier    = var.skip_final_snapshot ? null : "${var.tags["Environment"]}-${var.identifier}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  copy_tags_to_snapshot        = var.copy_tags_to_snapshot
  monitoring_interval          = var.monitoring_interval
  monitoring_role_arn          = var.monitoring_interval > 0 ? (var.create_monitoring_role ? aws_iam_role.monitoring[0].arn : var.monitoring_role_arn) : null
  performance_insights_enabled = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_retention_period
  deletion_protection          = var.deletion_protection

  # Storage performance optimizations
  iops                         = var.storage_type == "io1" || var.storage_type == "gp3" ? var.iops : null
  storage_throughput           = var.storage_type == "gp3" ? var.storage_throughput : null

  # Enhanced monitoring and logging
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  lifecycle {
    prevent_destroy = var.prevent_destroy
    ignore_changes  = [password] # Ignore password changes to prevent unnecessary updates
  }

  depends_on = [
    aws_iam_role_policy_attachment.monitoring
  ]

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-${var.identifier}"
      Role = "primary"
    }
  )
}

# Performance monitoring alarms
resource "aws_cloudwatch_metric_alarm" "database_cpu" {
  count = var.create_performance_alarms ? 1 : 0

  alarm_name          = "${var.tags["Environment"]}-${var.identifier}-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "120"
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold
  alarm_description   = "This metric monitors cpu utilization"
  alarm_actions       = var.sns_topic_arn != null ? [var.sns_topic_arn] : []

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "database_connections" {
  count = var.create_performance_alarms ? 1 : 0

  alarm_name          = "${var.tags["Environment"]}-${var.identifier}-connection-count"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "120"
  statistic           = "Average"
  threshold           = var.connection_alarm_threshold
  alarm_description   = "This metric monitors database connections"
  alarm_actions       = var.sns_topic_arn != null ? [var.sns_topic_arn] : []

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "database_free_storage" {
  count = var.create_performance_alarms ? 1 : 0

  alarm_name          = "${var.tags["Environment"]}-${var.identifier}-free-storage-space"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.free_storage_alarm_threshold
  alarm_description   = "This metric monitors free storage space"
  alarm_actions       = var.sns_topic_arn != null ? [var.sns_topic_arn] : []

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = var.tags
}

# Automated backup verification
resource "aws_cloudwatch_metric_alarm" "backup_retention" {
  count = var.create_performance_alarms && var.backup_retention_period > 0 ? 1 : 0

  alarm_name          = "${var.tags["Environment"]}-${var.identifier}-backup-age"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "BackupRetentionPeriodStorageUsed"
  namespace           = "AWS/RDS"
  period              = "86400" # 24 hours
  statistic           = "Average"
  threshold           = var.backup_retention_period * 1024 * 1024 * 1024 # Convert days to bytes approximation
  alarm_description   = "This metric monitors backup retention storage usage"
  alarm_actions       = var.sns_topic_arn != null ? [var.sns_topic_arn] : []

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = var.tags
}





