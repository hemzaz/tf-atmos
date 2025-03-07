# 🚀 Atmos-Managed AWS Infrastructure

![Version](https://img.shields.io/badge/version-1.1.0-blue.svg)
![Terraform](https://img.shields.io/badge/terraform-%3E%3D1.11.0-623CE4.svg)
![Atmos](https://img.shields.io/badge/atmos-%3E%3D1.163.0-16A394.svg)
![Kubectl](https://img.shields.io/badge/kubectl-%3E%3D1.32.0-326CE5.svg)
![Helm](https://img.shields.io/badge/helm-%3E%3D3.13.1-0F1689.svg)
![AWS](https://img.shields.io/badge/AWS-%23FF9900.svg?style=flat&logo=amazon-aws&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green.svg)

A streamlined framework for deploying and managing multi-account AWS environments using Terraform and Atmos, following the latest Atmos design patterns and best practices.

## ✨ Features

- Multi-account architecture with environment separation
- Ready-to-use infrastructure components with explicit dependencies
- Automated workflows for common operations including compliance checks
- Stack inheritance with mixins and catalog components
- Component validation with JSON Schema
- Advanced Kubernetes management with EKS
- Secure secret management patterns
- Comprehensive documentation and examples

## 🏗️ Components

We provide pre-built components for:

- **Networking**: VPC, DNS, Transit Gateway
- **Compute**: EC2, ECS, EKS, Lambda
- **Data**: RDS, DynamoDB
- **Security**: IAM, Secrets Manager, ACM
- **API**: API Gateway, Load Balancers
- **Observability**: CloudWatch dashboards and alarms

[View full component catalog →](docs/terraform-component-catalog.md)

## 🚦 Quick Start

### Prerequisites

- AWS CLI
- Terraform ≥ 1.11.0
- Atmos CLI ≥ 1.163.0
- Kubectl ≥ 1.32.0
- Helm ≥ 3.13.1

> Tool versions are defined in the .env file at the root of this repository.

### Version Management

The project uses a `.env` file to manage tool and dependency versions. This file:
- Defines required versions for Terraform, Atmos, Kubectl, and other tools
- Is used by installation scripts and CI/CD pipelines
- Should be updated when upgrading dependencies

Example `.env` file:
```bash
TERRAFORM_VERSION=1.11.0
ATMOS_VERSION=1.163.0
KUBECTL_VERSION=1.32.0
HELM_VERSION=3.13.1
TFSEC_VERSION=1.28.13
TFLINT_VERSION=0.55.1
```

### Basic Commands

```bash
# Install dependencies
./scripts/install-dependencies.sh

# Bootstrap backend infrastructure
atmos workflow bootstrap-backend tenant=mycompany region=us-west-2

# Deploy a new environment
atmos workflow onboard-environment tenant=mycompany account=dev environment=test vpc_cidr=10.1.0.0/16

# Apply changes to an environment
atmos workflow apply-environment tenant=mycompany account=dev environment=test

# Run compliance checks
atmos workflow compliance-check tenant=mycompany account=dev environment=test
```

[Complete installation guide →](docs/installation.md)  
[Step-by-step deployment guide →](docs/deployment.md)

## 🛡️ Design Patterns

This project implements the latest Atmos design patterns:

- **Stack Inheritance** - Using catalog components with environment-specific overrides
- **Component Dependencies** - Explicit dependencies between components
- **Configuration Mixins** - Reusable configuration fragments for environment types
- **Schema Validation** - JSON Schema for stack validation
- **Metadata-driven Components** - Rich component metadata for better documentation
- **Advanced Workflows** - Including compliance and security checks

## 📚 Documentation

- [Architecture Overview](docs/architecture.md)
- [Atmos Guide](docs/atmos-guide.md)
- [Component Development Guide](docs/terraform-development-guide.md)
- [Environment Onboarding](docs/environment-onboarding.md)
- [Workflow Reference](docs/workflows.md)
- [Security Best Practices](docs/security-best-practices-guide.md)
- [Troubleshooting Guide](docs/troubleshooting-guide.md)

## 🌱 Getting Started with Development

```bash
# Clone the repository
git clone https://github.com/your-org/tf-atmos.git
cd tf-atmos

# Install dependencies
./scripts/install-dependencies.sh

# View or modify tool versions in the .env file
cat .env

# Update tool versions in .env (examples)
./scripts/update-versions.sh --all                           # View all tools and their versions
./scripts/update-versions.sh --check --group all             # Check for updates for all tools
./scripts/update-versions.sh TERRAFORM_VERSION               # Update Terraform to latest
./scripts/update-versions.sh --version 1.11.0 TERRAFORM_VERSION # Set specific version
./scripts/update-versions.sh --group core                    # Update all core tools to latest

# After updating .env, reinstall dependencies
./scripts/install-dependencies.sh

# Create a new component from template
cp -r templates/terraform-component/* components/terraform/new-component/

# Validate changes
atmos workflow lint
atmos workflow validate
atmos validate stacks --stack mycompany-dev-test
```

[Component creation guide →](docs/terraform-component-creation-guide.md)

## 🔍 Component Structure

Components follow a consistent structure with:

```
components/terraform/example-component/
├── README.md           # Documentation
├── main.tf             # Main resources
├── variables.tf        # Input variables with validation
├── outputs.tf          # Output values
├── locals.tf           # Local values
├── provider.tf         # Provider configuration
└── policies/           # IAM policies and templates
```

## 🤝 Contributing

We welcome contributions! Please check out our [contribution guidelines](docs/CONTRIBUTING.md) before submitting pull requests.

## 🛣️ Roadmap

See our [roadmap](docs/project-roadmap.md) for upcoming features and development plans.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.