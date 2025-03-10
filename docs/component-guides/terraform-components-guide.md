# Terraform Components Guide

_Last Updated: March 10, 2025_

This comprehensive guide covers all aspects of Terraform components in the Atmos framework, including component structure, development process, best practices, and integration patterns.

## Table of Contents

1. [Introduction](#introduction)
2. [Component Catalog](#component-catalog)
   - [Network Layer Components](#network-layer-components)
   - [Compute Layer Components](#compute-layer-components)
   - [Data Layer Components](#data-layer-components)
   - [Security Layer Components](#security-layer-components)
   - [API Layer Components](#api-layer-components)
   - [Integration Patterns](#integration-patterns)
3. [Component Structure](#component-structure)
   - [Standard File Organization](#standard-file-organization)
   - [File Purposes and Contents](#file-purposes-and-contents)
4. [Component Development Process](#component-development-process)
   - [Setting Up the Component Directory](#setting-up-the-component-directory)
   - [Creating the Necessary Files](#creating-the-necessary-files)
   - [Developing and Testing the Component](#developing-and-testing-the-component)
   - [Adding Component Metadata](#adding-component-metadata)
5. [Catalog Integration](#catalog-integration)
   - [Creating a Catalog Entry](#creating-a-catalog-entry)
   - [Variables and Outputs Configuration](#variables-and-outputs-configuration)
   - [Component Dependencies](#component-dependencies)
6. [Environment Integration](#environment-integration)
   - [Environment Configuration](#environment-configuration)
   - [Stack Dependencies](#stack-dependencies)
   - [Using Mixins for Reusable Configurations](#using-mixins-for-reusable-configurations)
7. [Validation and Deployment](#validation-and-deployment)
   - [Schema Validation](#schema-validation)
   - [Component Validation](#component-validation)
   - [Deployment Process](#deployment-process)
8. [Advanced Techniques](#advanced-techniques)
   - [Dynamic Resource Creation](#dynamic-resource-creation)
   - [Conditional Resources](#conditional-resources)
   - [Complex Validations](#complex-validations)
   - [Cross-Component References](#cross-component-references)
9. [Best Practices](#best-practices)
   - [Resource Structure](#resource-structure)
   - [Security Considerations](#security-considerations)
   - [Naming Conventions](#naming-conventions)
   - [Documentation Standards](#documentation-standards)
10. [Practical Examples](#practical-examples)
    - [Basic Component Example (VPC)](#basic-component-example-vpc)
    - [Intermediate Component Example (Elasticache)](#intermediate-component-example-elasticache)
    - [Advanced Component Example (EKS)](#advanced-component-example-eks)
11. [Troubleshooting and FAQs](#troubleshooting-and-faqs)
    - [Common Issues and Solutions](#common-issues-and-solutions)
    - [Validation Errors](#validation-errors)
    - [Deployment Failures](#deployment-failures)

## Introduction

Terraform components are the building blocks of infrastructure in the Atmos framework. Each component encapsulates a specific piece of infrastructure, making it reusable, configurable, and maintainable. Components follow a standard structure that ensures consistency and promotes best practices.

Components in Atmos enable:

1. **Reusability** - Use the same component across multiple environments
2. **Configurability** - Customize component behavior through variables
3. **Consistency** - Standardize infrastructure patterns
4. **Composability** - Combine components to create complex infrastructure
5. **Versioning** - Track and manage infrastructure changes over time

## Component Catalog

The component catalog organizes components by infrastructure layer, making it easy to find and reuse existing components.

### Network Layer Components

| Component | Description | Status | Key Features |
|-----------|-------------|--------|--------------|
| **vpc** | Virtual Private Cloud | Stable | Multi-AZ, VPC Flow Logs, VPC Peering, Transit Gateway |
| **securitygroup** | Security Groups | Stable | Ingress/Egress rules, Dynamic source groups |
| **dns** | Route53 DNS | Stable | Public/Private zones, DNS records, Health checks |
| **apigateway** | API Gateway | Beta | REST/HTTP APIs, Throttling, Custom domains |
| **cloudfront** | CloudFront Distribution | Beta | Custom origins, Cache behaviors, WAF integration |

### Compute Layer Components

| Component | Description | Status | Key Features |
|-----------|-------------|--------|--------------|
| **ec2** | EC2 Instances | Stable | Auto-scaling, Spot Instances, Launch Templates |
| **eks** | Elastic Kubernetes Service | Stable | Managed Node Groups, IRSA, Add-ons |
| **eks-addons** | EKS Add-ons | Stable | ALB Controller, ExternalDNS, Cert-manager |
| **ecs** | Elastic Container Service | Stable | Fargate, Auto-scaling, Capacity Providers |
| **lambda** | Lambda Functions | Stable | Event sources, VPC integration, Layers |

### Data Layer Components

| Component | Description | Status | Key Features |
|-----------|-------------|--------|--------------|
| **rds** | Relational Database Service | Stable | MySQL, PostgreSQL, Multi-AZ, Encryption |
| **dynamodb** | DynamoDB Tables | Stable | Autoscaling, Global tables, Streams |
| **elasticache** | ElastiCache | Beta | Redis, Memcached, Replication Groups |
| **s3** | S3 Buckets | Stable | Versioning, Lifecycle, Encryption |
| **msk** | Managed Streaming for Kafka | Alpha | Multi-AZ, Auto-scaling, Encryption |

### Security Layer Components

| Component | Description | Status | Key Features |
|-----------|-------------|--------|--------------|
| **iam** | IAM Roles and Policies | Stable | Cross-account, OIDC, Service Accounts |
| **acm** | Certificate Manager | Stable | Public/Private CAs, Auto-renewal |
| **secretsmanager** | Secrets Manager | Stable | Rotation, Cross-account access |
| **waf** | Web Application Firewall | Beta | Managed rules, Rate limiting |
| **kms** | Key Management Service | Stable | Key rotation, Multi-region |

### API Layer Components

| Component | Description | Status | Key Features |
|-----------|-------------|--------|--------------|
| **apigateway** | API Gateway | Stable | REST APIs, Authorizers, Throttling |
| **appsync** | AppSync GraphQL | Beta | Resolvers, Authorization, Subscriptions |
| **cognito** | Cognito User Pools | Beta | MFA, OAuth, SAML |

### Integration Patterns

Components are designed to integrate with each other to create common architectural patterns. Below are common integration patterns and the components they use:

#### Web Application Pattern

![Web Application Pattern](https://via.placeholder.com/800x400?text=Web+Application+Pattern)

```
┌───────────┐     ┌───────────┐     ┌───────────┐     ┌───────────┐
│           │     │           │     │           │     │           │
│  Route53  │────▶│CloudFront │────▶│    ALB    │────▶│    ECS    │
│           │     │           │     │           │     │           │
└───────────┘     └───────────┘     └───────────┘     └───────────┘
                                                            │
                                                            ▼
                                                      ┌───────────┐     ┌───────────┐
                                                      │           │     │           │
                                                      │    RDS    │◀───▶│ElastiCache│
                                                      │           │     │           │
                                                      └───────────┘     └───────────┘
```

Components used:
- dns (Route53)
- cloudfront
- ec2 (ALB)
- ecs
- rds
- elasticache

## Component Structure

### Standard File Organization

Terraform components follow a standard file organization to ensure consistency across the infrastructure codebase:

```
components/terraform/
└── component-name/
    ├── README.md            # Component documentation
    ├── main.tf              # Main resource definitions
    ├── variables.tf         # Input variables
    ├── outputs.tf           # Output values
    ├── provider.tf          # Provider configuration
    ├── versions.tf          # Terraform version constraints
    ├── data.tf              # Data sources (optional)
    ├── locals.tf            # Local variables (optional)
    └── policies/            # IAM policies (optional)
        ├── policy-name.json
        └── ...
```

### File Purposes and Contents

#### main.tf

Contains the main resource definitions for the component. Resources should be organized logically, with related resources grouped together.

```terraform
resource "aws_elasticache_subnet_group" "default" {
  count = module.this.enabled ? 1 : 0

  name       = module.this.id
  subnet_ids = var.subnet_ids

  tags = module.this.tags
}

resource "aws_elasticache_replication_group" "default" {
  count = module.this.enabled ? 1 : 0

  replication_group_id          = module.this.id
  description                   = var.description
  node_type                     = var.instance_type
  port                          = var.port
  subnet_group_name             = join("", aws_elasticache_subnet_group.default.*.name)
  security_group_ids            = var.security_group_ids
  parameter_group_name          = var.parameter_group_name
  engine_version                = var.engine_version
  automatic_failover_enabled    = var.automatic_failover_enabled
  multi_az_enabled              = var.multi_az_enabled
  maintenance_window            = var.maintenance_window
  notification_topic_arn        = var.notification_topic_arn
  snapshot_window               = var.snapshot_window
  snapshot_retention_limit      = var.snapshot_retention_limit
  transit_encryption_enabled    = var.transit_encryption_enabled
  at_rest_encryption_enabled    = var.at_rest_encryption_enabled

  tags = module.this.tags
}
```

#### variables.tf

Defines input variables for the component. Variables should have clear descriptions, sensible defaults where appropriate, and validation rules when needed.

```terraform
variable "instance_type" {
  type        = string
  description = "ElastiCache instance type"
  default     = "cache.t3.small"
}

variable "engine_version" {
  type        = string
  description = "Redis engine version"
  default     = "6.2"
}

variable "port" {
  type        = number
  description = "Redis port"
  default     = 6379
  validation {
    condition     = var.port > 0 && var.port < 65536
    error_message = "Port must be between 1 and 65535."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs to deploy ElastiCache into"
  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "At least one subnet ID is required."
  }
}

variable "security_group_ids" {
  type        = list(string)
  description = "Security group IDs to allow access to ElastiCache"
  default     = []
}

variable "parameter_group_name" {
  type        = string
  description = "ElastiCache parameter group name"
  default     = "default.redis6.x"
}

variable "automatic_failover_enabled" {
  type        = bool
  description = "Enable automatic failover"
  default     = true
}

variable "multi_az_enabled" {
  type        = bool
  description = "Enable Multi-AZ deployment"
  default     = true
}

variable "transit_encryption_enabled" {
  type        = bool
  description = "Enable encryption in transit"
  default     = true
}

variable "at_rest_encryption_enabled" {
  type        = bool
  description = "Enable encryption at rest"
  default     = true
}

variable "maintenance_window" {
  type        = string
  description = "Maintenance window"
  default     = "sun:05:00-sun:07:00"
}

variable "snapshot_window" {
  type        = string
  description = "Snapshot window"
  default     = "03:00-05:00"
}

variable "snapshot_retention_limit" {
  type        = number
  description = "Snapshot retention limit in days"
  default     = 7
  validation {
    condition     = var.snapshot_retention_limit >= 0 && var.snapshot_retention_limit <= 35
    error_message = "Snapshot retention limit must be between 0 and 35 days."
  }
}

variable "notification_topic_arn" {
  type        = string
  description = "SNS topic ARN for notifications"
  default     = null
}
```

#### outputs.tf

Defines output values exported by the component. Outputs should include all resource IDs, ARNs, and other values that might be needed by other components.

```terraform
output "id" {
  value       = module.this.enabled ? join("", aws_elasticache_replication_group.default.*.id) : null
  description = "ElastiCache replication group ID"
}

output "primary_endpoint_address" {
  value       = module.this.enabled ? join("", aws_elasticache_replication_group.default.*.primary_endpoint_address) : null
  description = "Primary endpoint address"
}

output "reader_endpoint_address" {
  value       = module.this.enabled ? join("", aws_elasticache_replication_group.default.*.reader_endpoint_address) : null
  description = "Reader endpoint address"
}

output "port" {
  value       = var.port
  description = "Redis port"
}

output "security_group_ids" {
  value       = var.security_group_ids
  description = "Security group IDs"
}

output "subnet_group_name" {
  value       = module.this.enabled ? join("", aws_elasticache_subnet_group.default.*.name) : null
  description = "Subnet group name"
}
```

#### provider.tf

Defines provider configuration for the component.

```terraform
provider "aws" {
  region = var.region

  # Profile is not used when running Atmos, but is useful for local testing
  profile = lookup(var.additional_tag_map, "profile", null)

  # Make it faster by skipping validation steps
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_requesting_account_id  = true
}
```

## Component Development Process

### Setting Up the Component Directory

To create a new component, start by creating a directory with the component name:

```bash
mkdir -p components/terraform/elasticache
```

### Creating the Necessary Files

Create the standard files for the component:

```bash
touch components/terraform/elasticache/README.md
touch components/terraform/elasticache/main.tf
touch components/terraform/elasticache/variables.tf
touch components/terraform/elasticache/outputs.tf
touch components/terraform/elasticache/provider.tf
```

For components with IAM policies, create a policies directory:

```bash
mkdir -p components/terraform/elasticache/policies
```

### Developing and Testing the Component

1. **Define variables** in variables.tf with appropriate descriptions, defaults, and validations.
2. **Create resources** in main.tf, referencing variables as needed.
3. **Define outputs** in outputs.tf for values that might be needed by other components.
4. **Test the component** by running it through Terraform:

```bash
cd components/terraform/elasticache
terraform init
terraform validate
terraform plan
```

### Adding Component Metadata

Create a README.md file with documentation for the component:

```markdown
# ElastiCache Component

This component provisions an ElastiCache Redis cluster in AWS.

## Usage

```yaml
components:
  terraform:
    elasticache:
      vars:
        enabled: true
        name: "redis"
        subnet_ids: ${output.vpc.private_subnet_ids}
        security_group_ids: ${output.vpc.security_group_id}
        instance_type: "cache.t3.small"
        engine_version: "6.2"
        automatic_failover_enabled: true
        multi_az_enabled: true
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| enabled | Set to false to prevent the module from creating any resources | bool | true | no |
| subnet_ids | Subnet IDs to deploy ElastiCache into | list(string) | - | yes |
| security_group_ids | Security group IDs to allow access to ElastiCache | list(string) | [] | no |
| instance_type | ElastiCache instance type | string | "cache.t3.small" | no |
| engine_version | Redis engine version | string | "6.2" | no |
| port | Redis port | number | 6379 | no |
| parameter_group_name | ElastiCache parameter group name | string | "default.redis6.x" | no |
| automatic_failover_enabled | Enable automatic failover | bool | true | no |
| multi_az_enabled | Enable Multi-AZ deployment | bool | true | no |
| transit_encryption_enabled | Enable encryption in transit | bool | true | no |
| at_rest_encryption_enabled | Enable encryption at rest | bool | true | no |
| maintenance_window | Maintenance window | string | "sun:05:00-sun:07:00" | no |
| snapshot_window | Snapshot window | string | "03:00-05:00" | no |
| snapshot_retention_limit | Snapshot retention limit in days | number | 7 | no |
| notification_topic_arn | SNS topic ARN for notifications | string | null | no |

## Outputs

| Name | Description |
|------|-------------|
| id | ElastiCache replication group ID |
| primary_endpoint_address | Primary endpoint address |
| reader_endpoint_address | Reader endpoint address |
| port | Redis port |
| security_group_ids | Security group IDs |
| subnet_group_name | Subnet group name |
```

## Catalog Integration

### Creating a Catalog Entry

Create a catalog entry for the component in the appropriate catalog file:

```yaml
# stacks/catalog/elasticache/defaults.yaml
components:
  terraform:
    elasticache:
      metadata:
        component: elasticache
        type: terraform
      vars:
        enabled: true
        instance_type: "cache.t3.small"
        engine_version: "6.2"
        port: 6379
        automatic_failover_enabled: true
        multi_az_enabled: true
        transit_encryption_enabled: true
        at_rest_encryption_enabled: true
        maintenance_window: "sun:05:00-sun:07:00"
        snapshot_window: "03:00-05:00"
        snapshot_retention_limit: 7
```

### Variables and Outputs Configuration

Catalog entries should define sensible defaults for variables, and can reference outputs from other components:

```yaml
components:
  terraform:
    elasticache:
      vars:
        enabled: true
        subnet_ids: ${output.vpc.private_subnet_ids}
        security_group_ids:
          - ${output.vpc.security_group_id}
```

### Component Dependencies

Components can depend on other components, and Atmos will ensure they are deployed in the correct order:

```yaml
components:
  terraform:
    elasticache:
      metadata:
        component: elasticache
        type: terraform
        depends_on:
          - vpc
          - securitygroup
      vars:
        # ...
```

## Environment Integration

### Environment Configuration

Environments can customize component configurations:

```yaml
# stacks/orgs/mycompany/dev/us-west-2/dev/components/elasticache.yaml
import:
  - catalog/elasticache/defaults

components:
  terraform:
    elasticache:
      vars:
        enabled: true
        name: "${tenant}-${environment}-redis"
        subnet_ids: ${output.vpc.private_subnet_ids}
        security_group_ids:
          - ${output.vpc.security_group_id}
        instance_type: "cache.t3.medium"
        multi_az_enabled: false  # Save costs in dev
```

### Stack Dependencies

Environment stacks can define dependencies between components:

```yaml
# stacks/orgs/mycompany/dev/us-west-2/dev/main.yaml
import:
  - components/vpc
  - components/securitygroup
  - components/elasticache

components:
  terraform:
    elasticache:
      metadata:
        depends_on:
          - vpc
          - securitygroup
```

### Using Mixins for Reusable Configurations

Mixins can be used to create reusable configuration patterns:

```yaml
# stacks/mixins/elasticache/production.yaml
components:
  terraform:
    elasticache:
      vars:
        instance_type: "cache.m5.large"
        multi_az_enabled: true
        automatic_failover_enabled: true
        transit_encryption_enabled: true
        at_rest_encryption_enabled: true
        snapshot_retention_limit: 14

# stacks/orgs/mycompany/prod/us-west-2/prod/components/elasticache.yaml
import:
  - catalog/elasticache/defaults
  - mixins/elasticache/production

components:
  terraform:
    elasticache:
      vars:
        enabled: true
        name: "${tenant}-${environment}-redis"
        subnet_ids: ${output.vpc.private_subnet_ids}
        security_group_ids:
          - ${output.vpc.security_group_id}
```

## Validation and Deployment

### Schema Validation

Component variables can be validated using Terraform's built-in validation functionality:

```terraform
variable "port" {
  type        = number
  description = "Redis port"
  default     = 6379
  validation {
    condition     = var.port > 0 && var.port < 65536
    error_message = "Port must be between 1 and 65535."
  }
}
```

### Component Validation

Validate the component using Atmos:

```bash
atmos terraform validate elasticache -s mycompany-dev-us-west-2-dev
```

### Deployment Process

Deploy the component using Atmos:

```bash
# Plan changes
atmos terraform plan elasticache -s mycompany-dev-us-west-2-dev

# Apply changes
atmos terraform apply elasticache -s mycompany-dev-us-west-2-dev
```

## Advanced Techniques

### Dynamic Resource Creation

Create multiple similar resources using `for_each`:

```terraform
resource "aws_elasticache_parameter_group" "custom" {
  for_each = var.custom_parameter_groups

  name        = "${module.this.id}-${each.key}"
  description = each.value.description
  family      = each.value.family

  dynamic "parameter" {
    for_each = each.value.parameters
    content {
      name  = parameter.key
      value = parameter.value
    }
  }

  tags = module.this.tags
}
```

### Conditional Resources

Create resources conditionally based on variables:

```terraform
resource "aws_elasticache_replication_group" "default" {
  count = module.this.enabled && !var.serverless_enabled ? 1 : 0

  # Standard parameters...
}

resource "aws_elasticache_serverless_cache" "serverless" {
  count = module.this.enabled && var.serverless_enabled ? 1 : 0

  engine                   = "redis"
  serverless_cache_name    = module.this.id
  description              = var.description
  security_group_ids       = var.security_group_ids
  subnet_ids               = var.subnet_ids

  daily_snapshot_time      = var.snapshot_window
  snapshot_retention_limit = var.snapshot_retention_limit

  tags = module.this.tags
}
```

### Complex Validations

Use complex validations to ensure variables meet requirements:

```terraform
variable "instance_type" {
  type        = string
  description = "ElastiCache instance type"
  default     = "cache.t3.small"

  validation {
    condition = (
      contains(["cache.t3", "cache.t4g", "cache.m5", "cache.m6g", "cache.r5", "cache.r6g", "cache.c5", "cache.c6g"], 
        split(".", var.instance_type)[0]
      )
    )
    error_message = "Instance type must be a valid ElastiCache instance type."
  }
}

variable "maintenance_window" {
  type        = string
  description = "Maintenance window"
  default     = "sun:05:00-sun:07:00"

  validation {
    condition = (
      can(regex("^(mon|tue|wed|thu|fri|sat|sun):([0-1][0-9]|2[0-3]):00-([0-1][0-9]|2[0-3]):00$", var.maintenance_window))
    )
    error_message = "Maintenance window must be in the format day:hour:minute-day:hour:minute, e.g., sun:05:00-sun:07:00."
  }
}
```

### Cross-Component References

Reference outputs from other components:

```yaml
components:
  terraform:
    elasticache:
      vars:
        subnet_ids: ${output.vpc.private_subnet_ids}
        security_group_ids:
          - ${output.securitygroup.id}
```

## Best Practices

### Resource Structure

1. **Complete Outputs**: Export all resource IDs, ARNs, and other values that might be needed by other components.
2. **Error Handling**: Use proper error handling with descriptive error messages.
3. **Modular Design**: Break complex components into smaller, reusable modules.
4. **Resource Dependencies**: Use `depends_on` to explicitly define resource dependencies.

### Security Considerations

1. **Encryption**: Enable encryption in transit and at rest by default.
2. **IAM Policies**: Use the principle of least privilege for IAM policies.
3. **Security Groups**: Create minimal security group rules.
4. **Secrets**: Use AWS Secrets Manager for sensitive values.

### Naming Conventions

1. **Resource Names**: Use `module.this.id` for resource names to ensure consistency.
2. **Variable Names**: Use descriptive variable names with consistent naming patterns.
3. **Output Names**: Use descriptive output names that clearly indicate what they represent.

### Documentation Standards

1. **README**: Every component should have a README.md with usage examples.
2. **Comments**: Use comments to explain complex logic.
3. **Variable Descriptions**: Every variable should have a clear description.
4. **Output Descriptions**: Every output should have a clear description.

## Practical Examples

### Basic Component Example (VPC)

```terraform
# main.tf
resource "aws_vpc" "this" {
  count = module.this.enabled ? 1 : 0

  cidr_block           = var.cidr_block
  enable_dns_support   = var.enable_dns_support
  enable_dns_hostnames = var.enable_dns_hostnames

  tags = module.this.tags
}

resource "aws_subnet" "public" {
  count = module.this.enabled ? length(var.availability_zones) : 0

  vpc_id                  = aws_vpc.this[0].id
  cidr_block              = cidrsubnet(var.cidr_block, 8, count.index)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    module.this.tags,
    {
      Name = "${module.this.id}-public-${var.availability_zones[count.index]}"
      Type = "Public"
    }
  )
}

resource "aws_subnet" "private" {
  count = module.this.enabled ? length(var.availability_zones) : 0

  vpc_id            = aws_vpc.this[0].id
  cidr_block        = cidrsubnet(var.cidr_block, 8, count.index + length(var.availability_zones))
  availability_zone = var.availability_zones[count.index]

  tags = merge(
    module.this.tags,
    {
      Name = "${module.this.id}-private-${var.availability_zones[count.index]}"
      Type = "Private"
    }
  )
}

# variables.tf
variable "cidr_block" {
  type        = string
  description = "CIDR block for the VPC"
  validation {
    condition     = can(cidrnetmask(var.cidr_block))
    error_message = "CIDR block must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones" {
  type        = list(string)
  description = "List of availability zones to use"
}

variable "enable_dns_support" {
  type        = bool
  description = "Enable DNS support"
  default     = true
}

variable "enable_dns_hostnames" {
  type        = bool
  description = "Enable DNS hostnames"
  default     = true
}

# outputs.tf
output "vpc_id" {
  value       = module.this.enabled ? aws_vpc.this[0].id : null
  description = "VPC ID"
}

output "public_subnet_ids" {
  value       = module.this.enabled ? aws_subnet.public[*].id : null
  description = "Public subnet IDs"
}

output "private_subnet_ids" {
  value       = module.this.enabled ? aws_subnet.private[*].id : null
  description = "Private subnet IDs"
}
```

### Intermediate Component Example (Elasticache)

See the previous examples in this guide.

### Advanced Component Example (EKS)

```terraform
# main.tf
module "eks_cluster" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 18.0"

  create                         = module.this.enabled
  cluster_name                   = module.this.id
  cluster_version                = var.kubernetes_version
  vpc_id                         = var.vpc_id
  subnet_ids                     = var.subnet_ids
  cluster_endpoint_private_access = var.endpoint_private_access
  cluster_endpoint_public_access  = var.endpoint_public_access
  cluster_enabled_log_types      = var.cluster_enabled_log_types

  cluster_addons = {
    coredns = {
      addon_version     = var.coredns_addon_version
      resolve_conflicts = "OVERWRITE"
    }
    kube-proxy = {
      addon_version     = var.kube_proxy_addon_version
      resolve_conflicts = "OVERWRITE"
    }
    vpc-cni = {
      addon_version     = var.vpc_cni_addon_version
      resolve_conflicts = "OVERWRITE"
    }
  }

  # IAM roles for service accounts
  enable_irsa = true

  # Managed node groups
  eks_managed_node_groups = var.managed_node_groups

  # Self-managed node groups
  self_managed_node_groups = var.self_managed_node_groups

  # Fargate profiles
  fargate_profiles = var.fargate_profiles

  # AWS auth
  manage_aws_auth_configmap = true
  aws_auth_roles            = var.map_roles
  aws_auth_users            = var.map_users

  tags = module.this.tags
}

# Outputs, variables, etc.
```

## Troubleshooting and FAQs

### Common Issues and Solutions

1. **Missing Required Variables**
   - Error: `Error: Missing required argument`
   - Solution: Ensure all required variables are provided in the component configuration.

2. **Invalid Variable Values**
   - Error: `Error: Invalid value for variable`
   - Solution: Check the validation rules in variables.tf and ensure provided values meet the requirements.

3. **Resource Already Exists**
   - Error: `Error: Resource already exists`
   - Solution: Use a different name or import the existing resource into the Terraform state.

### Validation Errors

1. **Schema Validation Errors**
   - Use `terraform validate` to check for schema errors.
   - Check variable definitions for proper type constraints and validation rules.

2. **Policy Validation Errors**
   - Ensure IAM policies follow AWS best practices.
   - Use policy simulators to test policies before applying them.

### Deployment Failures

1. **Permission Issues**
   - Ensure the deployment role has the necessary permissions.
   - Check IAM policy limits and constraints.

2. **Resource Limits**
   - Check AWS service limits for the account.
   - Request limit increases if necessary.

3. **Dependency Issues**
   - Ensure all dependencies are properly defined.
   - Check for circular dependencies.

4. **State Locking Issues**
   - Check for abandoned locks in the DynamoDB table.
   - Release locks manually if necessary.

---

This guide covers the essential aspects of Terraform components in the Atmos framework. For additional information, refer to the Terraform documentation, AWS documentation, and Atmos documentation.