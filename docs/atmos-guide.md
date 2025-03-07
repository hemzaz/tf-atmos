# Atmos Framework Overview

_Last Updated: March 7, 2025_

This document provides a comprehensive overview of the Atmos framework, its architecture, latest design patterns, and how it's used to manage infrastructure as code with Terraform.

## Table of Contents

- [Introduction](#introduction)
- [Architecture](#architecture)
- [Key Concepts](#key-concepts)
- [Design Patterns](#design-patterns)
- [Installation](#installation)
- [Basic Usage](#basic-usage)
- [Advanced Usage](#advanced-usage)
- [Debugging and Troubleshooting](#debugging-and-troubleshooting)
- [Best Practices](#best-practices)
- [Reference](#reference)

## Introduction

Atmos is an orchestration tool designed to manage infrastructure as code across complex multi-account, multi-region environments. It provides a layer of abstraction over Terraform that simplifies management of infrastructure by:

- Organizing configurations in a hierarchical structure
- Providing variable inheritance and overrides
- Supporting cross-component references
- Enabling workflow automation and standardization
- Facilitating environment-specific configurations
- Implementing component dependencies and validation

Atmos is particularly well-suited for organizations with multiple AWS accounts (e.g., development, staging, production) and teams that need to manage infrastructure consistently across these accounts.

## Architecture

Atmos uses a structured approach to organize infrastructure code:

```
└── Project Root
    ├── atmos.yaml              # Atmos configuration
    ├── components/             # Terraform components
    │   └── terraform/          # Terraform modules
    ├── stacks/                 # Stack configurations
    │   ├── catalog/            # Reusable component configurations
    │   ├── account/            # Account-specific configurations
    │   ├── mixins/             # Reusable configuration fragments
    │   └── schemas/            # JSON schemas for validation
    ├── templates/              # Component templates
    └── workflows/              # Custom workflows
```

The architecture follows these principles:

1. **Separation of concerns** - Components (code) are separated from configurations (variables)
2. **Hierarchical organization** - Configurations cascade from general to specific
3. **Single source of truth** - All configurations managed in one repository
4. **Workflow standardization** - Common operations defined as workflows
5. **Version control** - All code and configurations managed with Git
6. **Validation and compliance** - Schema validation for configurations

## Key Concepts

### Components

Components are the building blocks of your infrastructure. In Atmos, a component is typically a Terraform module that defines a specific piece of infrastructure (e.g., VPC, EKS cluster, RDS instance).

Components are stored in the `components/terraform/` directory and contain:
- Terraform code (.tf files)
- Documentation (README.md)
- IAM policies (in the policies/ directory)
- Tests (optional)

Each component should include:
- Detailed metadata (component name, type, version, description)
- Clear dependency information
- Comprehensive variable validation
- Well-documented outputs

### Stacks

Stacks define configurations for components across different environments. They are organized in a hierarchical structure:

- **Catalog** (`stacks/catalog/`) - Base configurations for components
- **Account** (`stacks/account/`) - Account and environment-specific configurations
- **Mixins** (`stacks/mixins/`) - Reusable configuration fragments

Stacks use a hierarchical inheritance model:

1. Mixins provide environment-type configurations (e.g., production, development)
2. Catalog defines base component configurations
3. Account-specific configuration inherits and overrides catalog, with environment-specific settings

### Stack Metadata

Stacks can include metadata to provide additional context:

```yaml
metadata:
  description: "Development environment in EU region"
  owner: "DevOps Team"
  version: "1.0.0"
  stage: "dev"
  compliance:
    hipaa: false
    pci: false
    gdpr: true
```

### Component Metadata

Components should include rich metadata:

```yaml
metadata:
  component: "eks"
  type: "abstract"
  version: "1.2.0"
  description: "EKS Kubernetes cluster configuration"
  category: "container-orchestration"
  namespace: "k8s"
```

### Variables

Atmos provides a powerful variable system that supports:

- **Variable inheritance** - Inherited from more general to more specific configurations
- **Variable overrides** - More specific configurations override general ones
- **Context variables** - `tenant`, `account`, `environment`, `region`, etc.
- **Special expressions** - For advanced variable processing
- **Default values with fallbacks** - `${variable_name | default("default_value")}`

Example variable reference: `${output.vpc.vpc_id}`

### Workflows

Workflows are predefined sequences of commands that automate common tasks. They are defined in YAML files in the `workflows/` directory.

Example workflow:
```yaml
name: compliance-check
description: "Check infrastructure compliance"
workflows:
  check:
    description: "Run compliance checks on a specific environment"
    steps:
    - run:
        command: |
          echo "Running compliance checks for ${tenant}-${account}-${environment}"
          atmos validate stacks --stack ${tenant}-${account}-${environment}
```

## Design Patterns

Atmos supports several design patterns for effectively managing infrastructure:

### Abstract Component Pattern

Define abstract components in the catalog that are customized for specific environments:

```yaml
# In catalog
components:
  terraform:
    vpc:
      metadata:
        component: vpc
        type: abstract
      vars:
        enabled: true
        region: ${region}
```

### Component Dependencies

Define explicit dependencies between components:

```yaml
components:
  terraform:
    eks:
      depends_on:
        - vpc
        - securitygroup
```

### Configuration Mixins

Create reusable configuration fragments for environment types:

```yaml
# In stacks/mixins/production.yaml
vars:
  environment_type: "production"
  high_availability: true
  multi_az: true
  deletion_protection: true

# In environment stack
import:
  - mixins/production
  - catalog/network
```

### Variable Validation

Add validation rules to components:

```yaml
settings:
  terraform:
    vars:
      validation:
        rules:
          validate_k8s_version:
            rule: kubernetes_version =~ /^[0-9]+\.[0-9]+$/
            message: "Kubernetes version must be in format X.Y"
```

### Schema Validation

Use JSON Schema to validate stack configurations:

```yaml
# In atmos.yaml
schemas:
  atmos:
    manifest: "stacks/schemas/atmos/atmos-manifest/1.0/atmos-manifest.json"
```

### Component Hooks

Add pre/post-hooks for component operations:

```yaml
# In atmos.yaml
components:
  terraform:
    hooks:
      pre_plan:
        - run:
            command: terraform fmt -check -recursive
```

## Installation

### Prerequisites

- Terraform (v1.11.0 or later)
- AWS CLI (configured with appropriate credentials)
- Git

### Install Atmos CLI

#### macOS (with Homebrew)

```bash
brew tap cloudposse/tap
brew install atmos
```

#### Linux/macOS (with curl)

```bash
curl -fsSL https://atmos.tools/install.sh | bash
```

#### Verify Installation

```bash
atmos version
```

## Basic Usage

### Configure Atmos

Edit the `atmos.yaml` file to configure Atmos:

```yaml
base_path: "."

components:
  terraform:
    base_path: components/terraform
    apply_auto_approve: false
    deploy_run_init: true
    init_run_reconfigure: true
    auto_generate_backend_file: false
    terraform_version: "1.11.0"
    hooks:
      pre_plan:
        - run:
            command: terraform fmt -check -recursive

stacks:
  base_path: stacks
  included_paths:
  - "account/**/**/*.yaml"
  - "catalog/**/*.yaml"
  - "mixins/**/*.yaml"
  excluded_paths:
  - "**/_defaults.yaml"
  name_template: "{{.tenant}}-{{.account}}-{{.environment}}"

workflows:
  base_path: workflows
  imports:
  - apply-environment.yaml
  - bootstrap-backend.yaml
  - compliance-check.yaml
  # Other workflows...

settings:
  component:
    deps:
      enabled: true
    version:
      enabled: true
```

### Deploy a Component

```bash
atmos terraform apply vpc -s mycompany-dev-eu-west-2
```

### Use Workflows

```bash
atmos workflow apply-environment tenant=mycompany account=dev environment=eu-west-2
```

### Stack Validation

```bash
atmos validate stacks --stack mycompany-dev-eu-west-2
```

## Advanced Usage

### Component Dependencies

Define explicit component dependencies in stack files:

```yaml
# stacks/catalog/infrastructure.yaml
components:
  terraform:
    eks:
      depends_on:
        - vpc
        - securitygroup
      vars:
        # ... component variables ...
```

### Cross-Component References

Reference outputs from other components:

```yaml
vars:
  vpc_id: ${output.vpc.vpc_id}
  subnet_ids: ${output.vpc.private_subnet_ids}
  oidc_provider_arn: ${output.eks.oidc_provider_arn}
```

### Conditional Variable Processing

Use advanced variable processing with conditions:

```yaml
vars:
  multi_az: ${is_production | default(false)}
  backup_retention_period: ${is_production ? 30 : 7}
  deletion_protection: ${is_production | default(false)}
```

### Environment-Type Mixins

Use mixins to define common environment types:

```yaml
# Import environment type first, then specific components
import:
  - mixins/development
  - catalog/network
  - catalog/infrastructure
```

### Default Values with Fallbacks

Use default values with fallbacks to ensure variables are always defined:

```yaml
vars:
  eks_node_groups: ${eks_node_groups | default({
    default: {
      name: "default-ng",
      instance_types: ["t3.medium"],
      min_size: 2,
      max_size: 5,
      desired_size: 2
    }
  })}
```

## Debugging and Troubleshooting

### Logs

View Atmos logs with color:

```bash
# In atmos.yaml
logs:
  file: "/dev/stderr"
  level: Info
  color: true
```

### Verbose Output

Enable verbose output:

```bash
atmos --verbose terraform plan vpc -s tenant-account-environment
```

### Describe Configuration

Describe the merged configuration:

```bash
atmos describe config -s tenant-account-environment
```

### Compliance Checks

Run compliance checks:

```bash
atmos workflow compliance-check tenant=mycompany account=dev environment=eu-west-2
```

### Common Issues

1. **Stack not found** - Check stack name, name_template, and `stacks/` directory
2. **Component not found** - Check component name and `components/` directory
3. **Variable resolution errors** - Check variable references and context
4. **Backend errors** - Check S3/DynamoDB backend configuration
5. **Schema validation errors** - Check stack definitions against JSON schema

## Best Practices

### Organization Structure

- Organize stacks by account and environment
- Use mixins for environment types (production, development, staging)
- Use consistent naming conventions
- Keep component configurations DRY by using catalog

### Component Design

- Include comprehensive metadata
- Define explicit dependencies
- Implement variable validation
- Document component interface
- Follow standard file structure
- Provide sensible defaults

### Variables Management

- Define environment defaults in mixins
- Set reasonable defaults in catalog
- Override only what's necessary in account/environment
- Document variable meanings and constraints

### Workflow Standardization

- Create workflows for repetitive tasks
- Include validation and compliance checks
- Add proper error handling

### Documentation

- Document component interfaces (inputs/outputs)
- Document component architecture and design decisions
- Keep diagrams up-to-date

## Reference

### Atmos CLI Commands

- `atmos terraform <command> <component> -s <stack>` - Run Terraform commands
- `atmos workflow <workflow> [args]` - Run workflows
- `atmos describe component <component> -s <stack>` - Describe component
- `atmos describe config -s <stack>` - Describe stack configuration
- `atmos validate stacks --stack <stack>` - Validate stack configuration
- `atmos validate component --stack <stack>` - Validate component configuration
- `atmos version` - Show version information
- `atmos list components` - List available components
- `atmos list stacks` - List available stacks

### Configuration Reference

| Configuration | Description | Example |
|--------------|-------------|---------|
| `components.terraform.base_path` | Base path for components | `components/terraform` |
| `stacks.base_path` | Base path for stacks | `stacks` |
| `stacks.name_template` | Template for stack names | `{{.tenant}}-{{.account}}-{{.environment}}` |
| `workflows.base_path` | Base path for workflows | `workflows` |
| `settings.component.deps.enabled` | Enable component dependencies | `true` |

### Variable Reference

| Syntax | Description | Example |
|--------|-------------|---------|
| `${var.name}` | Reference variable | `${var.vpc_cidr}` |
| `${output.component.output}` | Reference component output | `${output.vpc.vpc_id}` |
| `${variable \| default("value")}` | Variable with default | `${region \| default("eu-west-2")}` |
| `${environment}` | Context variable | `${environment}` |
| `${condition ? value1 : value2}` | Conditional expression | `${is_prod ? 30 : 7}` |
| `${deep_merge(var1, var2)}` | Merge variables | `${deep_merge(var.defaults, var.overrides)}` |
| `${ssm:/path/to/param}` | SSM parameter | `${ssm:/myapp/database/password}` |

### Additional Resources

- [Atmos GitHub Repository](https://github.com/cloudposse/atmos)
- [Atmos Documentation](https://atmos.tools/)
- [Atmos Design Patterns](https://atmos.tools/design-patterns/)
- [Cloud Posse SweetOps Community](https://sweetops.com/)