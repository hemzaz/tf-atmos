#------------------------------------------------------------------------------
# Cluster Outputs
#------------------------------------------------------------------------------

output "cluster_id" {
  description = <<-EOT
    The RDS Cluster Identifier.
    Use this to reference the cluster in other resources.
  EOT
  value       = aws_rds_cluster.this.id
}

output "cluster_arn" {
  description = <<-EOT
    The ARN of the RDS cluster.
    Use this for IAM policies and resource tagging.
  EOT
  value       = aws_rds_cluster.this.arn
}

output "cluster_identifier" {
  description = <<-EOT
    The cluster identifier (same as cluster_id).
  EOT
  value       = aws_rds_cluster.this.cluster_identifier
}

output "cluster_resource_id" {
  description = <<-EOT
    The RDS Cluster Resource ID.
    Use this for Performance Insights and CloudWatch metrics.
  EOT
  value       = aws_rds_cluster.this.cluster_resource_id
}

#------------------------------------------------------------------------------
# Endpoint Outputs
#------------------------------------------------------------------------------

output "cluster_endpoint" {
  description = <<-EOT
    The cluster endpoint (writer endpoint).
    Use this for read-write database connections.
    Example: myapp-prod-aurora.cluster-abc123.us-east-1.rds.amazonaws.com
  EOT
  value       = aws_rds_cluster.this.endpoint
}

output "cluster_reader_endpoint" {
  description = <<-EOT
    The cluster reader endpoint.
    Use this for read-only database connections. Automatically load-balances across read replicas.
    Example: myapp-prod-aurora.cluster-ro-abc123.us-east-1.rds.amazonaws.com
  EOT
  value       = aws_rds_cluster.this.reader_endpoint
}

output "cluster_port" {
  description = <<-EOT
    The port on which the DB accepts connections.
    PostgreSQL: 5432, MySQL: 3306
  EOT
  value       = aws_rds_cluster.this.port
}

output "cluster_database_name" {
  description = <<-EOT
    The name of the default database.
    This is the initial database created with the cluster.
  EOT
  value       = aws_rds_cluster.this.database_name
}

output "cluster_master_username" {
  description = <<-EOT
    The master username for the database.
  EOT
  value       = aws_rds_cluster.this.master_username
  sensitive   = true
}

#------------------------------------------------------------------------------
# Instance Outputs
#------------------------------------------------------------------------------

output "cluster_instances" {
  description = <<-EOT
    List of all cluster instance identifiers.
    Use these to monitor individual instances or perform maintenance.
  EOT
  value       = aws_rds_cluster_instance.this[*].identifier
}

output "cluster_instance_endpoints" {
  description = <<-EOT
    List of all cluster instance endpoints.
    Use these for direct connections to specific instances.
  EOT
  value       = aws_rds_cluster_instance.this[*].endpoint
}

output "cluster_instance_ids" {
  description = <<-EOT
    List of all cluster instance IDs.
  EOT
  value       = aws_rds_cluster_instance.this[*].id
}

output "writer_instance_endpoint" {
  description = <<-EOT
    The endpoint of the writer instance (first instance).
  EOT
  value       = length(aws_rds_cluster_instance.this) > 0 ? aws_rds_cluster_instance.this[0].endpoint : null
}

output "reader_instance_endpoints" {
  description = <<-EOT
    List of reader instance endpoints (all instances except first).
  EOT
  value       = length(aws_rds_cluster_instance.this) > 1 ? slice(aws_rds_cluster_instance.this[*].endpoint, 1, length(aws_rds_cluster_instance.this)) : []
}

#------------------------------------------------------------------------------
# Security Outputs
#------------------------------------------------------------------------------

output "security_group_id" {
  description = <<-EOT
    The ID of the security group attached to the cluster.
    Use this to add additional ingress/egress rules.
  EOT
  value       = local.create_sg ? aws_security_group.aurora[0].id : null
}

output "security_group_arn" {
  description = <<-EOT
    The ARN of the security group attached to the cluster.
  EOT
  value       = local.create_sg ? aws_security_group.aurora[0].arn : null
}

output "kms_key_id" {
  description = <<-EOT
    The KMS key ID used for encryption.
  EOT
  value       = aws_rds_cluster.this.kms_key_id
}

#------------------------------------------------------------------------------
# Secrets Manager Outputs
#------------------------------------------------------------------------------

output "master_password_secret_arn" {
  description = <<-EOT
    The ARN of the Secrets Manager secret containing the master password.
    Use this to grant applications access to database credentials.
  EOT
  value       = local.create_secret ? aws_secretsmanager_secret.master_password[0].arn : var.master_password_secret_arn
  sensitive   = true
}

output "master_password_secret_id" {
  description = <<-EOT
    The ID of the Secrets Manager secret containing the master password.
  EOT
  value       = local.create_secret ? aws_secretsmanager_secret.master_password[0].id : null
  sensitive   = true
}

output "master_password_secret_name" {
  description = <<-EOT
    The name of the Secrets Manager secret containing the master password.
  EOT
  value       = local.create_secret ? aws_secretsmanager_secret.master_password[0].name : null
  sensitive   = true
}

#------------------------------------------------------------------------------
# Configuration Outputs
#------------------------------------------------------------------------------

output "cluster_parameter_group_name" {
  description = <<-EOT
    The name of the cluster parameter group.
  EOT
  value       = aws_rds_cluster.this.db_cluster_parameter_group_name
}

output "db_parameter_group_name" {
  description = <<-EOT
    The name of the DB instance parameter group.
  EOT
  value       = var.db_parameter_group_name != null ? var.db_parameter_group_name : (length(aws_db_parameter_group.this) > 0 ? aws_db_parameter_group.this[0].name : null)
}

output "db_subnet_group_name" {
  description = <<-EOT
    The name of the DB subnet group.
  EOT
  value       = aws_db_subnet_group.this.name
}

output "db_subnet_group_arn" {
  description = <<-EOT
    The ARN of the DB subnet group.
  EOT
  value       = aws_db_subnet_group.this.arn
}

#------------------------------------------------------------------------------
# Monitoring Outputs
#------------------------------------------------------------------------------

output "enhanced_monitoring_role_arn" {
  description = <<-EOT
    The ARN of the IAM role used for Enhanced Monitoring.
  EOT
  value       = var.enable_enhanced_monitoring && var.monitoring_role_arn == null ? aws_iam_role.enhanced_monitoring[0].arn : var.monitoring_role_arn
}

output "performance_insights_enabled" {
  description = <<-EOT
    Whether Performance Insights is enabled.
  EOT
  value       = var.enable_performance_insights
}

output "cloudwatch_log_groups" {
  description = <<-EOT
    List of CloudWatch log groups for database logs.
    Use these for log analysis and alerting.
  EOT
  value       = [for log_type in local.log_exports : "/aws/rds/cluster/${aws_rds_cluster.this.cluster_identifier}/${log_type}"]
}

#------------------------------------------------------------------------------
# Auto Scaling Outputs
#------------------------------------------------------------------------------

output "autoscaling_enabled" {
  description = <<-EOT
    Whether auto-scaling is enabled for read replicas.
  EOT
  value       = var.enable_autoscaling && var.instance_count > 1
}

output "autoscaling_target_id" {
  description = <<-EOT
    The resource ID of the auto-scaling target.
  EOT
  value       = var.enable_autoscaling && var.instance_count > 1 ? aws_appautoscaling_target.read_replica[0].id : null
}

output "autoscaling_min_capacity" {
  description = <<-EOT
    The minimum number of read replicas for auto-scaling.
  EOT
  value       = var.autoscaling_min_capacity
}

output "autoscaling_max_capacity" {
  description = <<-EOT
    The maximum number of read replicas for auto-scaling.
  EOT
  value       = var.autoscaling_max_capacity
}

#------------------------------------------------------------------------------
# Global Cluster Outputs
#------------------------------------------------------------------------------

output "global_cluster_id" {
  description = <<-EOT
    The ID of the global cluster (if enabled).
  EOT
  value       = var.enable_global_cluster && var.is_primary_cluster ? aws_rds_global_cluster.this[0].id : null
}

output "global_cluster_arn" {
  description = <<-EOT
    The ARN of the global cluster (if enabled).
  EOT
  value       = var.enable_global_cluster && var.is_primary_cluster ? aws_rds_global_cluster.this[0].arn : null
}

output "global_cluster_resource_id" {
  description = <<-EOT
    The resource ID of the global cluster (if enabled).
  EOT
  value       = var.enable_global_cluster && var.is_primary_cluster ? aws_rds_global_cluster.this[0].global_cluster_resource_id : null
}

#------------------------------------------------------------------------------
# Connection String Outputs
#------------------------------------------------------------------------------

output "connection_string_writer" {
  description = <<-EOT
    PostgreSQL connection string for writer endpoint.
    Format: postgresql://username:password@host:port/database
    Note: Password is masked. Retrieve from Secrets Manager.
  EOT
  value = local.is_postgresql ? format(
    "postgresql://%s:****@%s:%d/%s",
    aws_rds_cluster.this.master_username,
    aws_rds_cluster.this.endpoint,
    aws_rds_cluster.this.port,
    aws_rds_cluster.this.database_name != null ? aws_rds_cluster.this.database_name : "postgres"
  ) : format(
    "mysql://%s:****@%s:%d/%s",
    aws_rds_cluster.this.master_username,
    aws_rds_cluster.this.endpoint,
    aws_rds_cluster.this.port,
    aws_rds_cluster.this.database_name != null ? aws_rds_cluster.this.database_name : "mysql"
  )
}

output "connection_string_reader" {
  description = <<-EOT
    PostgreSQL connection string for reader endpoint.
    Format: postgresql://username:password@host:port/database
    Note: Password is masked. Retrieve from Secrets Manager.
  EOT
  value = local.is_postgresql ? format(
    "postgresql://%s:****@%s:%d/%s",
    aws_rds_cluster.this.master_username,
    aws_rds_cluster.this.reader_endpoint,
    aws_rds_cluster.this.port,
    aws_rds_cluster.this.database_name != null ? aws_rds_cluster.this.database_name : "postgres"
  ) : format(
    "mysql://%s:****@%s:%d/%s",
    aws_rds_cluster.this.master_username,
    aws_rds_cluster.this.reader_endpoint,
    aws_rds_cluster.this.port,
    aws_rds_cluster.this.database_name != null ? aws_rds_cluster.this.database_name : "mysql"
  )
}

#------------------------------------------------------------------------------
# Cost Estimation Outputs
#------------------------------------------------------------------------------

output "estimated_monthly_cost_usd" {
  description = <<-EOT
    Estimated monthly cost in USD (approximate).
    Includes: instances, storage, backups, and data transfer.
    Excludes: Performance Insights (beyond free tier), Enhanced Monitoring, cross-region replication.
  EOT
  value = format(
    "Instance: $%s, Storage: $40-60, Backups: $10-30, Total: ~$%s-$%s",
    var.enable_serverlessv2 ? format("%.0f ACU-hours", var.serverlessv2_max_capacity * 730 * 0.12) : format("%.0f", var.instance_count * 220),
    var.enable_serverlessv2 ? format("%.0f", var.serverlessv2_max_capacity * 730 * 0.12 + 50) : format("%.0f", var.instance_count * 220 + 50),
    var.enable_serverlessv2 ? format("%.0f", var.serverlessv2_max_capacity * 730 * 0.12 + 90) : format("%.0f", var.instance_count * 220 + 90)
  )
}

#------------------------------------------------------------------------------
# Metadata Outputs
#------------------------------------------------------------------------------

output "engine" {
  description = <<-EOT
    The database engine type.
  EOT
  value       = aws_rds_cluster.this.engine
}

output "engine_version" {
  description = <<-EOT
    The database engine version.
  EOT
  value       = aws_rds_cluster.this.engine_version
}

output "engine_mode" {
  description = <<-EOT
    The database engine mode (provisioned or serverless).
  EOT
  value       = aws_rds_cluster.this.engine_mode
}

output "availability_zones" {
  description = <<-EOT
    List of availability zones where cluster instances are deployed.
  EOT
  value       = aws_rds_cluster_instance.this[*].availability_zone
}

output "backup_retention_period" {
  description = <<-EOT
    Number of days backups are retained.
  EOT
  value       = aws_rds_cluster.this.backup_retention_period
}

output "preferred_backup_window" {
  description = <<-EOT
    Daily time range for automated backups.
  EOT
  value       = aws_rds_cluster.this.preferred_backup_window
}

output "preferred_maintenance_window" {
  description = <<-EOT
    Weekly time range for maintenance.
  EOT
  value       = aws_rds_cluster.this.preferred_maintenance_window
}
