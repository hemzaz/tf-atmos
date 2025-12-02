# Terraform Atmos Infrastructure Platform

Enterprise-grade infrastructure-as-code platform with **17 Terraform components**, **Python automation tooling**, and **multi-tenant architecture** for scalable cloud deployments.

---

## Quick Start

Get from zero to deployed infrastructure in minutes using our rapid deployment automation.

### Prerequisites Check

```bash
# Verify required tools
terraform version    # 1.11.0+
atmos version        # 1.163.0+
aws --version        # 2.0+
aws sts get-caller-identity  # Verify credentials
```

### Option 1: Deploy in 5 Minutes (Using Templates)

```bash
# 1. Create a new environment
./scripts/new-environment.sh \
  --tenant mycompany \
  --account dev \
  --environment testenv-01 \
  --region us-east-1 \
  --template web-application

# 2. Deploy using smart deployment script
./scripts/deploy-stack.sh \
  --template web-application \
  --stack mycompany-dev-testenv-01 \
  --auto-approve

# 3. Verify deployment
atmos terraform output vpc -s mycompany-dev-testenv-01
```

### Option 2: Interactive Setup

```bash
# Launch interactive environment wizard
./scripts/new-environment.sh --interactive

# Follow the prompts to:
# - Select tenant/organization
# - Choose environment type (dev/staging/prod)
# - Pick a stack template
# - Configure VPC and region
```

### Option 3: Step-by-Step Manual Deployment

```bash
# 1. Clone and setup
git clone https://github.com/example/tf-atmos.git
cd tf-atmos
cp .env.example .env

# 2. Install dependencies
./scripts/install-dependencies.sh

# 3. Configure AWS
aws configure
export AWS_REGION=us-east-1

# 4. Validate setup
atmos workflow validate

# 5. Deploy individual components
atmos terraform apply vpc -s mycompany-dev-testenv-01
atmos terraform apply securitygroup -s mycompany-dev-testenv-01
atmos terraform apply iam -s mycompany-dev-testenv-01
```

### Available Stack Templates

| Template | Use Case | Deploy Time | Monthly Cost |
|----------|----------|-------------|--------------|
| **web-application** | Web apps with VPC, RDS, monitoring | ~15 min | ~$150-800 |
| **microservices-platform** | EKS-based microservices | ~30 min | ~$300-2500 |
| **data-pipeline** | Lambda-based data processing | ~20 min | ~$50-300 |
| **serverless-api** | Serverless REST API | ~10 min | ~$20-100 |
| **batch-processing** | Batch job infrastructure | ~25 min | ~$30-200 |
| **minimal-stack** | Basic VPC and security | ~5 min | ~$50 |

**Full deployment guides: [docs/QUICK_DEPLOY.md](./docs/QUICK_DEPLOY.md)**

---

## Rapid Deployment Automation

### Smart Deployment Script

The `deploy-stack.sh` script provides intelligent deployment automation:

```bash
# Full deployment with progress tracking
./scripts/deploy-stack.sh --template microservices-platform \
  --stack mycompany-prod-prod-01 \
  --auto-approve

# Features:
# - Validates prerequisites (AWS credentials, Terraform, Atmos)
# - Deploys components in correct dependency order
# - Shows progress and estimated time remaining
# - Handles errors gracefully with rollback option
# - Generates deployment report

# Dry run to see deployment plan
./scripts/deploy-stack.sh --template web-application \
  --stack mycompany-dev-testenv-01 \
  --dry-run
```

### Environment Bootstrap Script

The `new-environment.sh` script creates complete environment configurations:

```bash
# Interactive mode
./scripts/new-environment.sh --interactive

# Or with all options
./scripts/new-environment.sh \
  --tenant mycompany \
  --account prod \
  --environment prod-01 \
  --region us-east-1 \
  --template full-stack \
  --env-type production \
  --vpc-cidr 10.20.0.0/16

# Creates:
# - Stack directory structure
# - Main stack configuration
# - Environment-specific variables
# - Backend configuration
# - Initializes Terraform workspace
```

### Template Deployment Workflow

Use Atmos workflows for consistent deployments:

```bash
# Deploy any template with validation
atmos workflow deploy-template -f deploy-template.yaml \
  template=web-application \
  tenant=mycompany \
  account=dev \
  environment=testenv-01 \
  auto_approve=true

# Quick deploy shortcuts
atmos workflow deploy-web-app -f deploy-template.yaml \
  tenant=mycompany account=dev environment=testenv-01

atmos workflow deploy-microservices -f deploy-template.yaml \
  tenant=mycompany account=prod environment=prod-01

atmos workflow deploy-serverless -f deploy-template.yaml \
  tenant=mycompany account=dev environment=api-01
```

---

## Project Architecture

This platform provides:

- **17 Production-Ready Components**: VPC, EKS, RDS, Lambda, Monitoring, Security, and more
- **20+ Automated Workflows**: Environment onboarding, drift detection, compliance checks, template deployment
- **Python CLI (Gaia)**: Simplified interface for common operations
- **Multi-Tenant Design**: Support for multiple organizations and environments
- **Security-First**: Encryption, IAM policies, certificate management
- **Built-in Monitoring**: CloudWatch dashboards, alerting, cost optimization
- **Rapid Deployment**: Deploy production infrastructure in minutes

---

## Core Components

| Component | Purpose | Status |
|-----------|---------|--------|
| **vpc** | Virtual Private Cloud and networking | Production |
| **eks** | Kubernetes clusters with best practices | Production |
| **eks-addons** | Ingress, monitoring, autoscaling | Production |
| **rds** | PostgreSQL/MySQL databases with backups | Production |
| **monitoring** | CloudWatch dashboards and alarms | Production |
| **secretsmanager** | Secure configuration management | Production |
| **iam** | Cross-account roles and policies | Production |
| **lambda** | Serverless functions | Production |
| **backup** | Automated backup and recovery | Production |
| **security-monitoring** | Security scanning and compliance | Production |
| **cost-optimization** | Cost monitoring and optimization | Production |

[View all 17 components](./components/terraform/)

---

## Prerequisites

### Required Tools

| Tool | Version | Purpose |
|------|---------|----------|
| **Terraform** | 1.11.0+ | Infrastructure provisioning |
| **Atmos CLI** | 1.163.0+ | Stack management |
| **Python** | 3.11+ | Automation tooling |
| **AWS CLI** | 2.0+ | Cloud authentication |
| **kubectl** | 1.28+ | Kubernetes management (for EKS) |

**Detailed installation: [docs/DEPLOYMENT_GUIDE.md#prerequisites](./docs/DEPLOYMENT_GUIDE.md#prerequisites)**

### Quick Installation

```bash
# macOS (using Homebrew)
brew install terraform awscli python@3.11
brew install cloudposse/tap/atmos
brew install kubectl helm jq

# Verify installations
terraform version
atmos version
aws --version
python3 --version
kubectl version --client

# Or use our installation script
./scripts/install-dependencies.sh
```

---

## Documentation

**Complete documentation portal: [docs/README.md](./docs/README.md)**

### Quick Links

| Document | Description |
|----------|-------------|
| **[Quick Deploy Guide](./docs/QUICK_DEPLOY.md)** | Deploy infrastructure in minutes |
| **[Deployment Guide](./docs/DEPLOYMENT_GUIDE.md)** | Complete deployment instructions |
| **[Operations Guide](./docs/OPERATIONS_GUIDE.md)** | Daily operations and maintenance |
| **[FAQ](./docs/FAQ.md)** | Frequently asked questions |
| **[Cost Estimation](./docs/COST_ESTIMATION.md)** | Cost analysis and optimization |

### Architecture Documentation

| Document | Description |
|----------|-------------|
| **[Architecture Overview](./docs/architecture/ARCHITECTURE_DIAGRAM.md)** | High-level system design |
| **[Network Architecture](./docs/architecture/NETWORK_ARCHITECTURE.md)** | VPC design and networking |
| **[Security Architecture](./docs/architecture/security-best-practices-guide.md)** | Security model and compliance |

### Component Documentation

- [VPC Component](./components/terraform/vpc/README.md)
- [EKS Component](./components/terraform/eks/README.md)
- [RDS Component](./components/terraform/rds/README.md)
- [All Components](./components/terraform/)

---

## Usage Examples

### Deploy Complete Environment

```bash
# Using deploy script (recommended)
./scripts/deploy-stack.sh \
  --template web-application \
  --stack mycompany-dev-testenv-01 \
  --auto-approve

# Using Atmos workflow
atmos workflow apply-environment \
  tenant=mycompany \
  account=dev \
  environment=testenv-01 \
  auto_approve=true
```

### Deploy Individual Components

```bash
# Plan changes
atmos terraform plan vpc -s mycompany-dev-testenv-01

# Apply changes
atmos terraform apply vpc -s mycompany-dev-testenv-01

# View outputs
atmos terraform output vpc -s mycompany-dev-testenv-01

# Destroy (with caution)
atmos terraform destroy vpc -s mycompany-dev-testenv-01
```

### Validate Infrastructure

```bash
# Validate all configurations
atmos workflow validate

# Lint configurations
atmos workflow lint

# Check for drift
atmos workflow drift-detection \
  tenant=mycompany \
  account=dev \
  environment=testenv-01
```

### List Available Stacks

```bash
# List all stacks
./scripts/list_stacks.sh

# Or using Atmos
atmos describe stacks

# View specific stack configuration
atmos describe component vpc -s mycompany-dev-testenv-01
```

---

## Project Structure

```
tf-atmos/
+-- components/terraform/     # 17 Infrastructure Components
|   +-- vpc/                  # Virtual Private Cloud + Networking
|   +-- eks/                  # Kubernetes Clusters
|   +-- rds/                  # Databases (PostgreSQL, MySQL, Aurora)
|   +-- lambda/               # Serverless Functions
|   +-- monitoring/           # CloudWatch Dashboards & Alarms
|   +-- ...                   # + 12 more components
+-- stacks/                   # Environment Configurations
|   +-- catalog/              # Component Catalogs & Defaults
|   |   +-- templates/        # Alexandria Library Templates
|   +-- mixins/               # Reusable Configuration Patterns
|   +-- orgs/                 # Tenant-Specific Stacks
+-- workflows/                # 20+ Automated Workflows
|   +-- deploy-template.yaml  # Template Deployment Workflow
|   +-- apply-environment.yaml
|   +-- drift-detection.yaml
|   +-- ...
+-- scripts/                  # Developer Utilities
|   +-- deploy-stack.sh       # Smart Deployment Script
|   +-- new-environment.sh    # Environment Bootstrap
|   +-- list_stacks.sh
|   +-- install-dependencies.sh
+-- docs/                     # Comprehensive Documentation
|   +-- QUICK_DEPLOY.md       # Fast Deployment Guides
|   +-- DEPLOYMENT_GUIDE.md
|   +-- OPERATIONS_GUIDE.md
+-- templates/                # Stack Templates
    +-- stacks/               # Pre-built Stack Templates
```

---

## Cost Estimation

### Monthly Cost by Environment

| Environment | Monthly Cost | Notes |
|------------|--------------|-------|
| **Development** | $495 | Single NAT, Spot instances |
| **Staging** | $1,195 | Single NAT, mixed instances |
| **Production** | $6,135 | Multi-AZ, Reserved Instances |

**With Optimizations: $2,479/month** (68% savings)

See [docs/COST_ESTIMATION.md](./docs/COST_ESTIMATION.md) for detailed breakdown.

---

## Security

### Security Features

- **Encryption at Rest**: KMS encryption for all data stores
- **Encryption in Transit**: TLS 1.3 for all connections
- **Network Isolation**: Private subnets for workloads
- **IAM Least Privilege**: Minimal necessary permissions
- **VPC Flow Logs**: Network traffic monitoring
- **GuardDuty**: Threat detection
- **AWS Config**: Compliance monitoring

### Security Compliance

- AWS Well-Architected Framework
- CIS AWS Foundations Benchmark
- PCI-DSS ready
- HIPAA eligible

See [docs/architecture/security-best-practices-guide.md](./docs/architecture/security-best-practices-guide.md) for details.

---

## Working Stack Reference

### Validated Working Stacks

- **Main Development**: `fnx-dev-testenv-01` (validated and working)
- **Test Commands**:
  ```bash
  atmos terraform plan vpc -s fnx-dev-testenv-01
  ./scripts/list_stacks.sh
  ```

---

## Getting Help

### Documentation

1. **[Quick Deploy Guide](./docs/QUICK_DEPLOY.md)** - Fast deployment
2. **[Deployment Guide](./docs/DEPLOYMENT_GUIDE.md)** - Complete setup
3. **[Operations Guide](./docs/OPERATIONS_GUIDE.md)** - Daily operations
4. **[FAQ](./docs/FAQ.md)** - Common questions

### Support

- File an issue in the repository
- Check FAQ for common problems
- Contact: platform-team@example.com

### Common Issues

```bash
# Terraform state locked?
terraform force-unlock <lock-id>

# kubectl can't connect?
aws eks update-kubeconfig --name <cluster-name> --region <region>

# Need to see all stacks?
./scripts/list_stacks.sh

# Validate everything?
atmos workflow validate
```

---

## Quick Reference Commands

```bash
# Create new environment
./scripts/new-environment.sh --interactive

# Deploy template
./scripts/deploy-stack.sh --template <template> --stack <stack> --auto-approve

# Validation
atmos workflow validate                              # Validate all
atmos workflow lint                                  # Lint code

# Environment Management
atmos workflow deploy-template -f deploy-template.yaml template=<tmpl> tenant=<t> account=<a> environment=<e>
atmos workflow destroy-environment tenant=<t> account=<a> environment=<e>

# Component Operations
atmos terraform plan <component> -s <stack>         # Plan component
atmos terraform apply <component> -s <stack>        # Apply component
atmos terraform output <component> -s <stack>       # View outputs

# Utilities
./scripts/list_stacks.sh                            # List stacks
atmos describe component <component> -s <stack>     # Component details
```

---

## Contributing

### Development Workflow

1. Fork the repository
2. Create feature branch: `git checkout -b feature/my-feature`
3. Make changes following standards
4. Test: `atmos workflow validate`
5. Lint: `atmos workflow lint`
6. Commit: `git commit -m "feat: add feature"`
7. Push: `git push origin feature/my-feature`
8. Create Pull Request

### Code Standards

- Follow Terraform best practices
- Use snake_case for resources and variables
- Include validation blocks for inputs
- Document all variables and outputs
- Write comprehensive README for components

---

## Roadmap

### Q1 2025
- [ ] GitOps integration (ArgoCD/Flux)
- [ ] Multi-cloud support (Azure, GCP)
- [ ] Enhanced cost optimization automation

### Q2 2025
- [ ] Service mesh integration (Istio)
- [ ] Advanced observability (Prometheus, Grafana)
- [ ] Policy as code (OPA)

---

## License

MIT License - see [LICENSE](./LICENSE) file for details.

---

## Acknowledgments

- Built with [Terraform](https://www.terraform.io/)
- Orchestrated with [Atmos](https://atmos.tools/)
- Managed on [AWS](https://aws.amazon.com/)

---

**Version**: 2.1.0
**Last Updated**: 2025-12-02
**Maintained By**: Platform Team
**Status**: Production Ready

---

**Need help?** Start with the [Quick Deploy Guide](./docs/QUICK_DEPLOY.md) or [Deployment Guide](./docs/DEPLOYMENT_GUIDE.md)
