# components/terraform/rds/main.tf
// ... 498 more lines (total: 499)
data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  name = "${var.tags["Environment"]}-${var.identifier}"

  # Confused-deputy scope for the enhanced-monitoring trust and the rotation
  # topic policy.
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  # Enhanced Monitoring: the instances that use the role, the primary and the
  # read replica (USER_Monitoring.OS.Enabling.html#USER_Monitoring.OS.confused-deputy).
  # RDS stores identifiers lowercase, and the source ARN carries the stored
  # form, so lower() keeps the match should an uppercase name ever reach
  # here. Today it cannot: the provider rejects uppercase in the subnet and
  # parameter group names built from the same Environment/identifier at plan.
  monitoring_source_arns = concat(
    ["arn:${local.partition}:rds:${var.region}:${local.account_id}:db:${lower(local.name)}"],
    var.create_read_replica ? ["arn:${local.partition}:rds:${var.region}:${local.account_id}:db:${lower(local.name)}-read-replica"] : [],
  )

  # family and port follow the engine unless set explicitly. AWS families:
  # postgres<major> from 10 on (postgres14, postgres16), postgres9.6 before;
  # mysql<major>.<minor> (mysql8.0, mysql8.4); mariadb<major>.<minor>
  # (mariadb10.11). var.family's validation rejects a family of another engine.
  version_parts  = split(".", var.engine_version)
  major_minor    = join(".", slice(local.version_parts, 0, min(2, length(local.version_parts))))
  postgres_major = tonumber(local.version_parts[0]) >= 10 ? local.version_parts[0] : local.major_minor
  derived_family = var.engine == "postgres" ? "postgres${local.postgres_major}" : "${var.engine}${local.major_minor}"
  family         = coalesce(var.family, local.derived_family)
  port           = coalesce(var.port, var.engine == "postgres" ? 5432 : 3306)

  # Engine-family defaults. var.parameters is merged after them, so a caller
  # entry with the same name wins (Cloud Posse's rds component also treats its
  # db_parameter list as caller-owned). Static parameters carry
  # apply_method = "pending-reboot": AWS rejects "immediate" for them.
  postgres_default_parameters = [
    { name = "shared_preload_libraries", value = "pg_stat_statements", apply_method = "pending-reboot" },
    # ddl, not all: "all" logs every statement verbatim, including any that
    # carries a secret (ALTER ROLE ... PASSWORD '...'), at high log volume.
    { name = "log_statement", value = "ddl", apply_method = "immediate" },
    { name = "log_min_duration_statement", value = "1000", apply_method = "immediate" }, # queries slower than 1s
    { name = "max_connections", value = tostring(var.max_connections), apply_method = "pending-reboot" },
    { name = "work_mem", value = "${var.work_mem_mb}MB", apply_method = "immediate" },
    { name = "maintenance_work_mem", value = "${var.maintenance_work_mem_mb}MB", apply_method = "immediate" },
    { name = "effective_cache_size", value = "${var.effective_cache_size_mb}MB", apply_method = "immediate" },
    { name = "random_page_cost", value = tostring(var.random_page_cost), apply_method = "immediate" },
    { name = "checkpoint_completion_target", value = tostring(var.checkpoint_completion_target), apply_method = "immediate" },
    # Every client connection must use TLS. Turn it off only knowingly, with an
    # explicit { name = "rds.force_ssl", value = "0" } in var.parameters.
    # pending-reboot: a new instance boots with it; an existing one picks it
    # up at its next reboot instead of dropping plaintext sessions mid-apply.
    { name = "rds.force_ssl", value = "1", apply_method = "pending-reboot" },
  ]

  # MySQL/MariaDB. The query cache was removed in MySQL 8.0 (the default
  # engine_version), so query_cache_* would fail CreateDBParameterGroup.
  mysql_default_parameters = [
    { name = "innodb_buffer_pool_size", value = "{DBInstanceClassMemory*3/4}", apply_method = "pending-reboot" },
    { name = "max_connections", value = tostring(var.max_connections), apply_method = "immediate" },
    { name = "innodb_log_file_size", value = "268435456", apply_method = "pending-reboot" }, # 256MB
    { name = "slow_query_log", value = "1", apply_method = "immediate" },
    { name = "long_query_time", value = "1", apply_method = "immediate" },
    # Every client connection must use TLS; turn it off only knowingly, with an
    # explicit { name = "require_secure_transport", value = "OFF" }. MariaDB has
    # it from 10.5 only (var.engine_version validation); pending-reboot as above.
    { name = "require_secure_transport", value = "ON", apply_method = "pending-reboot" },
  ]

  default_parameters = var.engine == "postgres" ? tolist(local.postgres_default_parameters) : tolist(local.mysql_default_parameters)

  # Defaults first, then the caller's list; the last entry per name wins, so a
  # caller overrides a default and a repeated caller entry is deduped.
  parameters_by_name = { for p in concat(local.default_parameters, var.parameters) : p.name => p... }
  db_parameters      = { for name, ps in local.parameters_by_name : name => ps[length(ps) - 1] }

  monitoring_role_arn = var.monitoring_interval > 0 ? (var.create_monitoring_role ? aws_iam_role.monitoring[0].arn : var.monitoring_role_arn) : null

  # Stable across plans, like Cloud Posse's terraform-aws-rds
  # (final_snapshot_identifier, else module.final_snapshot_label.id). The old
  # timestamp() suffix changed on every plan: a perpetual diff.
  final_snapshot_identifier = var.final_snapshot_identifier != "" ? var.final_snapshot_identifier : "${local.name}-final-snapshot"
}

resource "aws_db_subnet_group" "main" {
  name        = "${var.tags["Environment"]}-${var.identifier}-subnet-group"
  description = "Subnet group for ${var.identifier} RDS instance"
  subnet_ids  = var.subnet_ids

  tags = { Name = "${var.tags["Environment"]}-${var.identifier}-subnet-group" }
}

# Enhanced security group with detailed rules
#trivy:ignore:AWS-0104 Egress is unrestricted by policy (owner decision): the 443 egress reaches AWS APIs; ingress admits only allowed_security_groups or custom_ingress_rules CIDRs, never a /0
resource "aws_security_group" "rds" {
  name        = "${var.tags["Environment"]}-${var.identifier}-sg"
  description = "Security group for ${var.identifier} RDS instance"
  vpc_id      = var.vpc_id

  # Main database access from application security groups
  ingress {
    description     = "Database access from allowed security groups"
    from_port       = local.port
    to_port         = local.port
    protocol        = "tcp"
    security_groups = var.allowed_security_groups
  }

  # RDS Proxy access (if enabled)
  dynamic "ingress" {
    for_each = var.enable_rds_proxy ? [1] : []
    content {
      description = "RDS Proxy access"
      from_port   = local.port
      to_port     = local.port
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

  tags = { Name = "${var.tags["Environment"]}-${var.identifier}-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

# Security group for RDS Proxy (if enabled)
resource "aws_security_group" "rds_proxy" {
  #checkov:skip=CKV2_AWS_5:Attached to the proxy (aws_db_proxy vpc_security_group_ids); checkov's graph does not follow the count index in aws_security_group.rds_proxy[0].id
  count = var.enable_rds_proxy ? 1 : 0

  name        = "${var.tags["Environment"]}-${var.identifier}-proxy-sg"
  description = "Security group for ${var.identifier} RDS Proxy"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Database proxy access from applications"
    from_port       = local.port
    to_port         = local.port
    protocol        = "tcp"
    security_groups = var.allowed_security_groups
  }

  egress {
    description     = "Database access to RDS instance"
    from_port       = local.port
    to_port         = local.port
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

  tags = { Name = "${var.tags["Environment"]}-${var.identifier}-proxy-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

# Enhanced parameter group with performance optimizations
resource "aws_db_parameter_group" "main" {
  name   = "${var.tags["Environment"]}-${var.identifier}-pg"
  family = local.family

  # Engine defaults overlaid by var.parameters (the caller wins); see locals
  dynamic "parameter" {
    for_each = local.db_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = { Name = "${var.tags["Environment"]}-${var.identifier}-pg" }
}

# Connection pooling with RDS Proxy
resource "aws_db_proxy" "main" {
  count = var.enable_rds_proxy ? 1 : 0

  name          = "${var.tags["Environment"]}-${var.identifier}-proxy"
  engine_family = var.engine == "postgres" ? "POSTGRESQL" : "MYSQL"
  auth {
    auth_scheme = "SECRETS"
    secret_arn  = aws_db_instance.main.master_user_secret[0].secret_arn
  }
  role_arn               = aws_iam_role.rds_proxy[0].arn
  vpc_subnet_ids         = var.subnet_ids
  vpc_security_group_ids = [aws_security_group.rds_proxy[0].id]
  require_tls            = var.proxy_require_tls
  idle_client_timeout    = var.proxy_idle_client_timeout

  tags = { Name = "${var.tags["Environment"]}-${var.identifier}-proxy" }

  depends_on = [
    aws_iam_role_policy_attachment.rds_proxy
  ]
}

# Connection pool settings live on the proxy's default target group
resource "aws_db_proxy_default_target_group" "main" {
  count = var.enable_rds_proxy ? 1 : 0

  db_proxy_name = aws_db_proxy.main[0].name

  connection_pool_config {
    max_connections_percent      = var.proxy_max_connections_percent
    max_idle_connections_percent = var.proxy_max_idle_connections_percent
  }
}

resource "aws_db_proxy_target" "main" {
  count = var.enable_rds_proxy ? 1 : 0

  db_proxy_name          = aws_db_proxy.main[0].name
  target_group_name      = aws_db_proxy_default_target_group.main[0].name
  db_instance_identifier = aws_db_instance.main.identifier
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
        # No aws:SourceAccount/SourceArn condition, deliberately: AWS
        # documents this trust exactly as plain rds.amazonaws.com +
        # sts:AssumeRole (rds-proxy-iam-setup.html) and does not say the
        # proxy's AssumeRole carries those keys. A condition it does not
        # satisfy would leave the proxy unable to read its secret, a
        # runtime-only failure.
      }
    ]
  })

  tags = { Name = "${var.tags["Environment"]}-${var.identifier}-rds-proxy-role" }
}

resource "aws_iam_policy" "rds_proxy" {
  count = var.enable_rds_proxy ? 1 : 0

  name        = "${var.tags["Environment"]}-${var.identifier}-rds-proxy-policy"
  description = "Policy for RDS Proxy to access Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_db_instance.main.master_user_secret[0].secret_arn
      }
      ], var.master_user_secret_kms_key_id == null ? [] : [
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = var.master_user_secret_kms_key_id
      }
    ])
  })
}

resource "aws_iam_role_policy_attachment" "rds_proxy" {
  count = var.enable_rds_proxy ? 1 : 0

  role       = aws_iam_role.rds_proxy[0].name
  policy_arn = aws_iam_policy.rds_proxy[0].arn
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
        # AWS's documented Enhanced Monitoring trust: this account, and only
        # the instances that use the role.
        Condition = {
          StringEquals = { "aws:SourceAccount" = local.account_id }
          ArnLike      = { "aws:SourceArn" = local.monitoring_source_arns }
        }
      }
    ]
  })

  tags = { Name = "${var.tags["Environment"]}-${var.identifier}-monitoring-role" }
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  count = var.monitoring_interval > 0 && var.create_monitoring_role ? 1 : 0

  role       = aws_iam_role.monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Read replica for performance scaling. Same-region replica: storage
# encryption, engine and credentials come from the source; everything that
# does not is set to the primary's value so the replica is reachable from the
# same app security groups and protected the same way.
resource "aws_db_instance" "read_replica" {
  #checkov:skip=CKV2_AWS_69:False positive, aws_db_parameter_group.main sets rds.force_ssl = 1 / require_secure_transport = ON through a dynamic block Checkov cannot evaluate (tests/rds.tftest.hcl asserts it)
  count = var.create_read_replica ? 1 : 0

  identifier = "${local.name}-read-replica"
  # The source DB instance identifier: since AWS provider v5, .id is the
  # db-XXXX resource ID, which RDS does not accept here.
  replicate_source_db = aws_db_instance.main.identifier
  instance_class      = var.read_replica_instance_class != null ? var.read_replica_instance_class : var.instance_class
  # Storage autoscaling and the CA certificate are per instance, not
  # inherited from the source.
  max_allocated_storage = var.max_allocated_storage
  ca_cert_identifier    = var.ca_cert_identifier

  # Without these the replica lands in the VPC's default security group and
  # the default parameter group (no TLS enforcement, no logging defaults).
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.main.name
  publicly_accessible    = var.publicly_accessible
  port                   = local.port

  deletion_protection                   = aws_db_instance.main.deletion_protection
  iam_database_authentication_enabled   = var.iam_database_authentication_enabled
  auto_minor_version_upgrade            = var.auto_minor_version_upgrade
  maintenance_window                    = var.maintenance_window
  copy_tags_to_snapshot                 = var.copy_tags_to_snapshot
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = local.monitoring_role_arn
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null
  performance_insights_kms_key_id       = var.performance_insights_enabled ? var.performance_insights_kms_key_id : null
  enabled_cloudwatch_logs_exports       = var.enabled_cloudwatch_logs_exports
  # A replica has no final snapshot of its own; the primary's covers the data.
  skip_final_snapshot = true

  depends_on = [
    aws_iam_role_policy_attachment.monitoring
  ]

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-${var.identifier}-read-replica"
      Role = "read-replica"
    }
  )
}

resource "aws_db_instance" "main" {
  #checkov:skip=CKV_AWS_129:Log exports are an input (enabled_cloudwatch_logs_exports, [] by default as in Cloud Posse's terraform-aws-rds); prod and the web-application template set them
  identifier            = "${var.tags["Environment"]}-${var.identifier}"
  engine                = var.engine
  engine_version        = var.engine_version
  instance_class        = var.instance_class
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  ca_cert_identifier    = var.ca_cert_identifier
  storage_type          = var.storage_type
  storage_encrypted     = var.storage_encrypted
  kms_key_id            = var.kms_key_id
  username              = var.username
  # RDS generates the password and stores it in a Secrets Manager secret it manages
  manage_master_user_password           = true
  master_user_secret_kms_key_id         = var.master_user_secret_kms_key_id
  port                                  = local.port
  db_name                               = var.db_name
  parameter_group_name                  = aws_db_parameter_group.main.name
  db_subnet_group_name                  = aws_db_subnet_group.main.name
  vpc_security_group_ids                = [aws_security_group.rds.id]
  availability_zone                     = var.availability_zone
  multi_az                              = var.multi_az
  publicly_accessible                   = var.publicly_accessible
  allow_major_version_upgrade           = var.allow_major_version_upgrade
  auto_minor_version_upgrade            = var.auto_minor_version_upgrade
  backup_retention_period               = var.backup_retention_period
  backup_window                         = var.backup_window
  maintenance_window                    = var.maintenance_window
  skip_final_snapshot                   = var.skip_final_snapshot
  final_snapshot_identifier             = var.skip_final_snapshot ? null : local.final_snapshot_identifier
  copy_tags_to_snapshot                 = var.copy_tags_to_snapshot
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = local.monitoring_role_arn
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_retention_period
  performance_insights_kms_key_id       = var.performance_insights_enabled ? var.performance_insights_kms_key_id : null
  iam_database_authentication_enabled   = var.iam_database_authentication_enabled
  # prevent_destroy only accepts literals, so var.prevent_destroy maps to deletion protection
  deletion_protection = var.deletion_protection || var.prevent_destroy

  # Storage performance optimizations
  iops               = var.storage_type == "io1" || var.storage_type == "gp3" ? var.iops : null
  storage_throughput = var.storage_type == "gp3" ? var.storage_throughput : null

  # Enhanced monitoring and logging
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports


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
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }
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
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }
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
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }
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
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }
}
