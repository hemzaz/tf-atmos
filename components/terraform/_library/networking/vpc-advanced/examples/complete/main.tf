provider "aws" {
  region = "us-east-1"
}

module "vpc" {
  source = "../../"

  name_prefix = "myapp"
  environment = "production"
  vpc_cidr    = "10.0.0.0/16"

  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

  # Subnets
  public_subnets   = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnets  = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
  database_subnets = ["10.0.21.0/24", "10.0.22.0/24", "10.0.23.0/24"]

  # NAT Gateway - one per AZ for high availability
  enable_nat_gateway = true
  single_nat_gateway = false

  # DNS
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Flow Logs
  enable_flow_logs           = true
  flow_logs_destination_type = "cloud-watch-logs"
  flow_logs_retention_days   = 30

  # VPC Endpoints for cost optimization and security
  enable_vpc_endpoints = true
  vpc_endpoints = {
    s3 = {
      service_type    = "Gateway"
      route_table_ids = ["private", "database"]
    }
    dynamodb = {
      service_type    = "Gateway"
      route_table_ids = ["private"]
    }
    ec2 = {
      service_type        = "Interface"
      subnet_ids          = ["private"]
      private_dns_enabled = true
    }
    ecr_api = {
      service_type        = "Interface"
      subnet_ids          = ["private"]
      private_dns_enabled = true
    }
    ecr_dkr = {
      service_type        = "Interface"
      subnet_ids          = ["private"]
      private_dns_enabled = true
    }
    logs = {
      service_type        = "Interface"
      subnet_ids          = ["private"]
      private_dns_enabled = true
    }
    ssm = {
      service_type        = "Interface"
      subnet_ids          = ["private"]
      private_dns_enabled = true
    }
    ssmmessages = {
      service_type        = "Interface"
      subnet_ids          = ["private"]
      private_dns_enabled = true
    }
    ec2messages = {
      service_type        = "Interface"
      subnet_ids          = ["private"]
      private_dns_enabled = true
    }
  }

  # Security
  manage_default_security_group = true

  tags = {
    Terraform   = "true"
    Owner       = "platform-team"
    Project     = "myapp"
    CostCenter  = "engineering"
    Environment = "production"
  }
}

#------------------------------------------------------------------------------
# Optional: Create a security group for VPC endpoints
#------------------------------------------------------------------------------
resource "aws_security_group" "vpc_endpoints" {
  name_description = "Security group for VPC endpoints"
  vpc_id          = module.vpc.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "myapp-production-vpce-sg"
  }
}
