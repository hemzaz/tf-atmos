# components/terraform/rds/main.tf
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

resource "aws_security_group" "rds" {
  name        = "${var.tags["Environment"]}-${var.identifier}-sg"
  description = "Security group for ${var.identifier} RDS instance"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = var.port
    to_port         = var.port
    protocol        = "tcp"
    security_groups = var.allowed_security_groups
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-${var.identifier}-sg"
    }
  )
}

resource "aws_db_parameter_group" "main" {
  name   = "${var.tags["Environment"]}-${var.identifier}-pg"
  family = var.family

  dynamic "parameter" {
    for_each = var.parameters
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
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({
    username = var.username
    password = random_password.password.result
    engine   = var.engine
    host     = aws_db_instance.main.address
    port     = var.port
    dbname   = var.db_name
  })
}

resource "aws_db_instance" "main" {
  identifier                  = "${var.tags["Environment"]}-${var.identifier}"
  engine                      = var.engine
  engine_version              = var.engine_version
  instance_class              = var.instance_class
  allocated_storage           = var.allocated_storage
  max_allocated_storage       = var.max_allocated_storage
  storage_type                = var.storage_type
  storage_encrypted           = var.storage_encrypted
  kms_key_id                  = var.kms_key_id
  username                    = var.username
  password                    = random_password.password.result
  port                        = var.port
  db_name                     = var.db_name
  parameter_group_name        = aws_db_parameter_group.main.name
  db_subnet_group_name        = aws_db_subnet_group.main.name
  vpc_security_group_ids      = [aws_security_group.rds.id]
  availability_zone           = var.availability_zone
  multi_az                    = var.multi_az
  publicly_accessible         = var.publicly_accessible
  allow_major_version_upgrade = var.allow_major_version_upgrade
  auto_minor_version_upgrade  = var.auto_minor_version_upgrade
  backup_retention_period     = var.backup_retention_period
  backup_window               = var.backup_window
  maintenance_window          = var.maintenance_window
  skip_final_snapshot         = var.skip_final_snapshot
  final_snapshot_identifier   = var.skip_final_snapshot ? null : "${var.tags["Environment"]}-${var.identifier}-final-snapshot"
  copy_tags_to_snapshot       = var.copy_tags_to_snapshot
  monitoring_interval         = var.monitoring_interval
  monitoring_role_arn         = var.monitoring_interval > 0 ? var.monitoring_role_arn : null
  performance_insights_enabled = var.performance_insights_enabled
  deletion_protection         = var.deletion_protection

  lifecycle {
    prevent_destroy = var.prevent_destroy
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-${var.identifier}"
    }
  )
}





