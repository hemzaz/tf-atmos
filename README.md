# Atmos-Managed Multi-Account AWS Infrastructure

![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)
![Terraform](https://img.shields.io/badge/terraform-%3E%3D1.0.0-623CE4.svg)
![Atmos](https://img.shields.io/badge/atmos-%3E%3D1.5.0-16A394.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)
![AWS](https://img.shields.io/badge/AWS-%23FF9900.svg?style=flat&logo=amazon-aws&logoColor=white)
![Workflow Status](https://img.shields.io/badge/workflows-passing-success.svg)
![Last Commit](https://img.shields.io/github/last-commit/hemzaz/tf-atmos)

_Last Updated: February 27, 2025_

## Table of Contents
1. [What is this project?](#1-what-is-this-project)
2. [Project Structure](#2-project-structure)
3. [Getting Started](#3-getting-started)
4. [Component Catalog](#4-component-catalog)
5. [Workflows](#5-workflows)
6. [Development Guide](#6-development-guide)
7. [Best Practices](#7-best-practices)
8. [Contributing](#8-contributing)
9. [Documentation](#9-documentation)
10. [Support and Troubleshooting](#10-support-and-troubleshooting)
11. [License](#11-license)
12. [Roadmap](#12-roadmap)

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
├── CLAUDE.md                  # Code style guidelines and reference
├── atmos.yaml                 # Atmos configuration file
├── components/                # Reusable Terraform modules
│   └── terraform/
│       ├── acm/               # ACM certificate management
│       ├── apigateway/        # API Gateway (REST and HTTP APIs)
│       ├── backend/           # Terraform state management infrastructure
│       │   └── policies/      # IAM policy templates
│       ├── dns/               # Route53 and DNS configuration
│       ├── ec2/               # EC2 instances and related resources
│       ├── ecs/               # Container orchestration
│       ├── eks/               # Kubernetes clusters
│       ├── eks-addons/        # Kubernetes add-ons and operators
│       ├── iam/               # Identity and Access Management
│       │   └── policies/      # IAM policy templates
│       ├── lambda/            # Serverless functions
│       ├── monitoring/        # CloudWatch dashboards and alarms
│       │   └── templates/     # Dashboard templates
│       ├── rds/               # Database services
│       ├── secretsmanager/    # AWS Secrets Manager for secure secret storage
│       │   └── policies/      # Secret access policy templates
│       ├── securitygroup/     # Security group management
│       └── vpc/               # Network infrastructure
│           └── policies/      # Network policy templates
├── docs/                      # Project documentation
│   └── diagrams/              # Architecture and workflow diagrams
├── examples/                  # Practical implementation examples
├── stacks/                    # Stack configurations
│   ├── account/               # Account-specific configurations
│   │   ├── dev/
│   │   ├── management/
│   │   ├── prod/
│   │   ├── shared-services/
│   │   └── staging/
│   ├── catalog/               # Reusable stack configurations
│   │   ├── apigateway.yaml    # API Gateway configuration
│   │   ├── backend.yaml       # Backend configuration
│   │   ├── iam.yaml           # IAM configuration
│   │   ├── infrastructure.yaml # Infrastructure components
│   │   ├── network.yaml       # VPC and networking
│   │   └── services.yaml      # Application services
│   └── schemas/               # JSON schemas for validation
├── templates/                 # Reusable templates for new components/configs
└── workflows/                 # Atmos workflow definitions
    ├── apply-backend.yaml
    ├── apply-environment.yaml
    ├── bootstrap-backend.yaml
    ├── destroy-backend.yaml
    ├── destroy-environment.yaml
    ├── drift-detection.yaml
    ├── import.yaml            # Import existing resources
    ├── lint.yaml              # Code quality
    ├── onboard-environment.yaml # Environment onboarding
    ├── plan-environment.yaml
    └── validate.yaml          # Configuration validation
```

## 3. Getting Started

### Prerequisites
- AWS CLI configured with appropriate credentials
- Terraform (version 1.0.0 or later)
- Atmos CLI (version 1.5.0 or later)

### Installation

#### Linux
1. Install the AWS CLI:
   ```bash
   curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
   unzip awscliv2.zip
   sudo ./aws/install
   ```

2. Install Terraform:
   ```bash
   wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
   echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
   sudo apt update && sudo apt install terraform
   ```

3. Install Atmos CLI:
   ```bash
   curl -s https://raw.githubusercontent.com/cloudposse/atmos/master/scripts/install.sh | bash
   ```

#### macOS
1. Install the AWS CLI:
   ```bash
   curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
   sudo installer -pkg AWSCLIV2.pkg -target /
   ```

2. Install Terraform with Homebrew:
   ```bash
   brew tap hashicorp/tap
   brew install hashicorp/tap/terraform
   ```

3. Install Atmos CLI (choose one method):
   
   Using the install script:
   ```bash
   curl -s https://raw.githubusercontent.com/cloudposse/atmos/master/scripts/install.sh | bash
   ```
   
   Or using Homebrew:
   ```bash
   brew tap cloudposse/tap
   brew install atmos
   ```

4. Clone this repository:
   ```bash
   git clone https://github.com/your-org/tf-atmos.git
   cd tf-atmos
   ```

### Deployment Steps

1. Bootstrap the backend:
   ```bash
   atmos workflow bootstrap-backend tenant=mycompany region=us-west-2
   ```

2. Initialize and apply the backend configuration:
   ```bash
   atmos workflow apply-backend tenant=mycompany account=management environment=prod
   ```

3. Onboard a new environment:
   ```bash
   atmos workflow onboard-environment tenant=mycompany account=dev environment=testenv-01 vpc_cidr=10.1.0.0/16
   ```

4. Deploy an existing environment:
   ```bash
   atmos workflow apply-environment tenant=mycompany account=dev environment=testenv-01
   ```

## 4. Component Catalog

This infrastructure includes the following core components:

### Network Layer
- **VPC** - Virtual private cloud with public and private subnets
- **NAT Gateway** - For outbound internet access from private subnets
- **VPN Gateway** - For connectivity to on-premises networks
- **Transit Gateway** - For connecting multiple VPCs
- **DNS** - Route53 hosted zones, records, and health checks

### Infrastructure Layer
- **EC2** - Virtual servers with security groups and IAM profiles
- **ECS** - Container orchestration with Fargate support
- **RDS** - Managed relational databases with automated backups
- **Lambda** - Serverless functions with monitoring
- **Monitoring** - CloudWatch dashboards, alarms, and log groups
- **Secrets Manager** - Secure management of secrets and credentials

### Services Layer
- **API Gateway** - For creating and managing REST and HTTP APIs
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

1. Create a new directory under `components/terraform/`:
   ```bash
   mkdir -p components/terraform/new-component
   ```

2. Use the component template from the templates directory:
   ```bash
   cp -r templates/terraform-component/* components/terraform/new-component/
   ```

3. Create a corresponding catalog file in `stacks/catalog/`:
   ```bash
   cp templates/catalog-component.yaml stacks/catalog/new-component.yaml
   ```

4. Customize the files for your specific component.

### Adding a New Environment

1. Use the onboarding workflow:
   ```bash
   atmos workflow onboard-environment tenant=mycompany account=dev environment=newenv vpc_cidr=10.2.0.0/16
   ```

2. Customize the generated configurations as needed:
   ```bash
   cd stacks/account/dev/newenv
   # Edit the .yaml files as needed
   ```

### Modifying Existing Components

1. Make changes to the component code in `components/terraform/`
2. Update the corresponding catalog file if necessary
3. Run `atmos workflow plan-environment` to validate changes
4. Apply changes with `atmos workflow apply-environment`

## 7. Best Practices

- Use consistent naming conventions across all resources (singular form without hyphens for components)
- Follow the principle of least privilege for IAM policies
- Use the Secrets Manager component for secure storage of credentials and sensitive data
- Implement hierarchical secret organization with standardized paths (`context/environment/path/name`)
- Store sensitive values in SSM Parameter Store or Secrets Manager using `${ssm:/path/to/param}` syntax
- Use `templatefile()` for policy files instead of variable interpolation in JSON
- Leverage Atmos variables for environment-specific configurations 
- Use validation blocks to enforce proper input values
- Implement proper dependency management with `depends_on` and adequate wait times
- Use dynamic blocks for repetitive resource configurations
- Implement cost tagging for resource attribution
- Enable monitoring and alerting for all production environments 
- Use separate state files for different components
- Run regular drift detection to ensure configuration consistency

## 8. Contributing

Please follow these guidelines when contributing to the project:

1. Fork the repository and create a feature branch
   ```bash
   git checkout -b feature/my-new-feature
   ```

2. Make your changes and run validation before submitting:
   ```bash
   atmos workflow lint
   atmos workflow validate
   ```

3. Commit your changes with descriptive messages:
   ```bash
   git commit -m "Add my new feature with detailed description"
   ```

4. Push to your branch and create a Pull Request
   ```bash
   git push origin feature/my-new-feature
   ```

5. Include in your PR:
   - Description of the change
   - Any related issue numbers
   - Documentation updates
   - Test results if applicable

## 9. Documentation

Detailed documentation can be found in the `/docs` directory:

- [Atmos Guide](docs/Atmos.md) - Overview of Atmos architecture and principles
- [Terraform Development Guide](docs/tf-dev-guide.md) - Component development best practices
- [Route53 DNS Management](docs/Route53-Outline.md) - DNS architecture and patterns
- [API Gateway Integration](docs/api-gateway-integration-guide.md) - API Gateway patterns and integration
- [Secrets Manager Guide](docs/secrets-manager-guide.md) - Secure secrets management patterns and best practices
- [Workflows Reference](docs/workflows.md) - Workflow examples and usage
- [Component Creation Guide](docs/component-creation-guide.md) - Step-by-step guide to adding new components
- [Architecture Diagrams](docs/diagrams/) - Visual representations of architecture and workflows
- [Migration Guide](docs/migration-guide.md) - Steps for migrating existing infrastructure
- [Disaster Recovery Guide](docs/disaster-recovery-guide.md) - Backup and recovery procedures
- [Documentation Style Guide](docs/documentation-style-guide.md) - Standards for documentation
- [Project Roadmap](docs/roadmap.md) - Future plans, feature requests, and development goals

## 10. Support and Troubleshooting

### Common Issues

- **State Locking Issues**: If experiencing DynamoDB locking errors, verify the lock table and check for abandoned locks
  ```bash
  aws dynamodb scan --table-name <dynamo-table-name> --attributes-to-get LockID State
  ```

- **Cross-Account Access**: Ensure the correct assume_role_arn is set in the component variables

- **Missing Variables**: Verify that all required variables are defined in your stack configuration

- **Workflow Failures**: Check the logs with `atmos logs` to identify the specific error

### Getting Help

For questions or issues, please:

1. Check the documentation for guidance
2. Look at examples for similar configurations
3. Create an issue in the project repository with:
   - Description of the problem
   - Steps to reproduce
   - Expected vs actual behavior

## 11. License

This project is licensed under the MIT License - see the LICENSE file for details.

## 12. Roadmap

We maintain a detailed roadmap of planned features, enhancements, and future development for this project. The roadmap includes:

- **Current Development Focus**: Active development priorities for upcoming releases
- **Feature Requests**: Features requested by users and contributors
- **Technical Debt & Refactoring**: Areas identified for improvement
- **Documentation Improvements**: Planned documentation enhancements
- **Release Schedule**: Anticipated release dates and feature targets

For the complete roadmap, see [Project Roadmap](docs/roadmap.md).

To contribute to the roadmap or suggest new features:
1. Review the existing roadmap
2. Open an issue with the tag `roadmap-feedback`
3. Submit a pull request with your proposed changes or additions

We welcome community feedback to help prioritize our development efforts.