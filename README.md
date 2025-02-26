# Atmos-Managed Multi-Account AWS Infrastructure

## 1. What is this project?

This project is a comprehensive, Atmos-managed infrastructure-as-code solution for deploying and managing multi-account AWS environments. It leverages Terraform for resource provisioning and Atmos for orchestration, providing a scalable and maintainable approach to infrastructure management.

Key features:
- Multi-account AWS setup with separate environments (dev, staging, prod, etc.)
- Centralized state management using S3 and DynamoDB
- Modular component structure for easy customization and reuse
- Workflow automation for common tasks (plan, apply, destroy, drift detection)
- Consistent naming and tagging conventions across resources

## 2. Project Structure

```
.
├── atmos.yaml                 # Atmos configuration file
├── components/                # Reusable Terraform modules
│   └── terraform/
│       ├── acm/
│       ├── backend/
│       ├── dns/
│       ├── eks/
│       ├── eks-addons/
│       ├── helm/
│       ├── iam/
│       ├── security-groups/
│       └── vpc/
├── docs/                      # Project documentation
├── stacks/                    # Stack configurations
│   ├── account/               # Account-specific configurations
│   │   ├── dev/
│   │   ├── management/
│   │   ├── prod/
│   │   ├── shared-services/
│   │   └── stg/
│   ├── catalog/               # Reusable stack configurations
│   └── schemas/               # JSON schemas for validation
└── workflows/                 # Atmos workflow definitions
```

## 3. How to Deploy

### Prerequisites
- AWS CLI configured with appropriate credentials
- Terraform (version 1.0.0 or later)
- Atmos CLI installed

### Deployment Steps

1. Bootstrap the backend:
   ```
   atmos workflow bootstrap-backend tenant=mycompany region=us-west-2
   ```

2. Initialize and apply the backend configuration:
   ```
   atmos workflow apply-backend tenant=mycompany account=management environment=prod
   ```

3. Deploy an environment:
   ```
   atmos workflow apply-environment tenant=mycompany account=dev environment=testenv-01
   ```

## 4. Development Guide

### Code Conventions

- Use consistent naming conventions:
  - Resources: `${tenant}-${account}-${environment}-resource-name`
  - IAM Roles: `${tenant}-${account}-${environment}-RoleName`
  - S3 Buckets: `${tenant}-${account}-${environment}-bucket-name`

- Tag all resources with at least:
  - Tenant
  - Account
  - Environment
  - ManagedBy: "Terraform"

### Structure Guidelines

- Keep Terraform modules in `components/terraform/`
- Place reusable stack configurations in `stacks/catalog/`
- Create account and environment-specific configurations in `stacks/account/`
- Define workflows in the `workflows/` directory

### Adding a New Component

1. Create a new directory under `components/terraform/`
2. Include `variables.tf`, `main.tf`, `outputs.tf`, and `provider.tf`
3. Create a corresponding catalog file in `stacks/catalog/`

### Adding a New Environment

1. Create a new directory under `stacks/account/<account>/`
2. Create YAML files for each component (backend.yaml, iam.yaml, etc.)
3. Import and extend catalog configurations as needed

## 5. Examples

### Defining a New VPC

1. In `components/terraform/vpc/main.tf`:
   ```hcl
   resource "aws_vpc" "main" {
     cidr_block = var.vpc_cidr
     tags = merge(var.tags, {
       Name = "${var.tenant}-${var.account}-${var.environment}-main-vpc"
     })
   }
   ```

2. In `stacks/catalog/network.yaml`:
   ```yaml
   components:
     terraform:
       vpc:
         metadata:
           component: vpc
           type: abstract
         vars:
           vpc_cidr: "10.0.0.0/16"
         settings:
           terraform:
             backend:
               s3:
                 key: ${account}/${environment}/network/terraform.tfstate
   ```

3. In `stacks/account/dev/testenv-01/network.yaml`:
   ```yaml
   import:
     - catalog/network
   
   vars:
     account: dev
     environment: testenv-01
     vpc_cidr: "10.1.0.0/16"  # Override the default
   ```

### Applying Changes

To apply the VPC configuration:

```bash
atmos terraform apply vpc -s mycompany-dev-testenv-01
```