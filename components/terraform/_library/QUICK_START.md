# Alexandria Library - Quick Start Guide

Welcome to the Alexandria Library! This guide will help you get started using these production-ready Terraform modules.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Module Discovery](#module-discovery)
3. [Using Modules](#using-modules)
4. [Common Patterns](#common-patterns)
5. [Best Practices](#best-practices)
6. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Tools
- Terraform >= 1.5.0
- AWS CLI >= 2.0
- Git

### AWS Credentials
```bash
# Configure AWS credentials
aws configure

# Verify access
aws sts get-caller-identity
```

### Terraform Setup
```bash
# Verify Terraform version
terraform version

# Should show: Terraform v1.5.0 or newer
```

---

## Module Discovery

### Browse Available Modules

```bash
# List all modules
ls -la /Users/elad/PROJ/tf-atmos/components/terraform/_library/

# View module categories
networking/       # VPC, peering, Transit Gateway, etc.
compute/          # EKS, Lambda, ECS, EC2
data-layer/       # S3, RDS, DynamoDB, etc.
integration/      # SQS, SNS, API Gateway, Kinesis
security/         # KMS, Secrets Manager, WAF, etc.
observability/    # CloudWatch, X-Ray, Grafana
patterns/         # Complete application stacks
```

### Check Module Status

See [IMPLEMENTATION_STATUS.md](./IMPLEMENTATION_STATUS.md) for:
- Completed modules
- Modules in progress
- Planned modules
- Implementation timeline

---

## Using Modules

### Basic Module Usage

#### 1. Create a new Terraform project

```bash
mkdir my-infrastructure
cd my-infrastructure
```

#### 2. Create `main.tf`

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Use a module from the library
module "vpc" {
  source = "../_library/networking/vpc-advanced"

  name_prefix = "myapp"
  environment = "production"
  vpc_cidr    = "10.0.0.0/16"

  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = false

  enable_flow_logs = true

  tags = {
    Terraform = "true"
    Owner     = "platform-team"
  }
}
```

#### 3. Initialize and Apply

```bash
# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply changes
terraform apply
```

---

## Common Patterns

### Pattern 1: Three-Tier Web Application

```hcl
# VPC
module "vpc" {
  source = "../_library/networking/vpc-advanced"
  # ... configuration
}

# Application Load Balancer
module "alb" {
  source = "../_library/compute/application-load-balancer"
  # ... configuration
}

# ECS Fargate Service
module "web_service" {
  source = "../_library/compute/ecs-fargate-service"
  # ... configuration

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
}

# RDS Database
module "database" {
  source = "../_library/data-layer/rds-postgres"
  # ... configuration

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.database_subnet_ids
}
```

### Pattern 2: Serverless API

```hcl
# S3 Bucket for static assets
module "assets_bucket" {
  source = "../_library/data-layer/s3-bucket"
  # ... configuration
}

# DynamoDB Table
module "api_database" {
  source = "../_library/data-layer/dynamodb-table"
  # ... configuration
}

# Lambda Function
module "api_function" {
  source = "../_library/compute/lambda-function"
  # ... configuration
}

# API Gateway
module "api" {
  source = "../_library/integration/api-gateway-rest"
  # ... configuration

  lambda_function_arn = module.api_function.function_arn
}
```

### Pattern 3: Data Processing Pipeline

```hcl
# S3 Buckets (raw, processed)
module "raw_data_bucket" {
  source = "../_library/data-layer/s3-bucket"
  # ... configuration
}

module "processed_data_bucket" {
  source = "../_library/data-layer/s3-bucket"
  # ... configuration
}

# SQS Queue for processing
module "processing_queue" {
  source = "../_library/integration/sqs-queue"
  # ... configuration
}

# Lambda for data processing
module "processor" {
  source = "../_library/compute/lambda-function"
  # ... configuration

  event_source_arn = module.processing_queue.queue_arn
}
```

---

## Best Practices

### 1. Module Versioning

Use specific module versions in production:

```hcl
module "vpc" {
  source = "git::https://github.com/yourorg/alexandria-library.git//networking/vpc-advanced?ref=v1.0.0"
  # ... configuration
}
```

### 2. Remote State

Always use remote state for team collaboration:

```hcl
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "infrastructure/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

### 3. Environment Separation

Use workspaces or separate state files:

```bash
# Using workspaces
terraform workspace new production
terraform workspace new staging
terraform workspace new dev

# Or separate directories
infrastructure/
├── dev/
│   └── main.tf
├── staging/
│   └── main.tf
└── production/
    └── main.tf
```

### 4. Variable Files

Use `.tfvars` files for environment-specific values:

```hcl
# terraform.tfvars
name_prefix = "myapp"
environment = "production"
vpc_cidr    = "10.0.0.0/16"

# production.tfvars
instance_count = 10
enable_multi_az = true

# dev.tfvars
instance_count = 2
enable_multi_az = false
```

Apply with:
```bash
terraform apply -var-file="production.tfvars"
```

### 5. Secrets Management

Never commit secrets to Git:

```hcl
# Use AWS Secrets Manager
data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = "production/database/password"
}

module "database" {
  source = "../_library/data-layer/rds-postgres"

  master_password = data.aws_secretsmanager_secret_version.db_password.secret_string
}
```

### 6. Tagging Strategy

Apply consistent tags to all resources:

```hcl
locals {
  common_tags = {
    Terraform   = "true"
    Environment = var.environment
    Project     = "myapp"
    Owner       = "platform-team"
    CostCenter  = "engineering"
    ManagedBy   = "terraform"
  }
}

module "vpc" {
  source = "../_library/networking/vpc-advanced"

  tags = local.common_tags
}
```

### 7. Cost Optimization

Review module options for cost savings:

```hcl
# Development environment - single NAT Gateway
module "vpc_dev" {
  source = "../_library/networking/vpc-advanced"

  environment        = "dev"
  enable_nat_gateway = true
  single_nat_gateway = true  # Cost saving
}

# Production environment - NAT Gateway per AZ
module "vpc_prod" {
  source = "../_library/networking/vpc-advanced"

  environment        = "production"
  enable_nat_gateway = true
  single_nat_gateway = false  # High availability
}
```

---

## Troubleshooting

### Module Not Found

**Error**: `Module not found: module.vpc`

**Solution**: Check the module source path:
```hcl
# Correct relative path
source = "../_library/networking/vpc-advanced"

# Or absolute path
source = "/Users/elad/PROJ/tf-atmos/components/terraform/_library/networking/vpc-advanced"
```

### Version Constraint Errors

**Error**: `Terraform version constraint not met`

**Solution**: Update Terraform to >= 1.5.0:
```bash
# Download from terraform.io or use tfenv
tfenv install 1.5.0
tfenv use 1.5.0
```

### AWS Permissions Errors

**Error**: `AccessDenied` or `UnauthorizedOperation`

**Solution**: Verify IAM permissions:
```bash
# Check current identity
aws sts get-caller-identity

# List permissions
aws iam get-user-policy --user-name your-user --policy-name your-policy
```

### State Lock Errors

**Error**: `Error locking state`

**Solution**:
```bash
# Force unlock (use carefully!)
terraform force-unlock <lock-id>

# Or use DynamoDB table for locking
# See remote state configuration
```

### Module Validation Errors

**Error**: `Invalid value for variable`

**Solution**: Check variable validation rules in `variables.tf`:
```hcl
# Example: Environment must be dev, staging, or production
variable "environment" {
  type = string

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be dev, staging, or production."
  }
}
```

---

## Getting Help

### Module Documentation

Each module has comprehensive documentation:
```bash
# View module README
cat _library/networking/vpc-advanced/README.md

# View examples
ls _library/networking/vpc-advanced/examples/
```

### Module Examples

Run examples to see modules in action:
```bash
cd _library/networking/vpc-advanced/examples/complete
terraform init
terraform plan
```

### Common Issues

Check [Known Issues](./README.md#known-issues) section in module READMEs.

### Support Channels

- **Issues**: GitHub Issues
- **Discussions**: GitHub Discussions
- **Slack**: #infrastructure-team
- **Email**: platform-team@yourcompany.com

---

## Next Steps

1. **Explore Modules**: Browse available modules in each category
2. **Review Examples**: Check out the examples directory for each module
3. **Read Specifications**: See [MODULE_SPECIFICATIONS.md](./MODULE_SPECIFICATIONS.md) for detailed features
4. **Check Status**: Review [IMPLEMENTATION_STATUS.md](./IMPLEMENTATION_STATUS.md) for module availability
5. **Start Building**: Create your first infrastructure stack!

---

## Additional Resources

- [Terraform Documentation](https://www.terraform.io/docs)
- [AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)

---

**Happy Infrastructure Building! 🚀**
