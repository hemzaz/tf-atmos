# Multiple Component Instances Pattern - testenv-01

This stack implements the Multiple Component Instances design pattern to provision multiple instances of the same Terraform components with different configurations. The implementation uses a domain-based approach organized by functional areas.

## Architecture Overview

This environment contains multiple instances of core infrastructure components:

- **Networking**: Two VPCs (main, services), each with a DNS instance (`network/*`, `dns` root module)
- **Compute**: Two EKS clusters (main, data) and two EC2 instances (bastion, app-server)
- **Security**: IAM (`iam/dev`; `iam/ci` is disabled), ACM certificates, Secrets Manager instances and the state backend
- **Services**: API Gateways and monitoring configurations (`infrastructure/*` is disabled: no such root module yet)

## Directory Structure

```
eu-west-2/
├── testenv-01.yaml                    # Main stack manifest that imports all components
└── testenv-01/
    ├── README.md                      # This file
    └── components/                    # Component manifests by domain
        ├── README.md                  # Components documentation
        ├── globals.yaml               # Environment settings and imports
        ├── networking.yaml            # Network component instances
        ├── security.yaml              # Security component instances
        ├── compute.yaml               # Compute component instances
        └── services.yaml              # Service component instances
```

## Usage

The stack name is `fnx-dev-testenv-01` (`tenant-stage-environment` from `settings.context`).

### Deploy the entire environment:

```bash
atmos workflow full -f bootstrap -s fnx-dev-testenv-01           # first time: state bucket, IAM, VPCs
atmos workflow deploy -f deploy-full-stack -s fnx-dev-testenv-01 # layer by layer, confirmed per layer
```

### Deploy one layer:

```bash
# Deploy all networking components (vpc, dns, securitygroup root modules)
atmos workflow deploy-networking -f deploy-full-stack -s fnx-dev-testenv-01

# Deploy all security components (acm, secretsmanager, security-monitoring root modules)
atmos workflow deploy-security -f deploy-full-stack -s fnx-dev-testenv-01
```

### Deploy individual component instances:

```bash
# Deploy single VPC
atmos terraform deploy vpc/main -s fnx-dev-testenv-01

# Deploy single EKS cluster
atmos terraform deploy eks/data -s fnx-dev-testenv-01

# Deploy single ACM certificate
atmos terraform deploy acm/services -s fnx-dev-testenv-01
```

The dev account ID is read from the `AWS_ACCOUNT_ID` environment variable
(`settings.environment.aws_account_id`), so export it before running Atmos against this stack.

## Implementation Pattern

This stack demonstrates the Multiple Component Instances pattern where:

1. Abstract components in `catalog/*/defaults.yaml` define base configurations
2. Multiple concrete component instances inherit from these abstracts
3. Each instance customizes its configuration for its specific purpose
4. Domain-based organization groups related components by function