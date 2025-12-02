# Minimal Deployment Example

This example demonstrates the bare minimum configuration needed to deploy infrastructure using Atmos.

## Overview

The minimal deployment includes:
- Single VPC with basic networking
- Terraform backend (S3 + DynamoDB)
- Basic IAM roles
- Single EC2 bastion host

## Prerequisites

- AWS CLI configured
- Terraform 1.11+
- Atmos 1.163.0+

## Quick Start

```bash
# 1. Copy the stack configuration to your project
cp -r examples/minimal-deployment/stacks/* stacks/orgs/

# 2. Update variables in the stack file
vim stacks/orgs/example/dev/us-east-1/minimal.yaml

# 3. Set environment variables
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION=us-east-1

# 4. Bootstrap backend
atmos workflow backend-only -f bootstrap.yaml \
  tenant=example account=dev environment=minimal

# 5. Deploy
atmos workflow deploy -f deploy-full-stack.yaml \
  tenant=example account=dev environment=minimal \
  auto_approve=true
```

## Configuration

### Stack File (`stacks/orgs/example/dev/us-east-1/minimal.yaml`)

```yaml
import:
  - catalog/_base/defaults
  - catalog/vpc/defaults
  - catalog/iam/defaults
  - catalog/backend/defaults

vars:
  tenant: example
  account: dev
  environment: minimal
  region: us-east-1
  vpc_cidr: "10.100.0.0/16"

components:
  terraform:
    vpc/main:
      metadata:
        component: vpc
      vars:
        name: main
        vpc_cidr: "10.100.0.0/16"
        private_subnets:
          - "10.100.1.0/24"
        public_subnets:
          - "10.100.101.0/24"
        enable_nat_gateway: true
        nat_gateway_strategy: "single"
```

## Estimated Cost

| Resource | Monthly Cost (USD) |
|----------|-------------------|
| VPC | $0 |
| NAT Gateway | ~$32 |
| S3 (state) | ~$1 |
| DynamoDB (locks) | ~$0 |
| **Total** | **~$33** |

## Cleanup

```bash
# Destroy all resources
atmos workflow destroy -f destroy-environment.yaml \
  tenant=example account=dev environment=minimal \
  confirm=true
```

## Next Steps

After deploying the minimal example:

1. Add EKS cluster - see `examples/eks/`
2. Add RDS database - see `examples/rds/`
3. Add monitoring - see `examples/monitoring/`
4. Scale up to production - see `examples/production-ready/`
