# CLAUDE.md - Terraform/Atmos Infrastructure Project

This file provides guidance to Claude Code when working with this Terraform/Atmos infrastructure codebase.

## Project Overview

This is a **Terraform/Atmos infrastructure-as-code project** with:
- **22 Terraform root modules** in `components/terraform/` (plus `_library/` and `_catalog/`)
- **3 stacks**: `fnx-dev-testenv-01`, `fnx-staging-staging-01`, `fnx-prod-production` (eu-west-2)
- **Atmos workflows** in `workflows/` (`atmos list workflows`) and **Atmos Native CI** in `.github/workflows/`
- Atmos >= 1.229.0 (enforced in `atmos.yaml`); Terraform 1.16.3 is installed by the Atmos toolchain
  (`terraform.dependencies.tools` in `stacks/orgs/fnx/_defaults.yaml`); AWS provider `~> 6.65`
- S3 state backend `fnx-terraform-state` with native lockfiles (`use_lockfile`), no DynamoDB

There is no Python CLI; use `atmos` commands and workflows.

## Essential Commands

### Discovery
```bash
atmos list stacks                     # stack names
atmos list components                 # component instances
atmos list workflows                  # workflow name, file, description
atmos describe component <component> -s <stack>   # resolved config for one instance
```

### Validation & Linting (offline, no AWS credentials)
```bash
atmos validate stacks                          # stack manifests
atmos workflow validate-all -f validate-enhanced   # schema, stacks, yamllint, fmt, terraform validate of every root module
atmos workflow lint -f lint                    # fmt, yamllint, tflint, trivy
```
`atmos terraform validate <component> -s <stack>` runs `terraform init` against the S3 backend, so it needs AWS credentials.

### Planning & Deployment
```bash
atmos terraform plan <component> -s <stack>
atmos terraform deploy <component> -s <stack>        # plan + apply one instance
atmos workflow plan -f plan-environment -s <stack>   # every component in the stack
atmos workflow deploy -f deploy-full-stack -s <stack>   # layered, with confirmation per layer
atmos workflow full -f bootstrap -s <stack>          # first deploy: state bucket, IAM, VPCs
```

## Development Guidelines

### Terraform/HCL Standards
- Follow naming: `${local.name_prefix}-<resource-type>`
- Use snake_case for resources, variables, outputs
- Include detailed variable descriptions with validation
- Mark sensitive outputs with `sensitive = true`
- Tags come from `var.tags` through the provider's `default_tags`; don't repeat them per resource

### File Structure (per component)
- `main.tf` - Primary resource definitions (some components split them into `iam.tf`, `locals.tf`, ...)
- `variables.tf` - Input variables with validation
- `outputs.tf` - Output values with descriptions
- `versions.tf` - `required_version` (`>= 1.16.0, < 2.0.0`) and `required_providers`
- `provider.tf` - AWS provider with `region = var.region` and `default_tags { tags = var.tags }`
- `README.md` - Component documentation

### Stack Configuration
- Stack names come from `settings.context` (`tenant-stage-environment`), not from `vars`
- Cross-component values use YAML functions (`!terraform.state <component> .<output>`), never `${...}` interpolation
- Declare ordering with `dependencies.components`
- Disable an instance with `metadata.enabled: false`; `iam/ci`, `iam/eks-node` and `iam/eks-cluster` are disabled
- `network/*` instances use the `dns` root module; `idp-platform` is unsupported (`acknowledge_unsupported`)

### Security Requirements
- Encrypt sensitive data at rest and in transit
- Use least privilege IAM policies
- Keep secrets in Secrets Manager; never commit sensitive information
- Use specific CIDR blocks, avoid 0.0.0.0/0

### Multi-Environment Patterns
- Use Atmos stack hierarchies for configuration inheritance
- Component naming: singular form without hyphens (`securitygroup` not `security-groups`)
- Boolean variables: prefix with `is_`, `has_`, or `enable_`

## Testing & Validation

### Before Committing
```bash
atmos workflow lint -f lint
atmos workflow validate-all -f validate-enhanced
```

### Component Testing
```bash
atmos describe component <component> -s <stack>
atmos terraform plan <component> -s <stack>          # needs AWS credentials
```

## Common Stacks
- `fnx-dev-testenv-01` - Development
- `fnx-staging-staging-01` - Staging
- `fnx-prod-production` - Production

## Review Checklist

Before marking tasks complete:
- [ ] Terraform code follows naming conventions
- [ ] Variables include descriptions and validation
- [ ] Sensitive outputs marked appropriately
- [ ] Security best practices followed
- [ ] `atmos workflow validate-all -f validate-enhanced` passes
- [ ] Documentation updated (README.md)
