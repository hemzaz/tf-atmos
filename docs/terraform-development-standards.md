# Terraform Development Standards and Best Practices

> **Version:** 2.0.0  
> **Last Updated:** 2025-01-16  
> **Maintainer:** Platform Team

## Table of Contents

1. [Overview](#overview)
2. [Code Standards](#code-standards)
3. [Module Development](#module-development)
4. [Security Requirements](#security-requirements)
5. [State Management](#state-management)
6. [Testing and Validation](#testing-and-validation)
7. [Documentation Requirements](#documentation-requirements)
8. [CI/CD Integration](#cicd-integration)
9. [Troubleshooting Guide](#troubleshooting-guide)

## Overview

This document establishes comprehensive standards for Terraform development within our infrastructure-as-code ecosystem. These standards ensure consistency, security, maintainability, and reliability across all 17 components.

### Key Principles

- **Consistency**: Standardized naming, tagging, and structure across all components
- **Security**: Encryption by default, least privilege access, comprehensive validation
- **Maintainability**: Clear documentation, modular design, automated testing
- **Reliability**: State management best practices, drift detection, rollback capabilities

### Architecture Overview

Our Terraform infrastructure follows a modular architecture:

```
components/terraform/           # Component implementations
├── acm/                       # Certificate management
├── apigateway/               # API Gateway configuration
├── backend/                  # State backend infrastructure
├── dns/                      # Route53 DNS management
├── ec2/                      # EC2 instances and related resources
├── ecs/                      # Container service configuration
├── eks/                      # Kubernetes cluster management
├── eks-addons/              # EKS add-on configurations
├── external-secrets/        # External secrets integration
├── iam/                     # Identity and access management
├── lambda/                  # Serverless functions
├── monitoring/              # CloudWatch and monitoring
├── rds/                     # Database management
├── secretsmanager/          # AWS Secrets Manager
├── securitygroup/          # Network security groups
├── vpc/                    # Virtual private cloud
└── idp-platform/           # Internal developer platform

modules/terraform/            # Reusable modules
├── common/                  # Common naming and tagging
├── security/               # Security patterns and KMS
└── [additional modules]    # Domain-specific modules
```

## Code Standards

### File Structure

Each component must follow this standardized structure:

```
component-name/
├── main.tf                 # Primary resource definitions
├── variables.tf           # Input variable definitions
├── outputs.tf            # Output value definitions
├── provider.tf           # Provider configuration
├── data.tf               # Data source definitions (optional)
├── locals.tf             # Local value definitions (optional)
├── versions.tf           # Version constraints
├── policies/             # JSON policy templates
│   ├── policy1.json
│   └── policy2.json.tpl
├── templates/           # Template files
│   └── config.yaml.tpl
└── README.md           # Component documentation
```

### Naming Conventions

#### Resource Naming

- Use the standardized `name_prefix` pattern from the common module
- Format: `${local.name_prefix}-${resource_type}`
- Example: `myapp-prod-01-vpc`, `myapp-dev-01-lambda`

```hcl
# Import common module for consistent naming
module "common" {
  source = "../../modules/terraform/common"
  
  namespace      = var.namespace
  environment    = var.environment
  stage          = var.stage
  component_name = "vpc"
  
  # Additional configuration...
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  
  tags = merge(
    module.common.common_tags,
    {
      Name = "${module.common.component_name}-vpc"
    }
  )
}
```

#### Variable Naming

- Use `snake_case` for all variables, resources, and outputs
- Boolean variables should start with `enable_`, `is_`, or `has_`
- Collection variables should be plural

```hcl
# Good examples
variable "enable_encryption" {
  type        = bool
  description = "Enable encryption at rest"
  default     = true
}

variable "instance_types" {
  type        = list(string)
  description = "List of EC2 instance types"
  default     = ["t3.micro", "t3.small"]
}

variable "subnet_configuration" {
  type = map(object({
    cidr_block        = string
    availability_zone = string
  }))
  description = "Subnet configuration mapping"
}
```

### Variable Standards

#### Required Elements

Every variable must include:

1. **Type constraint**
2. **Description**
3. **Validation block** (when applicable)
4. **Default value** (when appropriate)

```hcl
variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "database_config" {
  type = object({
    engine_version    = string
    instance_class   = string
    allocated_storage = number
    multi_az         = bool
  })
  description = "Database configuration settings"
  
  validation {
    condition     = var.database_config.allocated_storage >= 20
    error_message = "Database allocated storage must be at least 20 GB."
  }
  
  default = {
    engine_version    = "8.0"
    instance_class   = "db.t3.micro"
    allocated_storage = 20
    multi_az         = false
  }
}
```

#### Common Variable Patterns

```hcl
# Standard tags variable
variable "tags" {
  type        = map(string)
  description = "Additional tags to apply to resources"
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.tags :
      length(k) <= 128 && length(v) <= 256
    ])
    error_message = "Tag keys must be <= 128 chars, values <= 256 chars."
  }
}

# AWS region with validation
variable "region" {
  type        = string
  description = "AWS region where resources will be created"
  
  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "Must be a valid AWS region format."
  }
}

# CIDR block validation
variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "Must be a valid CIDR block."
  }
  
  validation {
    condition     = split("/", var.vpc_cidr)[1] >= "16" && split("/", var.vpc_cidr)[1] <= "28"
    error_message = "CIDR block must have a prefix length between /16 and /28."
  }
}

# Email validation
variable "notification_emails" {
  type        = list(string)
  description = "Email addresses for notifications"
  default     = []
  
  validation {
    condition = alltrue([
      for email in var.notification_emails :
      can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All entries must be valid email addresses."
  }
}
```

### Output Standards

#### Required Elements

Every output must include:

1. **Description**
2. **Sensitive flag** (when applicable)
3. **Consistent naming pattern**

```hcl
# Resource identifiers (always include)
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_arn" {
  description = "ARN of the VPC"
  value       = aws_vpc.main.arn
}

# Sensitive information
output "database_password" {
  description = "Database master password"
  value       = aws_db_instance.main.password
  sensitive   = true
}

# Complex objects
output "subnet_configuration" {
  description = "Complete subnet configuration including IDs, ARNs, and CIDR blocks"
  value = {
    private_subnets = {
      ids        = aws_subnet.private[*].id
      arns       = aws_subnet.private[*].arn
      cidr_blocks = aws_subnet.private[*].cidr_block
    }
    public_subnets = {
      ids        = aws_subnet.public[*].id
      arns       = aws_subnet.public[*].arn
      cidr_blocks = aws_subnet.public[*].cidr_block
    }
  }
}

# Configuration summaries
output "security_configuration" {
  description = "Security configuration summary"
  value = {
    encryption_enabled    = var.enable_encryption
    kms_key_id           = aws_kms_key.main.id
    security_group_ids   = [aws_security_group.main.id]
    backup_enabled       = var.enable_backups
    monitoring_enabled   = var.enable_monitoring
  }
}
```

### Tagging Standards

#### Required Tags

All resources must include these standard tags via the common module:

- **Namespace**: Organization or project namespace
- **Environment**: Environment identifier (dev, staging, prod)
- **Component**: Component name
- **ManagedBy**: Always "terraform"
- **CreatedBy**: Always "atmos"
- **Project**: Project identifier
- **CostCenter**: Cost center for billing
- **Owner**: Team or individual responsible

#### Implementation

```hcl
# Use the common module for consistent tagging
resource "aws_instance" "web" {
  ami           = data.aws_ami.latest.id
  instance_type = var.instance_type
  
  tags = merge(
    module.common.common_tags,
    var.additional_tags,
    {
      Name = "${module.common.component_name}-web-server"
      Role = "WebServer"
    }
  )
}
```

## Module Development

### Common Module Usage

All components should import the common module for standardized naming and tagging:

```hcl
module "common" {
  source = "../../modules/terraform/common"
  
  # Required parameters
  namespace      = var.namespace
  environment    = var.environment
  stage          = var.stage
  component_name = "vpc"  # Component-specific name
  region         = var.region
  
  # Optional parameters with defaults
  project_name          = var.project_name
  cost_center          = var.cost_center
  owner               = var.owner
  data_classification = var.data_classification
  compliance_frameworks = var.compliance_frameworks
  
  additional_tags = var.additional_tags
}
```

### Security Module Usage

For components requiring KMS keys, security groups, or IAM roles:

```hcl
module "security" {
  source = "../../modules/terraform/security"
  
  # Pass common parameters
  namespace      = var.namespace
  environment    = var.environment
  stage          = var.stage
  component_name = "rds"
  region         = var.region
  
  # Security-specific configuration
  create_kms_key          = true
  enable_rds_permissions  = true
  kms_key_purpose        = "database"
  
  create_security_group = true
  vpc_id                = data.aws_vpc.main.id
  
  ingress_rules = [
    {
      description = "Database access from application subnets"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = var.app_subnet_cidrs
    }
  ]
}
```

### Custom Module Development

When creating new modules:

1. Follow the same file structure as components
2. Use the common module for consistency
3. Provide comprehensive examples
4. Include automated tests

```hcl
# Custom module example structure
modules/terraform/database/
├── main.tf
├── variables.tf
├── outputs.tf
├── versions.tf
├── README.md
└── examples/
    ├── basic/
    └── advanced/
```

## Security Requirements

### Encryption Standards

#### At Rest

- All storage must be encrypted by default
- Use customer-managed KMS keys for sensitive data
- Implement key rotation

```hcl
# S3 bucket with encryption
resource "aws_s3_bucket" "data" {
  bucket = "${module.common.component_name}-data"
  
  tags = module.common.common_tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = module.security.kms_key_id
      sse_algorithm     = "aws:kms"
    }
  }
}
```

#### In Transit

- Enforce HTTPS/TLS for all communications
- Use AWS PrivateLink where applicable
- Implement certificate management

```hcl
# ALB with TLS enforcement
resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = data.aws_acm_certificate.web.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# Redirect HTTP to HTTPS
resource "aws_lb_listener" "web_redirect" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
```

### IAM Best Practices

#### Least Privilege

- Grant minimum required permissions
- Use specific resource ARNs
- Implement condition blocks

```hcl
resource "aws_iam_policy" "s3_access" {
  name        = "${module.common.component_name}-s3-access"
  description = "S3 access policy for ${module.common.component_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.data.arn}/*"
        ]
        Condition = {
          StringEquals = {
            "s3:x-amz-server-side-encryption" = "aws:kms"
          }
        }
      }
    ]
  })
  
  tags = module.common.common_tags
}
```

#### Service-Linked Roles

Use service-linked roles where possible and create custom roles only when necessary:

```hcl
# Use existing service-linked role
data "aws_iam_role" "service_linked" {
  name = "AWSServiceRoleForECS"
}

# Create custom role only when required
resource "aws_iam_role" "custom" {
  count = var.create_custom_role ? 1 : 0
  
  name = "${module.common.component_name}-custom-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = var.trusted_service
        }
        Condition = {
          StringEquals = {
            "sts:ExternalId" = var.external_id
          }
        }
      }
    ]
  })
  
  tags = module.common.common_tags
}
```

### Network Security

#### Security Groups

- Follow least privilege principles
- Use descriptive names and descriptions
- Reference other security groups instead of CIDR blocks when possible

```hcl
resource "aws_security_group" "database" {
  name        = "${module.common.component_name}-database"
  description = "Security group for ${module.common.component_name} database"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Database access from application tier"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.application.id]
  }
  
  ingress {
    description = "Database access from bastion host"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.bastion_cidr_blocks
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    module.common.common_tags,
    {
      Name = "${module.common.component_name}-database-sg"
    }
  )
  
  lifecycle {
    create_before_destroy = true
  }
}
```

#### Network ACLs

Use NACLs for additional defense in depth:

```hcl
resource "aws_network_acl" "private" {
  vpc_id = var.vpc_id
  subnet_ids = aws_subnet.private[*].id

  # Allow inbound from VPC CIDR
  ingress {
    protocol   = -1
    rule_no    = 100
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 0
    to_port    = 0
  }

  # Allow outbound to everywhere
  egress {
    protocol   = -1
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge(
    module.common.common_tags,
    {
      Name = "${module.common.component_name}-private-nacl"
    }
  )
}
```

## State Management

### Backend Configuration

#### S3 Backend with DynamoDB Locking

Our standardized backend configuration:

```hcl
terraform {
  backend "s3" {
    bucket         = "terraform-state-${var.account_id}-${var.region}"
    key            = "${var.component}/${var.environment}/${var.stack}.tfstate"
    region         = var.region
    encrypt        = true
    kms_key_id     = "arn:aws:kms:${var.region}:${var.account_id}:key/${var.kms_key_id}"
    dynamodb_table = "terraform-state-lock"
    
    # Role assumption for cross-account access
    role_arn = var.assume_role_arn
  }
}
```

#### State File Organization

Organize state files hierarchically:

```
s3://terraform-state-bucket/
├── backend/
│   └── prod/
│       └── core.tfstate
├── vpc/
│   ├── dev/
│   │   └── dev-01.tfstate
│   └── prod/
│       └── prod-01.tfstate
└── eks/
    ├── dev/
    │   └── dev-01.tfstate
    └── prod/
        └── prod-01.tfstate
```

### State Management Best Practices

#### Remote State References

Use remote state data sources sparingly and prefer explicit outputs:

```hcl
# Preferred: Use explicit data sources
data "aws_vpc" "main" {
  tags = {
    Name        = "${var.environment}-vpc"
    Environment = var.environment
  }
}

# Avoid: Remote state references
# data "terraform_remote_state" "vpc" {
#   backend = "s3"
#   config = {
#     bucket = var.state_bucket
#     key    = "vpc/${var.environment}/terraform.tfstate"
#     region = var.region
#   }
# }
```

#### State Import Procedures

Document state import procedures for each resource type:

```bash
# Import existing VPC
terraform import aws_vpc.main vpc-12345678

# Import existing security group
terraform import aws_security_group.web sg-12345678

# Verify import
terraform plan
```

#### State Backup and Recovery

Implement automated state backup:

```hcl
# Lambda function for state backup
resource "aws_lambda_function" "state_backup" {
  filename         = "state-backup.zip"
  function_name    = "${module.common.component_name}-state-backup"
  role            = aws_iam_role.state_backup.arn
  handler         = "index.handler"
  runtime         = "python3.9"
  timeout         = 300

  environment {
    variables = {
      SOURCE_BUCKET = var.state_bucket
      BACKUP_BUCKET = var.backup_bucket
    }
  }

  tags = module.common.common_tags
}

# CloudWatch event for daily backup
resource "aws_cloudwatch_event_rule" "daily_backup" {
  name                = "${module.common.component_name}-daily-backup"
  description         = "Daily state backup"
  schedule_expression = "cron(0 2 * * ? *)"
  
  tags = module.common.common_tags
}
```

## Testing and Validation

### Automated Validation Pipeline

Use our enhanced validation workflow:

```yaml
# .github/workflows/terraform-validation.yml
name: Terraform Validation
on:
  pull_request:
    paths:
      - 'components/terraform/**'
      - 'modules/terraform/**'

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: 1.11.0
          
      - name: Run Enhanced Validation
        run: |
          atmos workflow enhanced-validation \\
            tenant=fnx \\
            account=dev \\
            environment=testenv-01
```

### Pre-commit Hooks

Configure pre-commit hooks for local validation:

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.81.0
    hooks:
      - id: terraform_fmt
        args: [--args=-recursive]
      - id: terraform_validate
        args: [--args=-json]
      - id: terraform_docs
        args: [--args=--sort-by-required]
      - id: terraform_tflint
        args: [--args=--only=terraform_deprecated_interpolation]
      - id: terraform_tfsec
        args: [--args=--severity=MEDIUM]
```

### Unit Testing

Implement unit tests using Terratest:

```go
// test/vpc_test.go
package test

import (
    "testing"
    "github.com/gruntwork-io/terratest/modules/terraform"
    "github.com/stretchr/testify/assert"
)

func TestVPCCreation(t *testing.T) {
    terraformOptions := &terraform.Options{
        TerraformDir: "../components/terraform/vpc",
        Vars: map[string]interface{}{
            "vpc_cidr":    "10.0.0.0/16",
            "environment": "test",
            "namespace":   "test",
        },
    }

    defer terraform.Destroy(t, terraformOptions)
    terraform.InitAndApply(t, terraformOptions)

    vpcID := terraform.Output(t, terraformOptions, "vpc_id")
    assert.NotEmpty(t, vpcID)
}
```

### Integration Testing

Test component interactions:

```go
func TestVPCEKSIntegration(t *testing.T) {
    // Deploy VPC first
    vpcOptions := &terraform.Options{
        TerraformDir: "../components/terraform/vpc",
        // ... configuration
    }
    
    defer terraform.Destroy(t, vpcOptions)
    terraform.InitAndApply(t, vpcOptions)
    
    // Get VPC outputs
    vpcID := terraform.Output(t, vpcOptions, "vpc_id")
    subnetIDs := terraform.OutputList(t, vpcOptions, "private_subnet_ids")
    
    // Deploy EKS using VPC outputs
    eksOptions := &terraform.Options{
        TerraformDir: "../components/terraform/eks",
        Vars: map[string]interface{}{
            "vpc_id":     vpcID,
            "subnet_ids": subnetIDs,
        },
    }
    
    defer terraform.Destroy(t, eksOptions)
    terraform.InitAndApply(t, eksOptions)
}
```

## Documentation Requirements

### Component README Template

Each component must include a comprehensive README:

````markdown
# Component Name

Brief description of the component's purpose and functionality.

## Architecture

Diagram or description of the component's architecture and relationships.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.3.0 |
| aws | >= 5.0 |

## Providers

| Name | Version |
|------|---------|
| aws | >= 5.0 |

## Resources

| Name | Type |
|------|------|
| [aws_vpc.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| vpc_cidr | CIDR block for the VPC | `string` | n/a | yes |
| environment | Environment name | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| vpc_id | ID of the VPC |
| vpc_arn | ARN of the VPC |

## Usage

```hcl
module "vpc" {
  source = "./components/terraform/vpc"
  
  vpc_cidr    = "10.0.0.0/16"
  environment = "prod"
  namespace   = "myapp"
}
```

## Examples

- [Basic VPC](../../examples/vpc/basic/)
- [VPC with Multiple AZs](../../examples/vpc/multi-az/)

## Security Considerations

- All subnets are private by default
- NACLs provide additional security layer
- VPC Flow Logs are enabled

## Cost Optimization

- NAT Gateway usage optimized per environment
- VPC Endpoints used to reduce data transfer costs
````

### Code Comments

Use descriptive comments for complex logic:

```hcl
# This locals block implements a sophisticated subnet calculation
# that automatically distributes subnets across availability zones
# while maintaining consistent CIDR block sizing
locals {
  # Calculate the number of bits needed for subnet addressing
  # For a /16 VPC with /24 subnets, we need 8 additional bits
  subnet_bits = var.subnet_size - split("/", var.vpc_cidr)[1]
  
  # Create subnet configurations for each AZ
  # This approach ensures even distribution and prevents overlap
  subnet_configs = {
    for idx, az in var.availability_zones : az => {
      cidr_block        = cidrsubnet(var.vpc_cidr, local.subnet_bits, idx)
      availability_zone = az
    }
  }
}
```

## CI/CD Integration

### Pipeline Configuration

Integrate Terraform validation into CI/CD pipelines:

```yaml
# Jenkinsfile
pipeline {
    agent any
    
    environment {
        AWS_REGION = 'us-west-2'
        TF_VERSION = '1.11.0'
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        
        stage('Terraform Format Check') {
            steps {
                script {
                    sh 'terraform fmt -check -recursive -diff'
                }
            }
        }
        
        stage('Enhanced Validation') {
            steps {
                script {
                    sh """
                        atmos workflow enhanced-validation \\
                            tenant=${params.TENANT} \\
                            account=${params.ACCOUNT} \\
                            environment=${params.ENVIRONMENT}
                    """
                }
            }
        }
        
        stage('Plan') {
            when {
                not { branch 'main' }
            }
            steps {
                script {
                    sh """
                        atmos workflow plan-environment \\
                            tenant=${params.TENANT} \\
                            account=${params.ACCOUNT} \\
                            environment=${params.ENVIRONMENT}
                    """
                }
            }
        }
        
        stage('Apply') {
            when {
                branch 'main'
            }
            steps {
                script {
                    sh """
                        atmos workflow apply-environment \\
                            tenant=${params.TENANT} \\
                            account=${params.ACCOUNT} \\
                            environment=${params.ENVIRONMENT} \\
                            auto_approve=true
                    """
                }
            }
        }
    }
    
    post {
        always {
            archiveArtifacts artifacts: 'logs/**/*', allowEmptyArchive: true
        }
    }
}
```

### Deployment Strategies

#### Blue/Green Deployment

For critical infrastructure changes:

```hcl
# Blue/Green deployment configuration
variable "deployment_color" {
  type        = string
  description = "Deployment color (blue or green)"
  default     = "blue"
  
  validation {
    condition     = contains(["blue", "green"], var.deployment_color)
    error_message = "Deployment color must be 'blue' or 'green'."
  }
}

resource "aws_launch_template" "app" {
  name = "${module.common.component_name}-${var.deployment_color}"
  
  # ... configuration
  
  tags = merge(
    module.common.common_tags,
    {
      DeploymentColor = var.deployment_color
    }
  )
}
```

#### Canary Deployments

For gradual rollouts:

```hcl
resource "aws_lb_target_group" "canary" {
  count = var.enable_canary_deployment ? 1 : 0
  
  name     = "${module.common.component_name}-canary"
  port     = var.application_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  
  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = var.health_check_path
    matcher             = "200"
  }
  
  tags = module.common.common_tags
}

resource "aws_lb_listener_rule" "canary" {
  count = var.enable_canary_deployment ? 1 : 0
  
  listener_arn = var.alb_listener_arn
  priority     = var.canary_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.canary[0].arn
  }

  condition {
    host_header {
      values = ["canary.${var.domain_name}"]
    }
  }
  
  condition {
    http_header {
      http_header_name = "X-Canary-User"
      values           = ["true"]
    }
  }
}
```

## Troubleshooting Guide

### Common Issues and Solutions

#### State Lock Conflicts

```bash
# List DynamoDB locks
aws dynamodb scan \\
    --table-name terraform-state-lock \\
    --attributes-to-get LockID

# Force unlock (use with caution)
terraform force-unlock <LOCK_ID>
```

#### Import Existing Resources

```bash
# Generate import blocks
terraform plan -generate-config-out=generated.tf

# Review and modify generated configuration
# Then import the resources
terraform import aws_vpc.main vpc-12345678
```

#### Resource Dependencies

```hcl
# Explicit dependencies
resource "aws_instance" "web" {
  # ... configuration
  
  depends_on = [
    aws_security_group.web,
    aws_iam_instance_profile.web
  ]
}

# Use data sources to establish implicit dependencies
data "aws_security_group" "web" {
  id = aws_security_group.web.id
}

resource "aws_instance" "web" {
  vpc_security_group_ids = [data.aws_security_group.web.id]
}
```

#### Provider Configuration Issues

```hcl
# Multiple provider configurations
provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}

provider "aws" {
  alias  = "us-west-2"
  region = "us-west-2"
}

# Use specific provider
resource "aws_s3_bucket" "logs" {
  provider = aws.us-east-1
  # ... configuration
}
```

### Performance Optimization

#### Parallel Execution

```hcl
# Enable parallelism (default is 10)
# terraform apply -parallelism=20

# For large infrastructures, increase parallelism
# But be aware of API rate limits
```

#### Resource Graph Optimization

```hcl
# Avoid unnecessary dependencies
# Bad: This creates unnecessary dependency
resource "aws_instance" "web" {
  subnet_id = aws_subnet.web.id
  
  depends_on = [aws_internet_gateway.main]  # Unnecessary
}

# Good: Let Terraform determine dependencies
resource "aws_instance" "web" {
  subnet_id = aws_subnet.web.id
  # Terraform automatically knows about IGW dependency through subnet
}
```

### Debugging Techniques

#### Enable Debug Logging

```bash
export TF_LOG=DEBUG
export TF_LOG_PATH=./terraform-debug.log

terraform plan
```

#### Graph Visualization

```bash
# Generate dependency graph
terraform graph | dot -Tsvg > graph.svg

# Open graph.svg in browser to visualize dependencies
```

#### State Inspection

```bash
# List resources in state
terraform state list

# Show specific resource
terraform state show aws_vpc.main

# Pull remote state
terraform state pull > state.json
```

This comprehensive standards document ensures consistent, secure, and maintainable Terraform code across all infrastructure components. Regular updates and team training on these standards are essential for long-term success.