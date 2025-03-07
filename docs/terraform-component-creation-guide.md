# Creating and Integrating New Components in Atmos

_Last Updated: March 7, 2025_

This guide provides a step-by-step process for creating a new component in Atmos, adding it to the component catalog, and integrating it into an environment. We'll use a practical example of adding an AWS Elasticache (Redis) component to illustrate the entire workflow, following the latest Atmos design patterns and best practices.

## Table of Contents

1. [Component Creation](#1-component-creation)
   - [File Structure](#file-structure)
   - [Component Development](#component-development)
   - [Component Metadata](#component-metadata)
   - [Variable Validation](#variable-validation)
2. [Catalog Integration](#2-catalog-integration)
   - [Creating a Catalog Entry](#creating-a-catalog-entry)
   - [Variables and Outputs](#variables-and-outputs)
   - [Component Dependencies](#component-dependencies)
3. [Environment Integration](#3-environment-integration)
   - [Environment Configuration](#environment-configuration)
   - [Stack Dependencies](#stack-dependencies)
   - [Using Mixins](#using-mixins)
4. [Validation and Deployment](#4-validation-and-deployment)
   - [Schema Validation](#schema-validation)
   - [Validating the Component](#validating-the-component)
   - [Deploying the Component](#deploying-the-component)
   - [Compliance Checking](#compliance-checking)
5. [Advanced Patterns](#5-advanced-patterns)
   - [Component Dependencies](#component-dependencies-1)
   - [Cross-Component References](#cross-component-references)
   - [Environment-Specific Configurations](#environment-specific-configurations)
   - [Conditional Resources](#conditional-resources)

## 1. Component Creation

### File Structure

First, create the appropriate directory and files for your new component, following the standard component structure:

```bash
# Create the component directory (use singular form without hyphens)
mkdir -p components/terraform/elasticache

# Create the necessary files
touch components/terraform/elasticache/main.tf
touch components/terraform/elasticache/variables.tf
touch components/terraform/elasticache/outputs.tf
touch components/terraform/elasticache/locals.tf
touch components/terraform/elasticache/provider.tf
touch components/terraform/elasticache/README.md
mkdir -p components/terraform/elasticache/policies
```

You can also use the template directory as a starting point:

```bash
# Copy from the template directory
cp -r templates/terraform-component/* components/terraform/elasticache/
```

### Component Development

Each component should include the following key files and follow these best practices:

#### README.md

Start with a comprehensive README.md file that documents your component:

```markdown
# Elasticache Component

This component provisions an AWS Elasticache Redis cluster with appropriate security groups, subnet groups, and parameter groups.

## Usage

```hcl
module "elasticache" {
  source = "../../components/terraform/elasticache"

  name        = "app-cache"
  engine      = "redis"
  node_type   = "cache.t3.small"
  subnet_ids  = ["subnet-1", "subnet-2", "subnet-3"]
  vpc_id      = "vpc-123456"
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name of the cluster | string | n/a | yes |
| engine | Cache engine (redis or memcached) | string | `"redis"` | no |
| engine_version | Version of the cache engine | string | `"6.x"` | no |
| node_type | Instance type for the cache nodes | string | n/a | yes |
| subnet_ids | List of VPC subnet IDs | list(string) | n/a | yes |
| vpc_id | VPC ID | string | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| cluster_id | The ID of the Elasticache cluster |
| cluster_endpoint | The endpoint of the Elasticache cluster |
| security_group_id | The ID of the security group |
```

#### 1. provider.tf

```hcl
provider "aws" {
  region = var.region

  # Tags to apply to all AWS resources by default
  default_tags {
    tags = var.tags
  }
  
  # Use assume_role if provided
  dynamic "assume_role" {
    for_each = var.assume_role_arn != null && var.assume_role_arn != "" ? [1] : []
    content {
      role_arn = var.assume_role_arn
      session_name = "${var.namespace}-elasticache"
    }
  }
}

terraform {
  required_version = ">= 1.11.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}
```

#### 2. locals.tf

```hcl
locals {
  # Create a name prefix for resources with standard format
  name_prefix = "${var.namespace}-${var.environment}-${var.name}"
  
  # Default ElastiCache settings by environment type
  default_settings = {
    production = {
      multi_az_enabled = true
      automatic_failover_enabled = true
      maintenance_window = "sun:05:00-sun:07:00"
      snapshot_retention_limit = 7
      at_rest_encryption_enabled = true
    },
    development = {
      multi_az_enabled = false
      automatic_failover_enabled = false
      maintenance_window = "sun:07:00-sun:09:00"
      snapshot_retention_limit = 1
      at_rest_encryption_enabled = true
    }
  }
  
  # Merge environment-specific settings with user-provided settings
  settings = merge(
    lookup(local.default_settings, var.environment_type, local.default_settings["development"]),
    var.override_settings
  )
}

#### 3. variables.tf

```hcl
variable "region" {
  type        = string
  description = "AWS region"
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "The region must be a valid AWS region (e.g., us-east-1, eu-west-2)."
  }
}

variable "enabled" {
  type        = bool
  description = "Set to false to prevent the module from creating any resources"
  default     = true
}

variable "namespace" {
  type        = string
  description = "Namespace (e.g., tenant name)"
}

variable "environment" {
  type        = string
  description = "Environment name"
}

variable "environment_type" {
  type        = string
  description = "Environment type (e.g., development, production)"
  default     = "development"
  validation {
    condition     = contains(["development", "staging", "production"], var.environment_type)
    error_message = "Valid values for environment_type: development, staging, production."
  }
}

variable "name" {
  type        = string
  description = "Name of the ElastiCache cluster"
}

variable "engine" {
  type        = string
  description = "Cache engine (redis or memcached)"
  default     = "redis"
  validation {
    condition     = contains(["redis", "memcached"], var.engine)
    error_message = "Valid values for engine: redis, memcached."
  }
}

variable "engine_version" {
  type        = string
  description = "Version of the cache engine"
  default     = "6.x"
}

variable "node_type" {
  type        = string
  description = "Instance type for the cache nodes"
  validation {
    condition     = can(regex("^cache\\.[a-z0-9]+\\.[a-z0-9]+$", var.node_type))
    error_message = "The node_type must be a valid ElastiCache node type (e.g., cache.t3.small)."
  }
}

variable "assume_role_arn" {
  type        = string
  description = "ARN of the IAM role to assume"
  default     = null
}

variable "enabled" {
  type        = bool
  description = "Whether to create the resources. Set to false to avoid creating resources"
  default     = true
}

variable "cluster_id" {
  type        = string
  description = "ID for the ElastiCache cluster"
}

variable "engine" {
  type        = string
  description = "The name of the cache engine to be used"
  default     = "redis"
  validation {
    condition     = contains(["redis", "memcached"], var.engine)
    error_message = "Engine must be either 'redis' or 'memcached'."
  }
}

variable "node_type" {
  type        = string
  description = "The instance class to be used"
  default     = "cache.t3.small"
}

variable "num_cache_nodes" {
  type        = number
  description = "Number of cache nodes"
  default     = 1
}

variable "port" {
  type        = number
  description = "ElastiCache port"
  default     = 6379
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs for the ElastiCache subnet group"
}

variable "security_group_ids" {
  type        = list(string)
  description = "List of security group IDs to associate with the cluster"
  default     = []
}

variable "parameter_group_name" {
  type        = string
  description = "Name of the parameter group to associate with the cluster"
  default     = null
}

variable "at_rest_encryption_enabled" {
  type        = bool
  description = "Whether to enable encryption at rest"
  default     = true
}

variable "transit_encryption_enabled" {
  type        = bool
  description = "Whether to enable encryption in transit"
  default     = true
}

variable "auth_token" {
  type        = string
  description = "Auth token for password protecting redis, `transit_encryption_enabled` must be set to `true`"
  default     = null
  sensitive   = true
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to add to all resources"
  default     = {}
}
```

#### 3. main.tf

```hcl
locals {
  enabled = var.enabled
  name    = var.cluster_id
  tags = merge(
    var.tags,
    {
      Name      = local.name
      Component = "ElastiCache"
      ManagedBy = "Terraform"
    }
  )
}

resource "aws_elasticache_subnet_group" "this" {
  count = local.enabled ? 1 : 0

  name       = "${local.name}-subnet-group"
  subnet_ids = var.subnet_ids
  
  tags = local.tags
}

resource "aws_elasticache_parameter_group" "this" {
  count = local.enabled && var.parameter_group_name == null ? 1 : 0

  name   = "${local.name}-params"
  family = var.engine == "redis" ? "redis6.x" : "memcached1.6"
  
  # Redis specific parameters
  dynamic "parameter" {
    for_each = var.engine == "redis" ? [1] : []
    content {
      name  = "maxmemory-policy"
      value = "volatile-lru"
    }
  }
  
  tags = local.tags
}

resource "aws_elasticache_replication_group" "redis" {
  count = local.enabled && var.engine == "redis" ? 1 : 0

  replication_group_id       = local.name
  description                = "Redis cluster for ${local.name}"
  node_type                  = var.node_type
  port                       = var.port
  num_cache_clusters         = var.num_cache_nodes
  parameter_group_name       = var.parameter_group_name != null ? var.parameter_group_name : aws_elasticache_parameter_group.this[0].name
  subnet_group_name          = aws_elasticache_subnet_group.this[0].name
  security_group_ids         = var.security_group_ids
  at_rest_encryption_enabled = var.at_rest_encryption_enabled
  transit_encryption_enabled = var.transit_encryption_enabled
  auth_token                 = var.transit_encryption_enabled ? var.auth_token : null

  lifecycle {
    precondition {
      condition     = !var.transit_encryption_enabled || var.auth_token != null
      error_message = "Authentication token is required when transit encryption is enabled."
    }
  }
  
  tags = local.tags
}

resource "aws_elasticache_cluster" "memcached" {
  count = local.enabled && var.engine == "memcached" ? 1 : 0

  cluster_id           = local.name
  engine               = "memcached"
  node_type            = var.node_type
  num_cache_nodes      = var.num_cache_nodes
  parameter_group_name = var.parameter_group_name != null ? var.parameter_group_name : aws_elasticache_parameter_group.this[0].name
  port                 = var.port
  subnet_group_name    = aws_elasticache_subnet_group.this[0].name
  security_group_ids   = var.security_group_ids
  
  tags = local.tags
}
```

#### 4. outputs.tf

```hcl
output "redis_endpoint" {
  description = "Redis primary endpoint"
  value       = var.engine == "redis" && var.enabled ? aws_elasticache_replication_group.redis[0].primary_endpoint_address : null
}

output "memcached_endpoint" {
  description = "Memcached endpoint"
  value       = var.engine == "memcached" && var.enabled ? aws_elasticache_cluster.memcached[0].configuration_endpoint : null
}

output "cluster_endpoint" {
  description = "Cluster endpoint - either redis or memcached depending on engine"
  value       = var.engine == "redis" && var.enabled ? aws_elasticache_replication_group.redis[0].primary_endpoint_address : (
                var.engine == "memcached" && var.enabled ? aws_elasticache_cluster.memcached[0].configuration_endpoint : null
              )
}

output "port" {
  description = "Port the cluster is listening on"
  value       = var.port
}

output "subnet_group_name" {
  description = "Name of the created subnet group"
  value       = var.enabled ? aws_elasticache_subnet_group.this[0].name : null
}

output "parameter_group_name" {
  description = "Name of the parameter group used"
  value       = var.enabled && var.parameter_group_name == null ? aws_elasticache_parameter_group.this[0].name : var.parameter_group_name
}

output "security_group_ids" {
  description = "Security groups associated with the cluster"
  value       = var.security_group_ids
}
```

### Component Metadata

Add component metadata to enable better documentation and discovery:

```hcl
# In main.tf

module "elasticache" {
  source = "aws-modules/elasticache/aws"
  # ... module parameters ...

  # Apply standard tagging
  tags = merge(
    var.tags,
    {
      Name        = local.name_prefix
      Environment = var.environment
      Component   = "ElastiCache"
      ManagedBy   = "terraform"
    }
  )
}

# Metadata can be used by documentation tools and other automation
locals {
  metadata = {
    component   = "elasticache"
    version     = "1.0.0"
    description = "ElastiCache Redis cluster"
    category    = "database"
    namespace   = "cache"
  }
}
```

### Variable Validation

Apply thorough validation to prevent errors:

```hcl
variable "subnet_ids" {
  type        = list(string)
  description = "List of VPC subnet IDs"
  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "At least one subnet ID must be provided."
  }
}

variable "security_group_rules" {
  type = list(object({
    type        = string
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
    description = string
  }))
  description = "Additional security group rules"
  default     = []
  
  validation {
    condition = alltrue([
      for rule in var.security_group_rules :
      contains(["ingress", "egress"], rule.type) &&
      rule.from_port >= 0 && rule.from_port <= 65535 &&
      rule.to_port >= 0 && rule.to_port <= 65535 &&
      contains(["tcp", "udp", "icmp", "-1"], rule.protocol)
    ])
    error_message = "Security group rules must have valid values for type, ports, and protocol."
  }
}
```

## 2. Catalog Integration

### Creating a Catalog Entry

After developing the component, integrate it into the Atmos catalog by creating a catalog file:

```bash
# Create a catalog file for the component
touch stacks/catalog/elasticache.yaml
```

Edit `stacks/catalog/elasticache.yaml` with the following content:

```yaml
name: elasticache
description: "Redis/Memcached ElastiCache configuration"

components:
  terraform:
    elasticache:
      metadata:
        component: elasticache
        type: abstract
        version: "1.0.0"
        description: "ElastiCache Redis/Memcached cluster configuration"
        category: "database"
        namespace: "cache"
      depends_on:
        - vpc
        - securitygroup
      vars:
        enabled: true
        region: ${region}
        cluster_id: "${tenant}-${environment}-cache"
        engine: "redis"
        node_type: "cache.t3.small"
        num_cache_nodes: 1
        port: 6379
        subnet_ids: ${subnet_ids}  # Reference from network component
        security_group_ids: ${security_group_ids} # Reference from network component
        at_rest_encryption_enabled: true
        transit_encryption_enabled: true
        auth_token: "${ssm:/elasticache/${environment}/auth_token}" # Store in SSM

      # Define common tags
      tags:
        Tenant: ${tenant}
        Account: ${account}
        Environment: ${environment}
        Component: "ElastiCache"
        ManagedBy: "Terraform"

      # Terraform backend configuration
      settings:
        terraform:
          backend:
            s3:
              bucket: ${tenant}-terraform-state
              key: ${account}/${environment}/elasticache/terraform.tfstate
              region: ${region}
              role_arn: arn:aws:iam::${management_account_id}:role/${tenant}-terraform-backend-role
              dynamodb_table: ${tenant}-terraform-locks

      # Provider configuration
      providers:
        aws:
          region: ${region}

      # Define common outputs
      outputs:
        cluster_endpoint:
          description: "Endpoint of the ElastiCache cluster"
          value: ${output.cluster_endpoint}
        port:
          description: "Port of the ElastiCache cluster"
          value: ${output.port}
```

### Variables and Outputs

To use variables from other components, ensure those components are deployed before your new component and have the appropriate outputs defined.

### Component Dependencies

Explicitly define component dependencies in your catalog YAML:

```yaml
components:
  terraform:
    elasticache:
      depends_on:
        - vpc          # Depends on VPC for subnet IDs
        - securitygroup # Depends on security groups
```

This ensures components are deployed in the correct order and enables dependency resolution at runtime.

## 3. Environment Integration

### Environment Configuration

Create an environment-specific configuration file for your component:

```bash
# Create an environment configuration file
touch stacks/account/dev/testenv-01/elasticache.yaml
```

Edit `stacks/account/dev/testenv-01/elasticache.yaml` with the following content:

```yaml
import:
  - mixins/development  # Environment type settings
  - catalog/elasticache

vars:
  account: dev
  environment: testenv-01
  region: eu-west-2
  tenant: fnx

  # Reference network resources
  subnet_ids: ${output.vpc.private_subnet_ids}
  security_group_ids: ["${output.securitygroup.cache_sg_id}"]
  
  # ElastiCache specific settings
  cluster_id: "fnx-dev-testenv-01-redis"
  engine: "redis"
  node_type: "cache.t3.micro"  # Smaller instance for dev
  num_cache_nodes: 1
  
  # Disable encryption for dev
  at_rest_encryption_enabled: false
  transit_encryption_enabled: false
  auth_token: null
  
# Define dependencies
dependencies:
  - network
  - securitygroup

tags:
  Team: "DevOps"
  CostCenter: "IT"
  Project: "Infrastructure"
  Environment: "Development"
```

### Stack Dependencies

The `dependencies` section in the environment configuration ensures that dependent components are deployed first. This is important for resources like `subnet_ids` and `security_group_ids` that are referenced from other components.

## 4. Validation and Deployment

### Using Mixins

Environment-type mixins provide reusable configuration fragments:

```yaml
# in stacks/mixins/development.yaml
name: development
description: "Development environment settings mixin"

vars:
  # Development-specific variables
  environment_type: "development"
  high_availability: false
  monitoring_enabled: false
  is_production: false
  
  # ElastiCache-specific settings
  elasticache_settings:
    multi_az_enabled: false
    automatic_failover_enabled: false
    node_type: "cache.t3.micro"
    maintenance_window: "sun:07:00-sun:09:00"
    snapshot_retention_limit: 1
```

Then in your environment stack:

```yaml
# Environment configuration
components:
  terraform:
    elasticache:
      vars:
        # Override with environment-specific settings
        node_type: ${elasticache_settings.node_type}
        multi_az_enabled: ${elasticache_settings.multi_az_enabled}
```

### Schema Validation

First, validate your stack conforms to the JSON schema:

```bash
# Validate stacks
atmos validate stacks --stack fnx-dev-testenv-01
```

### Validating the Component

Before deploying the component, validate it:

```bash
# Validate the component
atmos terraform validate elasticache -s fnx-dev-testenv-01
```

### Deploying the Component

Deploy the component:

```bash
# Plan the changes
atmos terraform plan elasticache -s fnx-dev-testenv-01

# Apply the changes
atmos terraform apply elasticache -s fnx-dev-testenv-01
```

You can also use the environment workflow to apply all components including your new one:

```bash
# Apply the entire environment
atmos workflow apply-environment tenant=fnx account=dev environment=testenv-01
```

### Compliance Checking

Run compliance checks on your new component and environment:

```bash
# Check compliance
atmos workflow compliance-check tenant=fnx account=dev environment=testenv-01
```

This will validate:
- Resource encryption settings
- Security configurations
- Compliance with organizational policies
- Schema validity
- Best practice adherence

## 5. Advanced Patterns

### Component Dependencies

Explicit dependencies can be managed in multiple ways:

1. **Stack Dependencies**: As shown in the environment configuration

```yaml
dependencies:
  - network
  - securitygroup
```

2. **Terraform Dependencies**: Using the `depends_on` attribute in Terraform

```hcl
resource "aws_elasticache_replication_group" "redis" {
  # Resource definition...
  
  depends_on = [
    aws_elasticache_subnet_group.this,
    aws_iam_role_policy_attachment.elasticache_policy
  ]
}
```

3. **Explicit Waiting**: Using `time_sleep` for race condition prevention

```hcl
resource "time_sleep" "wait_for_security_groups" {
  count = var.enabled ? 1 : 0
  
  depends_on = [
    var.security_group_ids
  ]
  
  create_duration = "10s"
}

resource "aws_elasticache_replication_group" "redis" {
  # Resource definition...
  
  depends_on = [
    time_sleep.wait_for_security_groups
  ]
}
```

### Cross-Component References

Reference outputs from other components in your catalog or environment configurations:

```yaml
# From another component's output
subnet_ids: ${output.vpc.private_subnet_ids}

# Access outputs directly in Terraform (if using Terragrunt)
security_group_id = dependency.securitygroup.outputs.cache_sg_id
```

### Environment-Specific Configurations

Use conditionals to apply environment-specific settings:

```yaml
# In the catalog definition
node_type: ${env:ELASTICACHE_NODE_TYPE, "cache.t3.small"}

# Or using environment-specific overrides
node_type: ${node_type_map[environment]}

# With a variable map
node_type_map:
  dev: "cache.t3.micro"
  staging: "cache.t3.small"
  prod: "cache.m5.large"
```

### Conditional Resources

Use conditionals to create or not create resources based on environment:

```hcl
# In main.tf
resource "aws_elasticache_replication_group" "redis" {
  count = var.enabled && var.engine == "redis" ? 1 : 0
  
  # Resource definition...
}

# In variables.tf
variable "enabled" {
  type    = bool
  default = true
}

# In stack yaml
enabled: ${is_production || high_availability}
```

You can also conditionally configure entire components:

```yaml
# In stack file
components:
  terraform:
    elasticache:
      vars:
        # Only enable encryption in production
        at_rest_encryption_enabled: ${is_production}
        transit_encryption_enabled: ${is_production}
        
        # Conditionally set auth token
        auth_token: ${is_production ? ssm:/elasticache/auth_token : ""}
```

---

By following this guide, you can efficiently create new components using the latest Atmos design patterns. The components will be properly validated, dependency-aware, and follow best practices for infrastructure as code. Remember to leverage mixins for environment types, use explicit dependencies, and run compliance checks regularly.