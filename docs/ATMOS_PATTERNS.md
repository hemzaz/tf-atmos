# Atmos Patterns and Best Practices

This document describes the recommended patterns and best practices for working with Atmos in this project.

## Directory Structure

```
stacks/
|-- catalog/                    # Component blueprints (abstract)
|   |-- _base/                  # Base configuration for all components
|   |   `-- defaults.yaml       # Common tags, settings, vars
|   |-- vpc/
|   |   |-- defaults.yaml       # VPC component defaults
|   |   |-- dev.yaml           # Dev-specific overrides
|   |   |-- staging.yaml       # Staging-specific overrides
|   |   `-- prod.yaml          # Production-specific overrides
|   |-- eks/
|   |   `-- defaults.yaml
|   `-- [component]/
|       `-- defaults.yaml
|
|-- mixins/                     # Reusable configuration fragments
|   |-- tenant/                 # Tenant-specific configurations
|   |   |-- fnx.yaml
|   |   `-- core.yaml
|   |-- stage/                  # Environment stage configurations
|   |   |-- dev.yaml
|   |   |-- staging.yaml
|   |   `-- prod.yaml
|   |-- region/                 # Region-specific configurations
|   |   |-- us-east-1.yaml
|   |   |-- eu-west-2.yaml
|   |   `-- us-west-2.yaml
|   |-- development.yaml        # Development environment mixin
|   `-- production.yaml         # Production environment mixin
|
`-- orgs/                       # Organization hierarchy
    `-- [tenant]/               # e.g., fnx
        |-- _defaults.yaml      # Tenant-wide defaults
        `-- [account]/          # e.g., dev, staging, prod
            |-- _defaults.yaml  # Account-wide defaults
            `-- [region]/       # e.g., eu-west-2
                |-- _defaults.yaml  # Region defaults
                `-- [environment].yaml  # Stack definition
                    `-- components/     # Component configs
                        |-- globals.yaml
                        |-- networking.yaml
                        |-- security.yaml
                        |-- compute.yaml
                        `-- services.yaml
```

## Import Best Practices

### 1. No File Extensions in Imports

Always omit the `.yaml` extension in import paths:

```yaml
# CORRECT
import:
  - catalog/vpc/defaults
  - mixins/stage/dev
  - orgs/fnx/dev/_defaults

# INCORRECT
import:
  - catalog/vpc/defaults.yaml
  - mixins/stage/dev.yaml
```

### 2. Import Order Matters

Import files in order of increasing specificity (later imports override earlier):

```yaml
import:
  # 1. Base configuration first
  - catalog/_base/defaults

  # 2. Mixins (general to specific)
  - mixins/tenant/fnx
  - mixins/stage/dev
  - mixins/region/eu-west-2

  # 3. Organization hierarchy
  - orgs/fnx/dev/_defaults

  # 4. Component-specific configurations
  - orgs/fnx/dev/eu-west-2/testenv-01/components/globals
```

### 3. Single Stack Definition

Each environment should have ONE canonical stack file:

```yaml
# stacks/orgs/fnx/dev/eu-west-2/testenv-01.yaml (canonical)

# Do NOT create multiple files like:
# - testenv-01.yaml AND main.yaml  (causes confusion)
```

## Variable Best Practices

### 1. Avoid Self-Referential Variables

Do NOT create variables that reference themselves:

```yaml
# INCORRECT - redundant and confusing
vars:
  tenant: "${tenant}"
  account: "${account}"
  environment: "${environment}"

# CORRECT - only define actual values or omit inherited vars
vars:
  tenant: fnx
  account: dev
  environment: testenv-01
```

### 2. Consistent Variable Naming

Match variable names between stacks and components:

```yaml
# Stack configuration
vars:
  vpc_cidr: "10.0.0.0/16"  # Match component variable name

# Component (components/terraform/vpc/variables.tf)
variable "vpc_cidr" {  # Same name
  type        = string
  description = "CIDR block for the VPC"
}
```

### 3. Use Descriptive Variable Names

Follow naming conventions:
- Boolean variables: prefix with `is_`, `has_`, or `enable_`
- Lists: use plural names (e.g., `subnet_ids`, not `subnet_id`)
- Maps: indicate the type (e.g., `tags_map` or `alarms_config`)

```yaml
vars:
  enable_vpc_flow_logs: true       # Boolean with enable_ prefix
  is_production: false             # Boolean with is_ prefix
  private_subnet_ids: []           # List with plural name
  alarm_configurations: {}         # Map with descriptive suffix
```

## Component Catalog Best Practices

### 1. Complete Metadata

Always include complete metadata in catalog defaults:

```yaml
components:
  terraform:
    vpc/defaults:
      metadata:
        component: vpc
        type: abstract
        version: "1.0.0"
        description: "Manages VPC with subnets, NAT gateways, and routing"
        category: "networking"
      depends_on:
        - backend
```

### 2. Use Abstract Components

Catalog components should be abstract (blueprints):

```yaml
metadata:
  type: abstract  # Cannot be provisioned directly
```

### 3. Define Outputs

Document expected outputs:

```yaml
outputs:
  vpc_id:
    description: "The ID of the VPC"
    value: "${output.vpc_id}"
  private_subnet_ids:
    description: "List of private subnet IDs"
    value: "${output.private_subnet_ids}"
```

## Mixin Best Practices

### 1. Structure Components Under `components:`

```yaml
# CORRECT
components:
  terraform:
    _environment_defaults:
      metadata:
        type: abstract
      vars:
        environment_type: "development"

# INCORRECT
terraform:
  vars:
    environment_type: "development"
```

### 2. Use Descriptive Names

Name mixins clearly to indicate their purpose:

- `development.yaml` - Development environment settings
- `production.yaml` - Production environment settings
- `mixins/region/eu-west-2.yaml` - EU West 2 region settings

## Backend Configuration

### Centralize in atmos.yaml

Define backend configuration once in `atmos.yaml`, not in individual catalog files:

```yaml
# atmos.yaml
components:
  terraform:
    backend_type: "s3"
    backend:
      s3:
        bucket: "atmos-terraform-state-${tenant}-${account}-${environment}"
        key: "terraform/${tenant}/${environment}/${component}.tfstate"
        dynamodb_table: "atmos-terraform-state-lock"
        region: "${region}"
```

## Validation

### Enable Validation in Production

Enable JSON Schema and OPA validation for production stacks:

```yaml
settings:
  validation:
    validate-component:
      schema_type: jsonschema
      schema_path: "vpc/validate-vpc-component.json"
      disabled: false  # Enable in prod
```

### Use the Enhanced Validation Workflow

```bash
# Run comprehensive validation
atmos workflow validate-all -f validate-enhanced.yaml

# Validate specific stack
atmos workflow validate-stack -f validate-enhanced.yaml \
  tenant=fnx account=dev environment=testenv-01
```

## Common Anti-Patterns to Avoid

1. **Duplicate stack definitions** - Only one file per environment
2. **`.yaml` extensions in imports** - Always omit extensions
3. **Self-referential variables** - Don't define `tenant: "${tenant}"`
4. **Backend config in catalogs** - Centralize in atmos.yaml
5. **Missing metadata** - Always include version, description
6. **Incorrect mixin structure** - Use `components: terraform:` not `terraform:`
7. **Variable name mismatches** - Stack vars must match component vars
8. **Duplicate variable declarations** - Check for duplicate variable blocks

## Workflow Commands

```bash
# Validate all configurations
atmos workflow validate-all -f validate-enhanced.yaml

# Lint and format
atmos workflow lint -f lint.yaml fix=true

# Plan environment
atmos workflow plan -f plan-environment.yaml \
  tenant=fnx account=dev environment=testenv-01

# Apply environment
atmos workflow apply-environment \
  tenant=fnx account=dev environment=testenv-01
```

## Quick Reference

| Pattern | Example |
|---------|---------|
| Import path | `- catalog/vpc/defaults` (no .yaml) |
| Boolean var | `enable_feature: true` |
| Component name | `vpc/main` (slash separator) |
| Metadata | Include `type`, `version`, `description` |
| Abstract type | `type: abstract` in catalog |
| Backend | Define once in `atmos.yaml` |
