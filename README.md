# 🚀 Atmos-Managed AWS Infrastructure

![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)
![Terraform](https://img.shields.io/badge/terraform-%3E%3D1.0.0-623CE4.svg)
![Atmos](https://img.shields.io/badge/atmos-%3E%3D1.5.0-16A394.svg)
![AWS](https://img.shields.io/badge/AWS-%23FF9900.svg?style=flat&logo=amazon-aws&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green.svg)

A streamlined framework for deploying and managing multi-account AWS environments using Terraform and Atmos.

## ✨ Features

- Multi-account architecture with environment separation
- Ready-to-use infrastructure components
- Automated workflows for common operations
- Consistent resource organization and naming
- Advanced Kubernetes management with EKS
- Secure secret management patterns

## 🏗️ Components

We provide pre-built components for:

- **Networking**: VPC, DNS, Transit Gateway
- **Compute**: EC2, ECS, EKS, Lambda
- **Data**: RDS, DynamoDB
- **Security**: IAM, Secrets Manager, ACM
- **API**: API Gateway, Load Balancers
- **Observability**: CloudWatch dashboards and alarms

[View full component catalog →](docs/component-catalog.md)

## 🚦 Quick Start

### Prerequisites

- AWS CLI
- Terraform ≥ 1.0.0
- Atmos CLI ≥ 1.5.0

### Basic Commands

```bash
# Bootstrap backend infrastructure
atmos workflow bootstrap-backend tenant=mycompany region=us-west-2

# Deploy a new environment
atmos workflow onboard-environment tenant=mycompany account=dev environment=test vpc_cidr=10.1.0.0/16

# Apply changes to an environment
atmos workflow apply-environment tenant=mycompany account=dev environment=test
```

[Complete installation guide →](docs/installation.md)  
[Step-by-step deployment guide →](docs/deployment.md)

## 📚 Documentation

- [Architecture Overview](docs/architecture.md)
- [Component Development Guide](docs/tf-dev-guide.md)
- [Environment Onboarding](docs/environment-onboarding.md)
- [Workflow Reference](docs/workflows.md)
- [Security Best Practices](docs/security-best-practices.md)
- [Troubleshooting Guide](docs/troubleshooting-guide.md)

## 🌱 Getting Started with Development

```bash
# Clone the repository
git clone https://github.com/your-org/tf-atmos.git
cd tf-atmos

# Create a new component
cp -r templates/terraform-component/* components/terraform/new-component/

# Validate changes
atmos workflow lint
atmos workflow validate
```

[Component creation guide →](docs/component-creation-guide.md)

## 🤝 Contributing

We welcome contributions! Please check out our [contribution guidelines](docs/CONTRIBUTING.md) before submitting pull requests.

## 🛣️ Roadmap

See our [roadmap](docs/roadmap.md) for upcoming features and development plans.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.