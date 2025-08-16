# Atmos Stacks

This directory contains the infrastructure stack configurations for our AWS environments, organized using the Atmos framework.

## Stack Structure

The project follows the hierarchical layout structure for Atmos stacks as recommended by the Atmos documentation:

```
stacks/
├── catalog/                # Reusable component configurations
│   ├── acm/                # Certificate management
│   │   ├── defaults.yaml   # Default component configuration
│   │   └── disabled.yaml   # Disabled configuration
│   ├── vpc/                # VPC networking
│   │   ├── defaults.yaml   # Default component configuration
│   │   ├── disabled.yaml   # Disabled configuration
│   │   ├── dev.yaml        # Dev stage specific configuration
│   │   ├── staging.yaml    # Staging stage specific configuration
│   │   ├── prod.yaml       # Production stage specific configuration
│   │   ├── ue2.yaml        # us-east-2 region specific configuration
│   │   └── uw2.yaml        # us-west-2 region specific configuration
│   └── ...                 # Other component configurations
├── mixins/                 # Reusable configuration sets
│   ├── tenant/             # Tenant-specific configuration
│   │   ├── core.yaml       # Core tenant configuration
│   │   └── fnx.yaml        # FNX tenant configuration
│   ├── region/             # Region-specific configuration
│   │   ├── us-east-2.yaml  # us-east-2 region configuration
│   │   └── us-west-2.yaml  # us-west-2 region configuration  
│   └── stage/              # Account stage configuration
│       ├── dev.yaml        # Development stage configuration
│       ├── staging.yaml    # Staging stage configuration
│       └── prod.yaml       # Production stage configuration
├── orgs/                   # Organization hierarchy
│   ├── acme/               # ACME Organization 
│   │   ├── _defaults.yaml  # Organization defaults
│   │   └── plat/           # Platform tenant
│   │       ├── _defaults.yaml          # Tenant defaults
│   │       ├── dev/                    # Development account
│   │       │   ├── _defaults.yaml      # Account defaults
│   │       │   ├── us-east-2/          # us-east-2 region
│   │       │   │   ├── _defaults.yaml  # Region defaults
│   │       │   │   └── test-01/        # Environment directory
│   │       │   │       ├── main.yaml   # Main environment config
│   │       │   │       └── components/ # Component configurations
│   │       │   │           ├── globals.yaml    # Global settings
│   │       │   │           ├── networking.yaml # Network config
│   │       │   │           ├── security.yaml   # Security config
│   │       │   │           ├── compute.yaml    # Compute config
│   │       │   │           └── services.yaml   # Services config
│   │       │   └── us-west-2/          # us-west-2 region
│   │       │       ├── _defaults.yaml  # Region defaults
│   │       │       └── test-02/        # Another environment
│   │       ├── staging/                # Staging account
│   │       │   ├── _defaults.yaml      # Account defaults
│   │       │   ├── us-east-2/          # us-east-2 region
│   │       │   └── us-west-2/          # us-west-2 region
│   │       └── prod/                   # Production account
│   │           ├── _defaults.yaml      # Account defaults
│   │           ├── us-east-2/          # us-east-2 region
│   │           └── us-west-2/          # us-west-2 region
│   └── fnx/                # FNX Organization 
│       ├── _defaults.yaml  # Organization defaults
│       └── dev/            # Development account
│           ├── _defaults.yaml          # Account defaults
│           └── eu-west-2/              # eu-west-2 region
│               ├── _defaults.yaml      # Region defaults
│               └── testenv-01/         # Environment directory
│                   ├── main.yaml       # Main environment config
│                   └── components/     # Component configurations
│                       ├── globals.yaml    # Global settings
│                       ├── networking.yaml # Network config
│                       ├── security.yaml   # Security config
│                       ├── compute.yaml    # Compute config
│                       └── services.yaml   # Services config
```

## Usage

To deploy an environment:

```bash
# For ACME organization
atmos terraform apply vpc -s acme-plat-dev-us-east-2-test-01

# For FNX organization
atmos terraform apply vpc -s fnx-dev-eu-west-2-testenv-01
```

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

## Components

The main components included:

- VPC and networking
- EKS clusters and addons
- Security groups
- IAM roles and policies
- Monitoring and logging
- Certificate management
- Secrets management
- API Gateway