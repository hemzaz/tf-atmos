# Atmos Stacks

Stack configurations for the `fnx` AWS environments.

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

## Structure

```
stacks/
├── catalog/                    # Reusable component configurations
│   ├── _base/defaults.yaml     # Base settings imported by every stack
│   ├── <component>/{defaults,disabled}.yaml   # Abstract component defaults and disabled variant
│   └── templates/              # Opt-in stack templates (below)
├── mixins/                     # tenant/{core,fnx}, stage/{dev,staging,prod}, region/*
└── orgs/fnx/
    ├── _defaults.yaml          # Tags, Terraform version, S3 backend
    └── <account>/eu-west-2/
        ├── <env>.yaml          # Stack manifest: imports, settings.context, settings.environment
        └── <env>/components/   # globals, networking, security, compute, services (imported by the manifest)
```

`testenv-01` is the reference example of this domain split: `networking.yaml` holds two VPCs
(`vpc/main`, `vpc/services`) each with a `network/*` (`dns` root module) instance; `security.yaml`
holds `iam/dev`, ACM, Secrets Manager and `backend/main`; `compute.yaml` holds two EKS clusters
(`eks/main`, `eks/data`) and two EC2 instances; `services.yaml` holds API Gateway and monitoring.
Instances declare order with `dependencies.components` and read each other via `!terraform.state`.

## Configuration conventions

- **Identity** lives in `settings.context` (`tenant`, `stage`, `environment`) and drives the stack
  name. Environment-wide knobs (account IDs, domain, hosted zone) live in `settings.environment`.
- **Cross-component values** use YAML functions (`!terraform.state vpc/main .vpc_id`), never
  `${...}` interpolation.
- **Backend and Terraform version** are set once in `orgs/fnx/_defaults.yaml`: S3 bucket
  `fnx-terraform-state`, native lockfiles (`use_lockfile: true`), Terraform 1.16.3.
- **Disabling** an instance: `metadata.enabled: false`.
- `settings.list_merge_strategy` is `replace` (in `atmos.yaml`): a list in a more specific file
  replaces the inherited list instead of appending to it.

See the [Deployment Guide](../docs/DEPLOYMENT.md) before the first apply: the stacks still contain
placeholder account IDs, domains and alert addresses.

## Stack templates

`stacks/catalog/templates/` has five opt-in templates. None of the three existing stacks imports
one today.

| Template | Pattern |
|----------|---------|
| `web-application` | 3-tier: ALB, WAF, ECS/EC2, RDS, ElastiCache, CloudFront |
| `microservices-platform` | EKS, API Gateway + VPC Link, EventBridge, DynamoDB |
| `serverless-api` | API Gateway, Lambda, DynamoDB, Cognito |
| `data-pipeline` | Kinesis, Lambda, S3 data lake, Glue, Athena |
| `batch-processing` | AWS Batch, SQS, Step Functions |

Use one by importing it into a stack manifest and setting its required variables (see the
template's YAML file for the full variable list), then deploy with
`atmos workflow deploy -f deploy-template -s <stack>` (see
[Deployment Guide](../docs/DEPLOYMENT.md#deploying-a-stack-template)).
