# Common outputs module - Standardized output patterns across all components
# This module provides consistent output formats and naming conventions

# Core identification outputs
output "name_prefix" {
  description = "Standardized name prefix used for resource naming"
  value       = local.name_prefix
}

output "component_name" {
  description = "Full component name including prefix"
  value       = local.component_name
}

output "dns_name" {
  description = "DNS-safe name (lowercase, no underscores)"
  value       = local.dns_name
}

# Environment and configuration outputs
output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "stage" {
  description = "Stage/instance identifier"
  value       = var.stage
}

output "region" {
  description = "AWS region"
  value       = data.aws_region.current.name
}

output "availability_zones" {
  description = "Available AZs in the region"
  value       = data.aws_availability_zones.available.names
}

# Account and identity information
output "account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "partition" {
  description = "AWS partition (aws, aws-cn, aws-us-gov)"
  value       = data.aws_partition.current.partition
}

# Common tags output
output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Environment-specific configuration
output "environment_config" {
  description = "Environment-specific configuration settings"
  value       = local.current_env_config
  sensitive   = false
}

# Security group rule templates
output "common_security_group_rules" {
  description = "Common security group rule templates"
  value       = local.common_sg_rules
}

# Standard port mappings
output "standard_ports" {
  description = "Standard port mappings for common services"
  value       = local.standard_ports
}

# KMS key policy statements
output "kms_key_policy_statements" {
  description = "Common KMS key policy statements"
  value       = local.kms_key_policy_statements
}

# Computed values for common use cases
output "resource_name_max_length" {
  description = "Maximum length for resource names (AWS limit)"
  value       = 64
}

output "is_production" {
  description = "Whether this is a production environment"
  value       = var.environment == "prod"
}

output "is_development" {
  description = "Whether this is a development environment"
  value       = var.environment == "dev"
}

output "requires_high_availability" {
  description = "Whether this environment requires high availability"
  value       = var.environment == "prod" || var.enable_multi_az
}

# Common ARN patterns (for reference)
output "arn_patterns" {
  description = "Common ARN patterns for resource construction"
  value = {
    s3_bucket   = "arn:${data.aws_partition.current.partition}:s3:::${local.name_prefix}-*"
    iam_role    = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.name_prefix}-*"
    kms_key     = "arn:${data.aws_partition.current.partition}:kms:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:key/*"
    lambda      = "arn:${data.aws_partition.current.partition}:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${local.name_prefix}-*"
    rds         = "arn:${data.aws_partition.current.partition}:rds:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:db:${local.name_prefix}-*"
    vpc         = "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:vpc/*"
    subnet      = "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:subnet/*"
    security_group = "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:security-group/*"
  }
}

# Time-based outputs
output "timestamp" {
  description = "Current timestamp (for reference)"
  value       = timestamp()
}

output "deployment_date" {
  description = "Deployment date in YYYY-MM-DD format"
  value       = formatdate("YYYY-MM-DD", timestamp())
}

# Validation helpers
output "validation_helpers" {
  description = "Validation helper patterns for common use cases"
  value = {
    # Email validation pattern
    email_regex = "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"
    
    # AWS resource name patterns
    s3_bucket_name_regex = "^[a-z0-9][a-z0-9.-]*[a-z0-9]$"
    iam_name_regex       = "^[a-zA-Z0-9+=,.@_-]+$"
    
    # Network validation
    cidr_regex = "^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$"
    
    # Version patterns
    semantic_version_regex = "^(0|[1-9]\\d*)\\.(0|[1-9]\\d*)\\.(0|[1-9]\\d*)(?:-((?:0|[1-9]\\d*|\\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\\.(?:0|[1-9]\\d*|\\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\\+([0-9a-zA-Z-]+(?:\\.[0-9a-zA-Z-]+)*))?$"
  }
}

# Common lifecycle rules for resources
output "lifecycle_rules" {
  description = "Common lifecycle rules for Terraform resources"
  value = {
    # Prevent accidental destruction of critical resources
    prevent_destroy_production = var.environment == "prod"
    
    # Create before destroy for zero-downtime updates
    create_before_destroy = true
    
    # Common ignore changes patterns
    ignore_changes = {
      # Ignore timestamp-based tags that change on every run
      tags_timestamps = ["tags.LastModified", "tags.CreatedDate"]
      
      # Ignore auto-scaling related changes
      auto_scaling = ["desired_capacity", "target_group_arns"]
      
      # Ignore password and secret changes (managed externally)
      secrets = ["password", "master_password", "secret_string"]
    }
  }
}

# Cost optimization helpers
output "cost_optimization_settings" {
  description = "Cost optimization settings based on environment"
  value = {
    enable_spot_instances     = var.environment != "prod"
    enable_scheduled_scaling  = var.environment != "prod"
    enable_instance_scheduler = var.environment != "prod"
    backup_retention_days     = var.environment == "prod" ? 30 : 7
    log_retention_days       = var.environment == "prod" ? 90 : 30
    enable_detailed_monitoring = var.environment == "prod"
  }
}

# Security baseline outputs
output "security_baseline" {
  description = "Security baseline settings"
  value = {
    require_ssl                = true
    enable_encryption_at_rest  = var.enable_encryption_at_rest
    enable_encryption_in_transit = var.enable_encryption_in_transit
    minimum_tls_version       = "1.2"
    enable_access_logging     = true
    enable_cloudtrail         = var.environment == "prod"
    enable_config_rules       = var.environment == "prod"
    enable_guardduty          = var.environment == "prod"
    
    # Default security group rules (restrictive)
    default_ingress_rules = []
    default_egress_rules = [
      {
        from_port   = 0
        to_port     = 65535
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
        description = "All outbound traffic"
      }
    ]
  }
}

# Monitoring and alerting configuration
output "monitoring_config" {
  description = "Monitoring and alerting configuration"
  value = {
    enable_detailed_monitoring = local.current_env_config.enable_monitoring
    cloudwatch_retention_days  = var.log_retention_days
    enable_performance_insights = var.performance_insights_enabled
    
    # Common CloudWatch metrics
    default_metrics = [
      "CPUUtilization",
      "NetworkIn",
      "NetworkOut",
      "StatusCheckFailed",
      "StatusCheckFailed_Instance",
      "StatusCheckFailed_System"
    ]
    
    # Alert thresholds by environment
    alert_thresholds = {
      cpu_high_threshold    = var.environment == "prod" ? 80 : 90
      memory_high_threshold = var.environment == "prod" ? 80 : 90
      disk_high_threshold   = var.environment == "prod" ? 85 : 95
      error_rate_threshold  = var.environment == "prod" ? 1 : 5
    }
  }
}

# Common resource configurations
output "resource_defaults" {
  description = "Default configurations for common AWS resources"
  value = {
    # EC2 defaults
    ec2 = {
      instance_type                        = var.environment == "prod" ? "t3.small" : "t3.micro"
      monitoring                          = local.current_env_config.enable_monitoring
      associate_public_ip_address         = false
      disable_api_termination             = var.environment == "prod"
      instance_initiated_shutdown_behavior = "stop"
      
      # Default user data for common setup
      user_data_template = base64encode(templatefile("${path.module}/templates/user-data.sh.tpl", {
        environment = var.environment
        region      = data.aws_region.current.name
      }))
    }
    
    # RDS defaults
    rds = {
      engine_version                = "8.0"
      instance_class               = "db.t3.micro"
      allocated_storage            = 20
      max_allocated_storage        = 100
      storage_encrypted            = local.current_env_config.storage_encrypted
      multi_az                     = local.current_env_config.enable_multi_az
      backup_retention_period      = local.current_env_config.enable_backups ? var.backup_retention_days : 0
      backup_window               = local.current_env_config.backup_window
      maintenance_window          = local.current_env_config.maintenance_window
      auto_minor_version_upgrade  = var.auto_minor_version_upgrade
      deletion_protection         = local.current_env_config.deletion_protection
      skip_final_snapshot         = var.environment != "prod"
      copy_tags_to_snapshot       = true
      enabled_cloudwatch_logs_exports = ["error", "general", "slow_query"]
      monitoring_interval         = local.current_env_config.enable_monitoring ? 60 : 0
      performance_insights_enabled = var.performance_insights_enabled
    }
    
    # S3 defaults
    s3 = {
      versioning_enabled          = true
      server_side_encryption_enabled = true
      public_access_block = {
        block_public_acls       = true
        block_public_policy     = true
        ignore_public_acls      = true
        restrict_public_buckets = true
      }
      lifecycle_rules = {
        transition_ia_days      = 30
        transition_glacier_days = 90
        expiration_days        = var.environment == "prod" ? 2557 : 365 # 7 years for prod, 1 year for dev
      }
    }
  }
}