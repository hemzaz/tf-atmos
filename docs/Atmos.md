# Atmos Framework Overview

_Last Updated: February 27, 2025_

This document provides a comprehensive overview of the Atmos framework, its architecture, and how it's used to manage infrastructure as code with Terraform.

## Table of Contents

- [Introduction](#introduction)
- [Architecture](#architecture)
- [Key Concepts](#key-concepts)
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

Atmos is particularly well-suited for organizations with multiple AWS accounts (e.g., development, staging, production) and teams that need to manage infrastructure consistently across these accounts.

## Architecture

Atmos uses a structured approach to organize infrastructure code:

```
└── Project Root
    ├── atmos.yaml              # Atmos configuration
    ├── components/             # Terraform modules
    ├── stacks/                 # Stack configurations
    │   ├── catalog/            # Reusable component configurations
    │   ├── account/            # Account-specific configurations
    │   └── schemas/            # JSON schemas for validation
    └── workflows/              # Custom workflows
```

The architecture follows these principles:

1. **Separation of concerns** - Components (code) are separated from configurations (variables)
2. **Hierarchical organization** - Configurations cascade from general to specific
3. **Single source of truth** - All configurations managed in one repository
4. **Workflow standardization** - Common operations defined as workflows
5. **Version control** - All code and configurations managed with Git

![Atmos Architecture](https://raw.githubusercontent.com/cloudposse/atmos/master/docs/images/architecture.png)

## Key Concepts

### Components

Components are the building blocks of your infrastructure. In Atmos, a component is typically a Terraform module that defines a specific piece of infrastructure (e.g., VPC, EKS cluster, RDS instance).

Components are stored in the `components/terraform/` directory and contain:
- Terraform code (.tf files)
- Documentation
- Tests (optional)

### Stacks

Stacks define configurations for components across different environments. They are organized in a hierarchical structure:

- **Catalog** (`stacks/catalog/`) - Base configurations for components
- **Account** (`stacks/account/`) - Account and environment-specific configurations

Stacks are defined in YAML files and use a hierarchical inheritance model:

1. Catalog defines base configuration
2. Account-specific configuration inherits and overrides catalog
3. Environment-specific configuration inherits and overrides account

### Variables

Atmos provides a powerful variable system that supports:

- **Variable inheritance** - Inherited from more general to more specific configurations
- **Variable overrides** - More specific configurations override general ones
- **Context variables** - `tenant`, `account`, `environment`, `region`, etc.
- **Special expressions** - For advanced variable processing

Example variable reference: `${output.vpc.vpc_id}`

### Workflows

Workflows are predefined sequences of commands that automate common tasks. They are defined in YAML files in the `workflows/` directory.

Example workflow:
```yaml
name: apply-environment
description: "Apply all components in an environment"
steps:
  - command: atmos
    args:
      - terraform
      - apply
      - vpc
      - -s
      - "{tenant}-{account}-{environment}"
  # More steps...
```

## Installation

### Prerequisites

- Terraform (v1.0.0 or later)
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

### Initialize Project

```bash
atmos init
```

This sets up the basic directory structure and configuration files.

### Configure Atmos

Edit the `atmos.yaml` file to configure Atmos:

```yaml
base:
  components:
    terraform:
      base_path: components/terraform
      apply_auto_approve: false
      deploy_run_init: true
      init_run_reconfigure: true
      auto_generate_backend_file: true
  stacks:
    base_path: stacks
    included_paths:
      - "catalog/**/*"
      - "account/**/*"
    excluded_paths:
      - "**/.git/**/*"
    name_pattern: "{tenant}-{environment}-{stage}"
# ...additional configuration...
```

### Deploy a Component

```bash
atmos terraform apply vpc -s mycompany-dev-us-east-1
```

### Use Workflows

```bash
atmos workflow apply-environment tenant=mycompany account=dev environment=us-east-1
```

## Advanced Usage

### Component Dependencies

Atmos supports explicit component dependencies using the `dependencies` field in stack configurations:

```yaml
# stacks/account/dev/us-east-1/eks.yaml
import:
  - catalog/eks

dependencies:
  - vpc
  - iam

vars:
  # ... component variables ...
```

### Cross-Component References

Reference outputs from other components:

```yaml
vars:
  vpc_id: ${output.vpc.vpc_id}
  subnet_ids: ${output.vpc.private_subnet_ids}
```

### Custom Variable Processing

Atmos supports advanced variable processing:

```yaml
vars:
  cidr_block: ${cidrsubnet("10.0.0.0/16", 8, 10)}
  combined_config: ${merge(var.default_config, var.override_config)}
```

### Context Inheritance

Use inheritance to manage configurations across multiple environments:

```yaml
import:
  - catalog/base
  - account/common
```

## Debugging and Troubleshooting

### Logs

View Atmos logs:

```bash
atmos logs
```

### Verbose Output

Enable verbose output:

```bash
atmos --verbose terraform plan vpc -s tenant-account-environment
```

### Component Validation

Validate a component:

```bash
atmos terraform validate vpc -s tenant-account-environment
```

### Common Issues

1. **Stack not found** - Check stack name and `stacks/` directory
2. **Component not found** - Check component name and `components/` directory
3. **Variable resolution errors** - Check variable references and context
4. **Backend errors** - Check S3/DynamoDB backend configuration

## Best Practices

### Organization Structure

- Organize stacks by account and environment
- Use consistent naming conventions
- Keep component configurations DRY by using catalog

### Variables Management

- Define defaults in catalog
- Override only what's necessary in account/environment
- Use context variables where possible
- Document variable meanings and constraints

### Workflow Standardization

- Create workflows for repetitive tasks
- Include validation steps
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
- `atmos describe stack <stack>` - Describe stack
- `atmos version` - Show version information
- `atmos list components` - List available components
- `atmos list stacks` - List available stacks

### Configuration Reference

| Configuration | Description | Example |
|--------------|-------------|---------|
| `base.components.terraform.base_path` | Base path for components | `components/terraform` |
| `base.stacks.base_path` | Base path for stacks | `stacks` |
| `base.stacks.name_pattern` | Pattern for stack names | `{tenant}-{environment}-{stage}` |
| `base.workflows.base_path` | Base path for workflows | `workflows` |

### Variable Reference

| Syntax | Description | Example |
|--------|-------------|---------|
| `${var.name}` | Reference variable | `${var.vpc_cidr}` |
| `${output.component.output}` | Reference component output | `${output.vpc.vpc_id}` |
| `${environment}` | Context variable | `${environment}` |
| `${deep_merge(var1, var2)}` | Merge variables | `${deep_merge(var.defaults, var.overrides)}` |
| `${ssm:/path/to/param}` | SSM parameter | `${ssm:/myapp/database/password}` |

### Additional Resources

- [Atmos GitHub Repository](https://github.com/cloudposse/atmos)
- [Atmos Documentation](https://atmos.tools/quick-start/)
- [Cloud Posse SweetOps Community](https://sweetops.com/)