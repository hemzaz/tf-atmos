# Atmos-Managed Multi-Account AWS Infrastructure

## 1. What is this project?

This project is a comprehensive, turnkey infrastructure-as-code solution for deploying and managing multi-account AWS environments. It leverages Terraform for resource provisioning and Atmos for orchestration, providing a scalable and maintainable approach to infrastructure management.

Key features:
- Multi-account AWS setup with separate environments (dev, staging, prod, etc.)
- Centralized state management using S3 and DynamoDB
- Modular component structure for easy customization and reuse
- Workflow automation for common tasks (plan, apply, destroy, drift detection)
- Consistent naming and tagging conventions across resources
- Streamlined environment onboarding process

## 2. Project Structure

```
.
├── atmos.yaml                 # Atmos configuration file
├── components/                # Reusable Terraform modules
│   └── terraform/
│       ├── acm/
│       ├── backend/
│       ├── dns/
│       ├── ecs/               # Container orchestration
│       ├── eks/
│       ├── eks-addons/
│       ├── helm/
│       ├── iam/
│       ├── lambda/            # Serverless functions
│       ├── monitoring/        # CloudWatch dashboards and alarms
│       ├── rds/               # Database services
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
│   │   ├── backend.yaml       # Backend configuration
│   │   ├── iam.yaml           # IAM configuration
│   │   ├── infrastructure.yaml # Infrastructure components
│   │   ├── network.yaml       # VPC and networking
│   │   └── services.yaml      # Application services
│   └── schemas/               # JSON schemas for validation
└── workflows/                 # Atmos workflow definitions
    ├── apply-backend.yaml
    ├── apply-environment.yaml
    ├── bootstrap-backend.yaml
    ├── destroy-backend.yaml
    ├── destroy-environment.yaml
    ├── drift-detection.yaml
    ├── import.yaml
    ├── lint.yaml
    ├── onboard-environment.yaml # Environment onboarding
    ├── plan-environment.yaml
    └── validate.yaml
```

## 3. Getting Started

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

3. Onboard a new environment:
   ```
   atmos workflow onboard-environment tenant=mycompany account=dev environment=testenv-01 vpc_cidr=10.1.0.0/16
   ```

4. Deploy an existing environment:
   ```
   atmos workflow apply-environment tenant=mycompany account=dev environment=testenv-01
   ```

## 4. Component Catalog

This infrastructure includes the following core components:

### Network Layer
- **VPC** - Virtual private cloud with public and private subnets
- **NAT Gateway** - For outbound internet access from private subnets
- **VPN Gateway** - For connectivity to on-premises networks
- **Transit Gateway** - For connecting multiple VPCs

### Infrastructure Layer
- **EC2** - Virtual servers with security groups and IAM profiles
- **ECS** - Container orchestration with Fargate support
- **RDS** - Managed relational databases with automated backups
- **Lambda** - Serverless functions with monitoring
- **Monitoring** - CloudWatch dashboards, alarms, and log groups

### Services Layer
- **API Gateway** - For creating and managing APIs
- **Load Balancer** - Application load balancers for web traffic
- **CloudFront** - Content delivery network for global distribution

### Operations Layer
- **IAM** - Cross-account roles and policies
- **Backend** - S3 and DynamoDB for Terraform state management

## 5. Workflows

The following workflows are available to manage the infrastructure:

- **bootstrap-backend** - Initialize the Terraform backend
- **apply-backend** - Apply changes to the backend configuration
- **onboard-environment** - Create a new environment with baseline infrastructure
- **apply-environment** - Apply changes to an environment
- **plan-environment** - Plan changes for an environment
- **destroy-environment** - Destroy all resources in an environment
- **drift-detection** - Detect infrastructure drift
- **validate** - Validate Terraform configurations
- **lint** - Lint Terraform code and Atmos configurations
- **import** - Import existing resources into Terraform state

## 6. Development Guide

### Adding a New Component

1. Create a new directory under `components/terraform/`
2. Include `variables.tf`, `main.tf`, `outputs.tf`, and `provider.tf`
3. Create a corresponding catalog file in `stacks/catalog/`

### Adding a New Environment

1. Use the onboarding workflow:
   ```
   atmos workflow onboard-environment tenant=mycompany account=dev environment=newenv vpc_cidr=10.2.0.0/16
   ```
2. Customize the generated configurations as needed

### Modifying Existing Components

1. Make changes to the component code in `components/terraform/`
2. Update the corresponding catalog file if necessary
3. Run `atmos workflow plan-environment` to validate changes
4. Apply changes with `atmos workflow apply-environment`

## 7. Best Practices

- Use consistent naming conventions across all resources
- Follow the principle of least privilege for IAM policies
- Leverage Atmos variables for environment-specific configurations
- Use the catalog for reusable stack configurations
- Implement cost tagging for resource attribution
- Enable monitoring and alerting for all production environments
- Use separate state files for different components
- Regular drift detection to ensure configuration consistency

## 8. Contributing

Please follow these guidelines when contributing to the project:

- Use the included linting workflow before submitting PRs
- Add documentation for any new components or features
- Update tests when modifying existing components
- Follow the established coding style and naming conventions

## 9. Support

For questions or issues, please contact the DevOps team or create an issue in the project repository.