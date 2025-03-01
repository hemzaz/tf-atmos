# Deployment Guide

This guide provides step-by-step instructions for deploying infrastructure using the Atmos framework.

## Deployment Architecture

The deployment follows this progression:

1. **Backend**: Terraform state management infrastructure (S3 + DynamoDB)
2. **Network**: VPC and core networking components
3. **IAM**: Identity and access management resources
4. **Infrastructure**: Compute, storage, and database resources
5. **Services**: Application services and endpoints

## Prerequisites

Before starting deployment, ensure you have:

- Completed the [installation guide](installation.md)
- AWS credentials with administrator access
- Atmos CLI properly configured (version specified in `.env`)
- Reviewed the tool versions in the `.env` file at project root

## Step 1: Bootstrap Backend Infrastructure

The backend stores Terraform state and provides locking to prevent concurrent modifications.

```bash
#!/usr/bin/env bash
# Bootstrap the Terraform backend
atmos workflow bootstrap-backend tenant=mycompany region=us-west-2

# Verify backend creation
aws s3 ls s3://mycompany-tfstate-us-west-2
aws dynamodb list-tables --region us-west-2
```

## Step 2: Deploy Backend Component

```bash
#!/usr/bin/env bash
# Initialize and apply the backend configuration
atmos workflow apply-backend tenant=mycompany account=management environment=prod
```

This creates:
- S3 bucket for Terraform state with versioning and encryption
- DynamoDB table for state locking
- IAM roles for cross-account access

## Step 3: Onboard a New Environment

The onboarding workflow sets up a new environment with all core infrastructure.

```bash
#!/usr/bin/env bash
# Create a new environment
atmos workflow onboard-environment tenant=mycompany account=dev environment=test vpc_cidr=10.1.0.0/16
```

This automatically:
1. Creates environment-specific stack configurations
2. Deploys network infrastructure (VPC, subnets, NAT gateways)
3. Sets up IAM roles and policies
4. Establishes security groups
5. Configures DNS resources

## Step 4: Review Generated Resources

```bash
# Check created configuration files
ls -la stacks/account/dev/test/

# Review the VPC configuration
cat stacks/account/dev/test/network.yaml
```

## Step 5: Customize Configuration

Edit the generated files to customize your environment:

```bash
# Example: Customize EKS configuration
vim stacks/account/dev/test/eks.yaml

# Example: Modify networking settings
vim stacks/account/dev/test/network.yaml
```

## Step 6: Plan and Apply Changes

```bash
#!/usr/bin/env bash
# Plan changes to validate configuration
atmos workflow plan-environment tenant=mycompany account=dev environment=test

# Apply infrastructure changes
atmos workflow apply-environment tenant=mycompany account=dev environment=test
```

## Step 7: Add Additional Components

To add individual components:

```bash
#!/usr/bin/env bash
# Example: Add RDS database
cp templates/catalog-component.yaml stacks/account/dev/test/rds.yaml
vim stacks/account/dev/test/rds.yaml

# Apply the specific component
atmos terraform apply rds -s mycompany-dev-test
```

## Step 8: Verify Deployment

```bash
#!/usr/bin/env bash
# List deployed AWS resources
atmos terraform output vpc -s mycompany-dev-test
aws ec2 describe-vpcs --region us-west-2 --filter "Name=tag:Name,Values=*test*"

# Check EKS cluster (if deployed)
aws eks list-clusters --region us-west-2
```

## Deployment Workflows

| Workflow | Description | Example |
|----------|-------------|---------|
| `bootstrap-backend` | Create backend infrastructure | `atmos workflow bootstrap-backend tenant=mycompany region=us-west-2` |
| `apply-backend` | Deploy backend component | `atmos workflow apply-backend tenant=mycompany account=management environment=prod` |
| `onboard-environment` | Create new environment | `atmos workflow onboard-environment tenant=mycompany account=dev environment=test vpc_cidr=10.1.0.0/16` |
| `plan-environment` | Plan changes | `atmos workflow plan-environment tenant=mycompany account=dev environment=test` |
| `apply-environment` | Apply all changes | `atmos workflow apply-environment tenant=mycompany account=dev environment=test` |
| `destroy-environment` | Remove environment | `atmos workflow destroy-environment tenant=mycompany account=dev environment=test` |

## Common Deployment Patterns

### Multi-Environment Setup

```
# Set up Dev
atmos workflow onboard-environment tenant=mycompany account=dev environment=dev vpc_cidr=10.1.0.0/16

# Set up Staging
atmos workflow onboard-environment tenant=mycompany account=staging environment=staging vpc_cidr=10.2.0.0/16

# Set up Production
atmos workflow onboard-environment tenant=mycompany account=prod environment=prod vpc_cidr=10.3.0.0/16
```

### EKS Deployment with Add-ons

```bash
#!/usr/bin/env bash
# Deploy EKS cluster
atmos terraform apply eks -s mycompany-dev-test

# Deploy add-ons after cluster is ready
atmos terraform apply eks-addons -s mycompany-dev-test
```

### Database Deployment

```bash
#!/usr/bin/env bash
# Create secrets first
atmos terraform apply secretsmanager -s mycompany-dev-test

# Deploy RDS using generated secrets
atmos terraform apply rds -s mycompany-dev-test
```

## Handling Deployment Failures

If a deployment fails:

1. Check the error message for details
2. Fix the configuration issues
3. Run `atmos workflow plan-environment` to validate changes
4. Try `atmos workflow apply-environment` again

For state locking issues:

```bash
#!/usr/bin/env bash
# View current locks
aws dynamodb scan --table-name mycompany-tfstate-locks-us-west-2 --attributes-to-get LockID Info

# Force unlock (use with caution)
terraform force-unlock LOCK_ID
```

## Next Steps

- Set up [CI/CD](cicd-best-practices.md) for automated deployments
- Configure [monitoring and alerting](../components/terraform/monitoring)
- Implement [security best practices](security-best-practices.md)

For detailed management of existing environments, see the [environment management guide](environment-management.md).