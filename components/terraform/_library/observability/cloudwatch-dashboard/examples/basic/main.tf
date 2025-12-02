module "cloudwatch_dashboard" {
  source = "../../"

  name_prefix = "example-prod"
  region      = "us-east-1"

  create_infrastructure_widgets = true
  create_application_widgets    = true
  create_cost_widgets           = false
  create_security_widgets       = false

  enable_auto_discovery = true
  discovery_tags = {
    Environment = "production"
    Monitoring  = "enabled"
  }

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
    Example     = "basic"
  }
}

output "dashboard_url" {
  value = module.cloudwatch_dashboard.dashboard_url
}
