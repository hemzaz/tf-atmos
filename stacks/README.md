# Atmos Stacks

This directory contains the stack configurations for the `fnx` AWS environments, organized with
Atmos.

## Stacks

Stack names come from `name_template` in `atmos.yaml`:
`{{ .settings.context.tenant }}-{{ .settings.context.stage }}-{{ .settings.context.environment }}`.
Only files under `orgs/` are stack manifests (`included_paths`); `_defaults.yaml` files and
`components/` directories are imported, not stacks themselves.

| Stack | Manifest |
|-------|----------|
| `fnx-dev-testenv-01` | `orgs/fnx/dev/eu-west-2/testenv-01.yaml` |
| `fnx-staging-staging-01` | `orgs/fnx/staging/eu-west-2/staging-01.yaml` |
| `fnx-prod-production` | `orgs/fnx/prod/eu-west-2/production.yaml` |

```bash
atmos list stacks
atmos list components
atmos describe component vpc/main -s fnx-dev-testenv-01
```

## Stack Structure

```
stacks/
├── catalog/                    # Reusable component configurations
│   ├── _base/defaults.yaml     # Base settings imported by every stack
│   ├── <component>/
│   │   ├── defaults.yaml       # Abstract component defaults
│   │   └── disabled.yaml       # Disabled variant
│   ├── vpc/{dev,staging,prod,ue2,uw2}.yaml   # Stage and region overrides for vpc
│   ├── templates/              # Opt-in stack templates (see templates/README.md)
│   └── _library/               # Module registry metadata
├── mixins/
│   ├── tenant/{core,fnx}.yaml
│   ├── stage/{dev,staging,prod}.yaml
│   ├── region/{eu-west-2,us-east-2,us-west-2}.yaml
│   └── development.yaml, production.yaml
└── orgs/fnx/
    ├── _defaults.yaml          # Tags, Terraform version, S3 backend
    └── <account>/              # dev, staging, prod
        ├── _defaults.yaml      # Account defaults (account_id, ...)
        └── eu-west-2/
            ├── _defaults.yaml  # Region defaults
            ├── <env>.yaml      # Stack manifest: imports, settings.context, settings.environment
            └── <env>/components/
                ├── globals.yaml     # Environment-wide settings
                ├── networking.yaml  # vpc/*, network/* (dns root module)
                ├── security.yaml    # iam/*, acm/*, secretsmanager/*, backend/main, kms/main (prod)
                ├── compute.yaml     # eks/*, ec2/*, external-secrets/*
                └── services.yaml    # apigateway/*, monitoring/*, infrastructure/* (disabled)
```

## Configuration conventions

- **Identity** lives in `settings.context` (`tenant`, `stage`, `environment`) and drives the stack
  name. Environment-wide knobs (account IDs, domain, hosted zone, versions) live in
  `settings.environment`. Components only receive the `vars` they declare.
- **Cross-component values** use YAML functions such as `!terraform.state vpc/main .vpc_id`, not
  `${...}` interpolation.
- **Ordering** is declared with `dependencies.components`; multi-component commands follow it.
- **Backend and Terraform version** are set once in `orgs/fnx/_defaults.yaml`: S3 bucket
  `fnx-terraform-state`, native lockfiles (`use_lockfile: true`), Terraform 1.16.3 through
  `terraform.dependencies.tools`.
- **Disabling** an instance: `metadata.enabled: false`.
- `settings.list_merge_strategy` is `replace` (set in `atmos.yaml`): a list in a more specific file
  replaces the inherited list instead of being appended to it.

## Usage

```bash
atmos terraform plan vpc/main -s fnx-dev-testenv-01
atmos terraform deploy vpc/main -s fnx-dev-testenv-01
atmos workflow deploy -f deploy-full-stack -s fnx-dev-testenv-01
```

See the [Deployment Guide](../docs/DEPLOYMENT_GUIDE.md) before the first apply: the stacks still
contain placeholder account IDs, domains and alert addresses.

## Guidelines

- Use catalog components for reusable configurations
- Define tenant/region/stage specific configurations in mixins
- Environment-specific overrides should be done in the environment files
- Follow the hierarchical inheritance pattern:
  1. Organization defaults
  2. Tenant configuration
  3. Account/stage configuration
  4. Region configuration
  5. Environment-specific overrides
