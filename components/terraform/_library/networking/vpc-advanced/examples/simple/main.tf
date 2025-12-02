provider "aws" {
  region = "us-east-1"
}

module "vpc" {
  source = "../../"

  name_prefix = "myapp"
  environment = "dev"
  vpc_cidr    = "10.0.0.0/16"

  availability_zones = ["us-east-1a", "us-east-1b"]

  # Basic subnet configuration
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24"]

  # Single NAT Gateway for cost savings in dev
  enable_nat_gateway = true
  single_nat_gateway = true

  # Enable flow logs for security
  enable_flow_logs           = true
  flow_logs_destination_type = "cloud-watch-logs"
  flow_logs_retention_days   = 7

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}
