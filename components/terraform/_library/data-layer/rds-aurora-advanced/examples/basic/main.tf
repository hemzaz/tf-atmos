module "aurora_basic" {
  source = "../.."

  name_prefix = "myapp"
  environment = "dev"
  
  vpc_id     = "vpc-0123456789abcdef0"  # Replace with actual VPC ID
  subnet_ids = [
    "subnet-abc123",  # Replace with actual subnet IDs
    "subnet-def456",
    "subnet-ghi789"
  ]
  
  engine          = "aurora-postgresql"
  engine_version  = "15.4"
  instance_class  = "db.t4g.medium"  # Small instance for dev
  instance_count  = 1                 # Single instance for dev
  
  database_name    = "myapp_dev"
  master_username  = "dbadmin"
  
  # Dev settings
  backup_retention_period     = 1
  enable_deletion_protection  = false
  skip_final_snapshot         = true
  
  # Disable expensive features for dev
  enable_performance_insights = false
  enable_enhanced_monitoring  = false
  enable_autoscaling          = false
  
  allowed_cidr_blocks = ["10.0.0.0/16"]
  
  tags = {
    Environment = "development"
    Purpose     = "testing"
  }
}

output "endpoint" {
  value = module.aurora_basic.cluster_endpoint
}

output "secret_arn" {
  value     = module.aurora_basic.master_password_secret_arn
  sensitive = true
}
