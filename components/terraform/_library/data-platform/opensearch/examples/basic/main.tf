module "opensearch" {
  source = "../.."

  domain_name    = "dev-search"
  engine_version = "OpenSearch_2.11"

  instance_type  = "t3.small.search"
  instance_count = 2

  zone_awareness_enabled  = true
  availability_zone_count = 2

  ebs_volume_size = 100
  ebs_volume_type = "gp3"

  internal_user_database_enabled = true
  master_user_name               = "admin"
  master_user_password           = "Admin123!" # Change in production!

  access_principals = ["*"]

  enable_monitoring = true

  tags = {
    Environment = "development"
    Example     = "basic"
  }
}

output "opensearch_endpoint" {
  value = module.opensearch.endpoint
}

output "dashboards_endpoint" {
  value = module.opensearch.kibana_endpoint
}
