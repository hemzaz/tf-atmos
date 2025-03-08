# Environment Templating and Scaffolding Guide

This guide explores tools and processes for creating new Atmos environments from templates, improving consistency and reducing manual configuration.

## Table of Contents

- [Overview](#overview)
- [Scaffolding Tool Selection](#scaffolding-tool-selection)
- [Copier Implementation](#copier-implementation)
- [Template Structure](#template-structure)
- [Variables and Customization](#variables-and-customization)
- [Integration with Atmos Workflows](#integration-with-atmos-workflows)
- [Advanced Features](#advanced-features)
- [Best Practices](#best-practices)
- [Example Implementation](#example-implementation)

## Overview

Creating new infrastructure environments requires consistency, proper inheritance patterns, and adherence to organizational standards. Scaffolding tools automate this process by generating environment configurations from templates with appropriate customization.

### Benefits of Environment Templating

- **Consistency**: Enforce organizational standards across all environments
- **Efficiency**: Reduce manual configuration time and human error
- **Auditability**: Track environment creation through version control
- **Maintainability**: Implement changes to templates rather than individual environments
- **Onboarding**: Simplify the process of creating new environments for team members

## Scaffolding Tool Selection

| Tool | Language | Template Engine | Strengths | Limitations | Best For |
|------|----------|-----------------|-----------|-------------|----------|
| **Copier** | Python | Jinja2 | Two-way updates, Git integration, powerful templating | Requires Python | Projects requiring ongoing template updates |
| **Yeoman** | JavaScript | EJS | Interactive prompts, composable generators | JavaScript dependency | Web-focused projects with complex interactions |
| **Terraform Module Generator** | Go | Text templates | Terraform-specific, generates compliant modules | Limited extensibility | Simple Terraform module creation |
| **Terragrunt** | Go | HCL | DRY configurations, remote state, dependencies | Not a pure templating solution | Complex multi-environment Terraform deployments |

For Atmos environment templating, we recommend **Copier** due to its flexibility, cross-platform support, powerful templating capabilities, and most importantly, its two-way update feature which allows environments to stay in sync with template changes over time.

## Copier Implementation

### Installation

```bash
# Install Copier
pip install copier

# Create new environment from template
copier copy gh:your-org/atmos-environment-template ./path/to/new-environment
```

### Key Features

Copier provides several advantages for environment templating:

1. **Two-way Updates**: Environments can be updated when templates change
2. **Version Control Integration**: Supports Git workflow and template versioning
3. **Powerful Templates**: Jinja2 templating with rich conditionals and macros
4. **Conflict Resolution**: Advanced mechanisms for resolving conflicts during updates
5. **Interactive Prompts**: Rich CLI interface for environment customization

## Template Structure

A typical Atmos environment template using Copier includes:

```
atmos-environment-template/
├── .copier-answers.yml                  # Tracks template answers
├── copier.yml                           # Template configuration
├── environment/                         # Template files
│   ├── {{tenant}}/                      # Templated directory names
│   │   └── {{account}}/
│   │       └── {{environment}}/
│   │           ├── atmos.yaml           # Environment config
│   │           ├── {{environment}}.yaml # Environment values
│   │           └── backend.tf           # State configuration 
├── hooks/                               # Pre/post generation scripts
│   ├── post_gen.py
│   └── pre_gen.py
└── README.md                            # Template documentation
```

## Variables and Customization

Copier uses interactive prompts to gather environment-specific variables:

```yaml
# copier.yml
_templates_suffix: .jinja
_envops:
  keep_trailing_newline: true

# Basic Information
tenant:
  type: str
  help: Organization tenant name (e.g., acme)
  validator: "^[a-z][a-z0-9-]*$"

account:
  type: str
  help: AWS account name (e.g., dev, prod)
  validator: "^[a-z][a-z0-9-]*$"

environment:
  type: str
  help: Environment name (e.g., ue2, use1)
  validator: "^[a-z][a-z0-9-]*$"

# Network Configuration  
vpc_cidr:
  type: str
  help: VPC CIDR block (e.g., 10.0.0.0/16)
  default: 10.0.0.0/16
  validator: "^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$"

# Environment Type
environment_type:
  type: str
  help: Environment type for configuration inheritance
  default: standard
  choices:
    - standard
    - data
    - demo
    - dev
    - prod
    - staging
```

## Integration with Atmos Workflows

The templating system integrates with Atmos workflows for seamless environment creation:

```bash
# 1. Create environment from template
copier copy gh:your-org/atmos-environment-template ./atmos

# 2. Initialize and validate the new environment
atmos workflow validate

# 3. Deploy the environment infrastructure
atmos workflow apply-environment tenant=acme account=dev environment=ue2
```

## Advanced Features

### Template Customization

Copier templates can use conditional logic to customize environments:

```jinja
{% if environment_type == "prod" %}
high_availability = true
instance_type = "m5.xlarge"
{% else %}
high_availability = false
instance_type = "t3.medium"
{% endif %}
```

### Template Updates

Environments can be updated when templates evolve:

```bash
# Update an existing environment to latest template version
cd path/to/environment
copier update
```

### Environment Presets

Create preset configurations for different environment types:

```yaml
# Template presets in copier.yml
_tasks:
  - output_dir: "./atmos/templates/{{ environment_type }}"
    when: environment_type in ["dev", "prod", "staging"]
    copy: 
      - source: "./templates/{{ environment_type }}/"
        dest: "./"
```

## Best Practices

1. **Consistent Structure**: Maintain consistent directory structure across templates
2. **Version Control**: Store templates in Git repositories with semantic versioning
3. **Documentation**: Include comprehensive README files explaining template usage
4. **Validation**: Add input validation to prevent misconfiguration
5. **Modular Design**: Create modular templates that focus on specific aspects
6. **Testing**: Test templates with different input combinations
7. **Compliance**: Include compliance and security standards in templates

## Example Implementation

### Creating a New Environment

```bash
# Install dependencies
pip install copier

# Create new environment
copier copy gh:your-org/atmos-environment-template ./atmos

# Answer prompts:
# - tenant: acme
# - account: dev
# - environment: ue2
# - vpc_cidr: 10.0.0.0/16
# - environment_type: dev

# Initialize and validate
cd atmos
atmos workflow validate

# Deploy infrastructure
atmos workflow apply-environment tenant=acme account=dev environment=ue2
```

### Updating an Environment Template

```bash
# Navigate to environment directory
cd path/to/environment

# Update to latest template version
copier update

# Review and resolve any conflicts
git diff

# Validate changes
atmos workflow validate

# Apply updated configuration
atmos workflow apply-environment tenant=acme account=dev environment=ue2
```

This templating approach ensures consistent environments that can evolve with changing requirements while maintaining infrastructure-as-code best practices.