# Outputs for IDP Platform Infrastructure Component

# EKS Cluster Outputs
output "eks_cluster_id" {
  description = "EKS cluster ID"
  value       = module.eks_cluster.cluster_id
}

output "eks_cluster_arn" {
  description = "EKS cluster ARN"
  value       = module.eks_cluster.cluster_arn
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint URL"
  value       = module.eks_cluster.cluster_endpoint
  sensitive   = true
}

output "eks_cluster_certificate_authority_data" {
  description = "EKS cluster certificate authority data"
  value       = module.eks_cluster.cluster_certificate_authority_data
  sensitive   = true
}

output "eks_cluster_security_group_id" {
  description = "EKS cluster security group ID"
  value       = module.eks_cluster.cluster_security_group_id
}

output "eks_node_group_arns" {
  description = "EKS node group ARNs"
  value       = module.eks_cluster.node_group_arns
}

output "eks_oidc_provider_arn" {
  description = "EKS OIDC provider ARN for service account roles"
  value       = module.eks_cluster.oidc_provider_arn
}

# Database Outputs
output "database_instance_id" {
  description = "RDS instance ID"
  value       = module.idp_database.instance_id
}

output "database_instance_arn" {
  description = "RDS instance ARN"
  value       = module.idp_database.instance_arn
}

output "database_endpoint" {
  description = "RDS instance endpoint"
  value       = module.idp_database.endpoint
  sensitive   = true
}

output "database_port" {
  description = "RDS instance port"
  value       = module.idp_database.port
}

output "database_name" {
  description = "Database name"
  value       = module.idp_database.db_name
}

output "database_username" {
  description = "Database master username"
  value       = module.idp_database.username
  sensitive   = true
}

output "database_password" {
  description = "Database master password"
  value       = module.idp_database.password
  sensitive   = true
}

output "database_connection_string" {
  description = "Database connection string (without credentials)"
  value       = "postgresql://${module.idp_database.endpoint}:${module.idp_database.port}/${module.idp_database.db_name}"
  sensitive   = true
}

# Redis Outputs
output "redis_replication_group_id" {
  description = "ElastiCache Redis replication group ID"
  value       = aws_elasticache_replication_group.redis.replication_group_id
}

output "redis_primary_endpoint" {
  description = "ElastiCache Redis primary endpoint"
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
  sensitive   = true
}

output "redis_reader_endpoint" {
  description = "ElastiCache Redis reader endpoint"
  value       = aws_elasticache_replication_group.redis.reader_endpoint_address
  sensitive   = true
}

output "redis_configuration_endpoint" {
  description = "ElastiCache Redis configuration endpoint"
  value       = aws_elasticache_replication_group.redis.configuration_endpoint_address
  sensitive   = true
}

output "redis_port" {
  description = "ElastiCache Redis port"
  value       = aws_elasticache_replication_group.redis.port
}

output "redis_auth_token" {
  description = "ElastiCache Redis auth token"
  value       = random_password.redis_auth_token.result
  sensitive   = true
}

# Storage Outputs
output "s3_bucket_names" {
  description = "S3 bucket names by purpose"
  value = {
    for purpose in ["artifacts", "backups", "logs", "techdocs", "uploads"] :
    purpose => module.idp_storage[purpose].bucket_name
  }
}

output "s3_bucket_arns" {
  description = "S3 bucket ARNs by purpose"
  value = {
    for purpose in ["artifacts", "backups", "logs", "techdocs", "uploads"] :
    purpose => module.idp_storage[purpose].bucket_arn
  }
}

output "s3_bucket_domains" {
  description = "S3 bucket domain names"
  value = {
    for purpose in ["artifacts", "backups", "logs", "techdocs", "uploads"] :
    purpose => module.idp_storage[purpose].bucket_domain_name
  }
}

# Load Balancer Outputs
output "load_balancer_arn" {
  description = "Application Load Balancer ARN"
  value       = aws_lb.idp_platform.arn
}

output "load_balancer_dns_name" {
  description = "Application Load Balancer DNS name"
  value       = aws_lb.idp_platform.dns_name
}

output "load_balancer_zone_id" {
  description = "Application Load Balancer zone ID"
  value       = aws_lb.idp_platform.zone_id
}

output "load_balancer_security_group_id" {
  description = "Load balancer security group ID"
  value       = aws_security_group.alb.id
}

# DNS Outputs
output "hosted_zone_id" {
  description = "Route53 hosted zone ID"
  value       = aws_route53_zone.main.zone_id
}

output "hosted_zone_name" {
  description = "Route53 hosted zone name"
  value       = aws_route53_zone.main.name
}

output "hosted_zone_name_servers" {
  description = "Route53 hosted zone name servers"
  value       = aws_route53_zone.main.name_servers
}

# Certificate Outputs
output "certificate_arn" {
  description = "ACM certificate ARN"
  value       = module.acm_certificate.certificate_arn
}

output "certificate_domain_name" {
  description = "ACM certificate domain name"
  value       = module.acm_certificate.domain_name
}

output "certificate_subject_alternative_names" {
  description = "ACM certificate subject alternative names"
  value       = module.acm_certificate.subject_alternative_names
}

# Secrets Outputs
output "secrets_manager_secret_arn" {
  description = "Secrets Manager secret ARN"
  value       = aws_secretsmanager_secret.idp_config.arn
}

output "secrets_manager_secret_name" {
  description = "Secrets Manager secret name"
  value       = aws_secretsmanager_secret.idp_config.name
}

# Security Group Outputs
output "security_groups" {
  description = "Security group IDs and names"
  value = {
    database = {
      id   = aws_security_group.database.id
      name = aws_security_group.database.name
    }
    redis = {
      id   = aws_security_group.redis.id
      name = aws_security_group.redis.name
    }
    alb = {
      id   = aws_security_group.alb.id
      name = aws_security_group.alb.name
    }
  }
}

# Monitoring Outputs
output "sns_topic_arn" {
  description = "SNS topic ARN for alerts"
  value       = aws_sns_topic.alerts.arn
}

output "cloudwatch_log_groups" {
  description = "CloudWatch log group names"
  value = {
    redis_slow_log = aws_cloudwatch_log_group.redis_slow_log.name
  }
}

output "health_check_id" {
  description = "Route53 health check ID"
  value       = aws_route53_health_check.idp_platform.id
}

# Network Outputs
output "vpc_id" {
  description = "VPC ID"
  value       = data.aws_vpc.selected.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = data.aws_subnets.private.ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = data.aws_subnets.public.ids
}

# IAM Outputs
output "iam_roles" {
  description = "IAM role ARNs"
  value = {
    rds_enhanced_monitoring = aws_iam_role.rds_enhanced_monitoring.arn
  }
}

# Platform Configuration Output
output "platform_configuration" {
  description = "Complete platform configuration for Kubernetes deployment"
  value = {
    # Cluster configuration
    cluster = {
      name                  = module.eks_cluster.cluster_id
      endpoint              = module.eks_cluster.cluster_endpoint
      certificate_authority = module.eks_cluster.cluster_certificate_authority_data
      oidc_provider_arn     = module.eks_cluster.oidc_provider_arn
      security_group_id     = module.eks_cluster.cluster_security_group_id
    }

    # Database configuration
    database = {
      host     = module.idp_database.endpoint
      port     = module.idp_database.port
      name     = module.idp_database.db_name
      username = module.idp_database.username
    }

    # Redis configuration
    redis = {
      endpoint = aws_elasticache_replication_group.redis.configuration_endpoint_address
      port     = aws_elasticache_replication_group.redis.port
    }

    # Storage configuration
    storage = {
      for purpose in ["artifacts", "backups", "logs", "techdocs", "uploads"] :
      purpose => {
        bucket_name = module.idp_storage[purpose].bucket_name
        bucket_arn  = module.idp_storage[purpose].bucket_arn
      }
    }

    # DNS configuration
    dns = {
      zone_id      = aws_route53_zone.main.zone_id
      domain_name  = var.domain_name
      name_servers = aws_route53_zone.main.name_servers
    }

    # Certificate configuration
    certificate = {
      arn         = module.acm_certificate.certificate_arn
      domain_name = module.acm_certificate.domain_name
    }

    # Load balancer configuration
    load_balancer = {
      arn      = aws_lb.idp_platform.arn
      dns_name = aws_lb.idp_platform.dns_name
      zone_id  = aws_lb.idp_platform.zone_id
    }

    # Secrets configuration
    secrets = {
      config_secret_arn  = aws_secretsmanager_secret.idp_config.arn
      config_secret_name = aws_secretsmanager_secret.idp_config.name
    }

    # Monitoring configuration
    monitoring = {
      sns_topic_arn   = aws_sns_topic.alerts.arn
      health_check_id = aws_route53_health_check.idp_platform.id
    }
  }
  sensitive = true
}

# Deployment URLs
output "deployment_urls" {
  description = "Deployment URLs for the IDP platform"
  value = {
    primary_url    = "https://${var.domain_name}"
    api_url        = "https://api.${var.domain_name}"
    grafana_url    = "https://grafana.${var.domain_name}"
    prometheus_url = "https://prometheus.${var.domain_name}"
    jaeger_url     = "https://jaeger.${var.domain_name}"
  }
}