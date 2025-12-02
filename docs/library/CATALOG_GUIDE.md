# Component Catalog Guide

This guide explains how to use the Terraform module library and component catalog system in the tf-atmos project.

## Table of Contents

1. [Overview](#overview)
2. [Catalog Structure](#catalog-structure)
3. [Searching Modules](#searching-modules)
4. [Using Modules](#using-modules)
5. [Blueprint Templates](#blueprint-templates)
6. [Creating New Modules](#creating-new-modules)
7. [Best Practices](#best-practices)

## Overview

The component catalog provides a centralized, searchable library of Terraform modules organized by category. It includes:

- **24 Production-Ready Modules**: VPC, EKS, RDS, Lambda, and more
- **7 Blueprint Templates**: Pre-configured architecture patterns
- **Atmos Workflows**: Automated discovery and management
- **CLI Tools**: Search, discovery, and composition utilities

### Key Benefits

- **Discoverability**: Find modules quickly by name, category, or use case
- **Consistency**: All modules follow the same standards and patterns
- **Composition**: Combine modules into complete infrastructure stacks
- **Documentation**: Each module includes detailed documentation

## Catalog Structure

```
stacks/catalog/_library/
├── catalog.yaml           # Category definitions and metadata
├── module-registry.yaml   # Comprehensive module registry
└── templates/             # Blueprint stack templates
    ├── web-app-stack.yaml
    ├── microservices-stack.yaml
    ├── serverless-api-stack.yaml
    ├── data-lake-stack.yaml
    ├── streaming-pipeline-stack.yaml
    ├── ml-platform-stack.yaml
    └── saas-multi-tenant-stack.yaml
```

### Categories

Modules are organized into the following categories:

| Category | Description |
|----------|-------------|
| `foundations/networking` | VPC, subnets, routing |
| `foundations/security` | Security groups, NACLs |
| `foundations/identity` | IAM roles and policies |
| `compute/containers` | EKS, ECS |
| `compute/serverless` | Lambda |
| `compute/virtual-machines` | EC2 |
| `data/databases` | RDS |
| `data/storage` | S3, Backup |
| `integration/api-management` | API Gateway |
| `observability/metrics` | CloudWatch, Monitoring |
| `security/secrets` | Secrets Manager |
| `security/certificates` | ACM |
| `dns/dns-management` | Route53 |

## Searching Modules

### Using Atmos Workflows

```bash
# List all available modules
atmos workflow list-modules -f workflows/library-management.yaml

# Search by keyword
atmos workflow search-modules -f workflows/library-management.yaml \
  -var query="kubernetes"

# List modules in a category
atmos workflow list-by-category -f workflows/library-management.yaml \
  -var category="compute/containers"

# Show detailed module information
atmos workflow module-info -f workflows/library-management.yaml \
  -var module="eks"
```

### Using CLI Script

```bash
# Search modules
./scripts/library/module-search.sh search vpc

# List all modules
./scripts/library/module-search.sh list

# List by category
./scripts/library/module-search.sh list foundations/networking

# Get module details
./scripts/library/module-search.sh info eks

# Show dependencies
./scripts/library/module-search.sh deps rds

# Get cost estimate
./scripts/library/module-search.sh cost eks

# Get recommendations
./scripts/library/module-search.sh recommend web-app
```

## Using Modules

### 1. Find the Module

```bash
./scripts/library/module-search.sh search database
```

### 2. Review Module Information

```bash
./scripts/library/module-search.sh info rds
```

Output includes:
- Description and features
- Cost estimates
- Dependencies
- Required inputs
- Available outputs

### 3. Add to Stack Configuration

```yaml
# stacks/orgs/fnx/dev/us-east-2/testenv-01/components/infrastructure.yaml
import:
  - catalog/infrastructure/defaults  # Import catalog defaults

components:
  terraform:
    rds:
      vars:
        enabled: true
        identifier: "fnx-dev-app-db"
        engine: "postgres"
        engine_version: "15.4"
        instance_class: "db.t3.medium"
        allocated_storage: 50
        multi_az: false
```

### 4. Deploy

```bash
atmos terraform plan rds -s fnx-dev-eu-west-2-testenv-01
atmos terraform apply rds -s fnx-dev-eu-west-2-testenv-01
```

## Blueprint Templates

Blueprints are pre-configured stacks for common architecture patterns.

### Available Blueprints

| Blueprint | Description | Use Case |
|-----------|-------------|----------|
| `web-app-stack` | 3-tier web application | Traditional web apps, CMS |
| `microservices-stack` | Microservices platform | Distributed systems |
| `serverless-api-stack` | Serverless REST API | APIs, backends |
| `data-lake-stack` | Analytics data lake | Data analytics, BI |
| `streaming-pipeline-stack` | Real-time streaming | Event processing |
| `ml-platform-stack` | Machine learning | ML/AI workloads |
| `saas-multi-tenant-stack` | Multi-tenant SaaS | B2B SaaS platforms |

### Using Blueprints

1. **Review Blueprint**:
```bash
atmos workflow blueprint-info -f workflows/library-management.yaml \
  -var blueprint="web-app-stack"
```

2. **Generate Stack**:
```bash
./scripts/library/generate-stack.sh web-app-stack fnx dev
```

3. **Customize**: Edit the generated stack file to match your requirements

4. **Deploy**: Use Atmos workflows to deploy the stack

### Blueprint Components

Each blueprint includes:
- Pre-configured component dependencies
- Sensible defaults for the use case
- Security best practices
- Monitoring and alerting
- Cost optimization settings

Example: `web-app-stack` includes:
```
vpc -> securitygroup -> eks -> rds -> monitoring
                    |-> eks-addons
```

## Creating New Modules

### 1. Create Component Directory

```bash
mkdir -p components/terraform/my-module
cd components/terraform/my-module
```

### 2. Create Terraform Files

```hcl
# main.tf
resource "aws_example" "this" {
  # ...
}

# variables.tf
variable "enabled" {
  description = "Enable/disable the module"
  type        = bool
  default     = true
}

# outputs.tf
output "id" {
  description = "Resource ID"
  value       = aws_example.this.id
}
```

### 3. Add to Module Registry

Edit `stacks/catalog/_library/module-registry.yaml`:

```yaml
modules:
  my-module:
    name: "My Module"
    display_name: "My Custom Module"
    category: "foundations/networking"
    version: "1.0.0"
    maturity: "beta"
    complexity: "basic"
    description: "Description of what this module does"
    short_description: "Short description"
    features:
      - Feature 1
      - Feature 2
    cost_estimate:
      minimum: "$10/month"
      typical: "$50/month"
      maximum: "$200/month"
    dependencies:
      - vpc
    inputs:
      - name: "enabled"
        type: "bool"
        description: "Enable/disable"
        default: true
    outputs:
      - name: "id"
        description: "Resource ID"
    deployment_time: "5-10 minutes"
    tags:
      - "custom"
      - "networking"
    author: "Your Name"
    last_updated: "2025-12-02"
```

### 4. Create Catalog Entry

Create `stacks/catalog/my-module/defaults.yaml`:

```yaml
---
name: my-module
description: "My custom module"

import:
  - catalog/_base/defaults

components:
  terraform:
    my-module:
      metadata:
        component: my-module
        type: abstract
        version: "1.0.0"
      vars:
        enabled: true
        # Default configuration
```

### 5. Validate Module

```bash
atmos workflow validate-module -f workflows/library-management.yaml \
  -var module="my-module"
```

### 6. Generate Documentation

```bash
terraform-docs markdown components/terraform/my-module > \
  components/terraform/my-module/README.md
```

## Best Practices

### Module Design

1. **Single Responsibility**: Each module should do one thing well
2. **Parameterized**: Use variables for all configurable values
3. **Documented**: Include descriptions for all variables and outputs
4. **Validated**: Add validation rules for inputs
5. **Secure**: Follow security best practices by default

### Naming Conventions

- Module names: `lowercase-with-hyphens`
- Variable names: `snake_case`
- Output names: `snake_case`
- Resource names: `${local.name_prefix}-resource`

### Dependencies

- Minimize dependencies between modules
- Document all dependencies clearly
- Use outputs to pass data between modules
- Avoid circular dependencies

### Cost Awareness

- Include cost estimates in module registry
- Use lifecycle rules for storage
- Enable auto-scaling where appropriate
- Tag resources for cost allocation

### Security

- Encrypt data at rest and in transit
- Use least-privilege IAM policies
- Enable logging and monitoring
- Keep secrets in Secrets Manager

## Atmos Workflow Reference

| Workflow | Description |
|----------|-------------|
| `list-modules` | List all modules |
| `list-categories` | List module categories |
| `list-by-category` | List modules in category |
| `search-modules` | Search modules |
| `module-info` | Show module details |
| `module-inputs` | Show module inputs |
| `module-outputs` | Show module outputs |
| `module-dependencies` | Show dependencies |
| `module-cost` | Show cost estimate |
| `list-blueprints` | List blueprint templates |
| `blueprint-info` | Show blueprint details |
| `blueprint-components` | List blueprint components |
| `validate-module` | Validate a module |
| `validate-all-modules` | Validate all modules |
| `lint-module` | Lint a module |
| `security-scan-module` | Security scan |
| `generate-docs` | Generate documentation |
| `catalog-stats` | Show catalog statistics |
| `recommend-modules` | Get module recommendations |
| `generate-stack` | Generate stack from blueprint |
| `show-dependency-graph` | Show dependency tree |

## Troubleshooting

### Module Not Found

```bash
# Check if module exists
./scripts/library/module-search.sh list | grep my-module

# Verify component directory
ls components/terraform/my-module/
```

### Validation Errors

```bash
# Validate specific module
cd components/terraform/my-module
terraform init -backend=false
terraform validate
```

### Dependency Issues

```bash
# Check dependency graph
./scripts/library/dependency-graph.sh

# Show module dependencies
./scripts/library/module-search.sh deps my-module
```

## Support

For questions or issues:
1. Check this documentation
2. Review module registry: `stacks/catalog/_library/module-registry.yaml`
3. Check catalog structure: `stacks/catalog/_library/catalog.yaml`
4. Review Atmos workflows: `workflows/library-management.yaml`
