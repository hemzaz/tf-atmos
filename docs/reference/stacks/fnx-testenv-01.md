# Multiple Component Instances Pattern - testenv-01

This stack implements the Multiple Component Instances design pattern to provision multiple instances of the same Terraform components with different configurations. The implementation uses a domain-based approach organized by functional areas.

## Architecture Overview

This environment contains multiple instances of core infrastructure components:

- **Networking**: Two VPCs (main, services) with dedicated network configurations
- **Compute**: Two EKS clusters (main, data) and multiple EC2 instances
- **Security**: Multiple IAM roles, ACM certificates, and secrets manager instances
- **Services**: Multiple API Gateways, databases, and monitoring configurations

## Directory Structure

```
testenv-01/
├── README.md                      # This file
├── components/                    # Component manifests by domain
│   ├── README.md                  # Components documentation
│   ├── globals.yaml               # Environment variables and imports
│   ├── networking.yaml            # Network component instances
│   ├── security.yaml              # Security component instances  
│   ├── compute.yaml               # Compute component instances
│   └── services.yaml              # Service component instances
└── testenv-01.yaml                # Main stack manifest that imports all components
```

## Usage

### Deploy the entire environment:

```bash
atmos terraform apply -s fnx-dev-eu-west-2-testenv-01
```

### Deploy domain-specific components:

```bash
# Deploy all networking components
atmos terraform apply -c networking.yaml -s fnx-dev-eu-west-2-testenv-01

# Deploy all security components
atmos terraform apply -c security.yaml -s fnx-dev-eu-west-2-testenv-01
```

### Deploy individual component instances:

```bash
# Deploy single VPC
atmos terraform apply vpc/main -s fnx-dev-eu-west-2-testenv-01

# Deploy single EKS cluster
atmos terraform apply eks/data -s fnx-dev-eu-west-2-testenv-01

# Deploy single ACM certificate
atmos terraform apply acm/services -s fnx-dev-eu-west-2-testenv-01
```

## Implementation Pattern

This stack demonstrates the Multiple Component Instances pattern where:

1. Abstract components in `catalog/*/defaults.yaml` define base configurations
2. Multiple concrete component instances inherit from these abstracts
3. Each instance customizes its configuration for its specific purpose
4. Domain-based organization groups related components by function