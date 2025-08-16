# CLAUDE.md - Terraform/Atmos Infrastructure Project

This file provides guidance to Claude Code when working with this Terraform/Atmos infrastructure codebase.

## Project Overview

This is a **Terraform/Atmos infrastructure-as-code project** with:
- **17 Terraform components** (VPC, EKS, RDS, Lambda, etc.)
- **Python CLI tool "Gaia"** for workflow automation
- **Multi-tenant/multi-environment** architecture
- **16 Atmos workflows** for deployment automation

## Essential Commands

### Validation & Linting
```bash
atmos workflow lint                    # Lint all configurations  
atmos workflow validate               # Validate all components
atmos terraform validate <component> -s <stack>  # Validate specific component
```

### Planning & Deployment
```bash
atmos workflow plan-environment tenant=<tenant> account=<account> environment=<environment>
atmos workflow apply-environment tenant=<tenant> account=<account> environment=<environment>
```

### Stack Management
```bash
atmos describe stacks                 # List all stacks
./scripts/list_stacks.sh             # User-friendly stack listing
```

## Development Guidelines

### Terraform/HCL Standards
- Follow naming: `${local.name_prefix}-<resource-type>`
- Use snake_case for resources, variables, outputs
- Include detailed variable descriptions with validation
- Mark sensitive outputs with `sensitive = true`
- Apply consistent tags to all resources

### File Structure (per component)
- `main.tf` - Primary resource definitions
- `variables.tf` - Input variables with validation
- `outputs.tf` - Output values with descriptions  
- `provider.tf` - Provider configuration
- `README.md` - Component documentation

### Security Requirements
- Encrypt sensitive data at rest and in transit
- Use least privilege IAM policies
- Store secrets in SSM/Secrets Manager (`${ssm:/path}`)
- Never commit sensitive information
- Use specific CIDR blocks, avoid 0.0.0.0/0

### Multi-Environment Patterns
- Use Atmos stack hierarchies for configuration inheritance
- Component naming: singular form without hyphens (`securitygroup` not `security-groups`)
- Boolean variables: prefix with `is_`, `has_`, or `enable_`

## Testing & Validation

### Before Committing
```bash
atmos workflow lint                   # Fix formatting issues
atmos workflow validate              # Validate all components
```

### Component Testing
```bash
atmos terraform validate <component> -s <tenant>-<account>-<environment>
atmos terraform plan <component> -s <stack> --out=plan.out
```

## Python Tooling (Gaia CLI)

### Installation
```bash
pip install -e .                     # Install in development mode
```

### Usage
```bash
gaia workflow lint --fix false       # Lint with optional auto-fix
gaia workflow validate --tenant <tenant> --account <account> --environment <environment>
```

## Common Stacks
- `fnx-dev-testenv-01` - Main development environment

## Review Checklist

Before marking tasks complete:
- [ ] Terraform code follows naming conventions
- [ ] Variables include descriptions and validation
- [ ] Sensitive outputs marked appropriately  
- [ ] Security best practices followed
- [ ] Components validated with `atmos workflow validate`
- [ ] Documentation updated (README.md)