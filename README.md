# Terraform Atmos Infrastructure Platform

Enterprise-grade infrastructure-as-code platform with **17 Terraform components**, **Python automation tooling**, and **multi-tenant architecture** for scalable cloud deployments.

## 🚀 Quick Start

```bash
# 1. Clone and setup
git clone https://github.com/example/tf-atmos.git
cd tf-atmos
cp .env.example .env

# 2. Install dependencies
./scripts/install-dependencies.sh

# 3. Validate setup
atmos workflow validate

# 4. Test with example stack
atmos terraform plan vpc -s fnx-dev-testenv-01
```

**⏱️ Setup Time: < 30 minutes** | **📚 Full Setup Guide: [docs/DEPLOYMENT_GUIDE.md](./docs/DEPLOYMENT_GUIDE.md)**

---

## Project Architecture

This platform provides:

- **🏗️ 17 Production-Ready Components**: VPC, EKS, RDS, Lambda, Monitoring, Security, and more
- **🔄 16 Automated Workflows**: Environment onboarding, drift detection, compliance checks
- **🐍 Python CLI (Gaia)**: Simplified interface for common operations
- **🏢 Multi-Tenant Design**: Support for multiple organizations and environments
- **🔒 Security-First**: Encryption, IAM policies, certificate management
- **📊 Built-in Monitoring**: CloudWatch dashboards, alerting, cost optimization

---

## Core Components

| Component | Purpose | Status |
|-----------|---------|--------|
| **vpc** | Virtual Private Cloud and networking | ✅ Production |
| **eks** | Kubernetes clusters with best practices | ✅ Production |
| **eks-addons** | Ingress, monitoring, autoscaling | ✅ Production |
| **rds** | PostgreSQL/MySQL databases with backups | ✅ Production |
| **monitoring** | CloudWatch dashboards and alarms | ✅ Production |
| **secretsmanager** | Secure configuration management | ✅ Production |
| **iam** | Cross-account roles and policies | ✅ Production |
| **lambda** | Serverless functions | ✅ Production |
| **backup** | Automated backup and recovery | ✅ Production |
| **security-monitoring** | Security scanning and compliance | ✅ Production |
| **cost-optimization** | Cost monitoring and optimization | ✅ Production |

[View all 17 components →](./components/terraform/)

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

**📖 Detailed installation: [docs/DEPLOYMENT_GUIDE.md#prerequisites](./docs/DEPLOYMENT_GUIDE.md#prerequisites)**

### Quick Installation

```bash
# macOS (using Homebrew)
brew install terraform awscli python@3.11
brew install cloudposse/tap/atmos
brew install kubectl helm

# Verify installations
terraform version
atmos version
aws --version
python3 --version
kubectl version --client
```

---

## Configuration

### Environment Setup

```bash
# Configure AWS credentials
aws configure

# Set project variables
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export TENANT=mycompany
export ENVIRONMENT=dev

# Source configuration
source .env
```

### Project Configuration Files

```
.
├── .atmos.yaml                 # Atmos CLI configuration
├── atmos.yaml                 # Stack configuration (legacy)
├── .env                       # Environment variables
└── stacks/
    ├── catalog/               # Component defaults
    │   ├── vpc/defaults.yaml
    │   ├── eks/defaults.yaml
    │   └── ...
    ├── mixins/                # Reusable patterns
    │   ├── region/us-east-1.yaml
    │   └── tags/common.yaml
    └── orgs/                  # Tenant configurations
        └── mycompany/
            └── dev/
                └── use1/
                    └── main.yaml
```

---

## Usage Examples

### Deploy Complete Environment

```bash
# Deploy all components for an environment
atmos workflow apply-environment \
  tenant=mycompany \
  account=dev \
  environment=use1

# This deploys (in order):
# 1. Backend (S3 + DynamoDB)
# 2. VPC with subnets and routing
# 3. IAM roles and policies
# 4. Security groups
# 5. EKS cluster and node groups
# 6. RDS database
# 7. Monitoring and logging
# 8. Additional components
```

### Deploy Individual Components

```bash
# Plan changes
atmos terraform plan vpc -s mycompany-dev-use1

# Apply changes
atmos terraform apply vpc -s mycompany-dev-use1

# View outputs
atmos terraform output vpc -s mycompany-dev-use1

# Destroy (with caution)
atmos terraform destroy vpc -s mycompany-dev-use1
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
  environment=use1
```

### List Available Stacks

```bash
# List all stacks
atmos describe stacks

# User-friendly stack listing
./scripts/list_stacks.sh

# View specific stack configuration
atmos describe component vpc -s mycompany-dev-use1
```

### Environment Management

```bash
# Create new environment
./scripts/create-environment.sh \
  --tenant mycompany \
  --account prod \
  --environment use1 \
  --vpc-cidr 10.20.0.0/16

# Onboard new environment
atmos workflow onboard-environment \
  tenant=mycompany \
  account=prod \
  environment=use1 \
  vpc_cidr=10.20.0.0/16

# Destroy environment
atmos workflow destroy-environment \
  tenant=mycompany \
  account=dev \
  environment=use1
```

---

## 📚 Documentation

**Complete documentation portal: [docs/README.md](./docs/README.md)**

### Quick Links

| Document | Description |
|----------|-------------|
| **[Deployment Guide](./docs/DEPLOYMENT_GUIDE.md)** | Complete deployment instructions from scratch |
| **[Operations Guide](./docs/OPERATIONS_GUIDE.md)** | Daily operations, maintenance, and troubleshooting |
| **[FAQ](./docs/FAQ.md)** | Frequently asked questions and answers |
| **[Cost Estimation](./docs/COST_ESTIMATION.md)** | Detailed cost analysis and optimization strategies |
| **[Variable Reference](./docs/VARIABLE_REFERENCE.md)** | Complete variable documentation for all components |

### Architecture Documentation

| Document | Description |
|----------|-------------|
| **[Architecture Overview](./docs/architecture/ARCHITECTURE_DIAGRAM.md)** | High-level system design and diagrams |
| **[Network Architecture](./docs/architecture/NETWORK_ARCHITECTURE.md)** | VPC design, subnets, routing, and networking |
| **[Security Architecture](./docs/architecture/security-best-practices-guide.md)** | Security model, IAM, encryption, and compliance |
| **[Deployment Architecture](./docs/architecture/DEPLOYMENT_ARCHITECTURE_GUIDE.md)** | Deployment patterns and strategies |

### Component Documentation

Each component has detailed documentation:

- [VPC Component](./components/terraform/vpc/README.md)
- [EKS Component](./components/terraform/eks/README.md)
- [RDS Component](./components/terraform/rds/README.md)
- [Monitoring Component](./components/terraform/monitoring/README.md)
- [IAM Component](./components/terraform/iam/README.md)
- [Lambda Component](./components/terraform/lambda/README.md)
- [All Components →](./components/terraform/)

---

## Project Structure

```
tf-atmos/
├── 📁 components/terraform/     # 17 Infrastructure Components
│   ├── vpc/                    # Virtual Private Cloud + Networking
│   ├── eks/                    # Kubernetes Clusters
│   ├── eks-addons/             # K8s Add-ons (Ingress, Monitoring)
│   ├── rds/                    # Databases (PostgreSQL, MySQL, Aurora)
│   ├── monitoring/             # CloudWatch Dashboards & Alarms
│   ├── security-monitoring/    # Security Scanning & Compliance
│   ├── backup/                 # Backup & Recovery
│   ├── cost-optimization/      # Cost Monitoring & Optimization
│   ├── secretsmanager/         # Secrets Management
│   ├── iam/                    # IAM Roles & Policies
│   ├── lambda/                 # Serverless Functions
│   ├── apigateway/             # API Gateway
│   ├── dns/                    # Route 53 DNS
│   ├── acm/                    # Certificate Manager
│   ├── external-secrets/       # External Secrets Operator
│   ├── securitygroup/          # Security Groups
│   └── backend/                # S3 + DynamoDB Backend
├── 📁 stacks/                  # Environment Configurations
│   ├── catalog/                # Component Catalogs & Defaults
│   ├── mixins/                 # Reusable Configuration Patterns
│   └── orgs/                   # Tenant-Specific Stacks
├── 📁 workflows/               # 16 Automated Workflows
│   ├── apply-environment.yaml  # Deploy Complete Environments
│   ├── plan-environment.yaml   # Plan All Components
│   ├── drift-detection.yaml    # Infrastructure Drift Detection
│   ├── onboard-environment.yaml # New Environment Setup
│   ├── destroy-environment.yaml # Teardown Environments
│   ├── validate.yaml           # Validate Configurations
│   ├── lint.yaml               # Lint Terraform Files
│   ├── compliance-check.yaml   # Compliance Validation
│   └── ...                     # + 8 more workflows
├── 📁 gaia/                    # Python CLI Automation Tool
│   ├── src/gaia/               # Source code
│   ├── tests/                  # Test suite
│   └── README.md               # Gaia documentation
├── 📁 scripts/                 # Developer Utilities
│   ├── list_stacks.sh          # List available stacks
│   ├── install-dependencies.sh # Install required tools
│   ├── create-environment.sh   # Create new environment
│   └── ...                     # + more utility scripts
├── 📁 docs/                    # Comprehensive Documentation
│   ├── DEPLOYMENT_GUIDE.md     # Complete deployment guide
│   ├── OPERATIONS_GUIDE.md     # Operations and maintenance
│   ├── FAQ.md                  # Frequently asked questions
│   ├── COST_ESTIMATION.md      # Cost analysis
│   ├── VARIABLE_REFERENCE.md   # Variable documentation
│   ├── architecture/           # Architecture documentation
│   ├── components/             # Component guides
│   ├── guides/                 # User guides
│   ├── operations/             # Operational procedures
│   └── workflows/              # Workflow documentation
└── 📁 examples/                # Usage Examples & Templates
```

---

## Key Features

### Multi-Tenant Architecture

Support multiple organizations and environments with isolated infrastructure:

```yaml
# Organization hierarchy
orgs/
  ├── company-a/
  │   ├── dev/
  │   ├── staging/
  │   └── prod/
  └── company-b/
      ├── dev/
      └── prod/
```

### Automated Workflows

Pre-built workflows for common operations:

```bash
# Complete environment lifecycle
atmos workflow onboard-environment      # Create new environment
atmos workflow apply-environment        # Deploy infrastructure
atmos workflow drift-detection          # Detect configuration drift
atmos workflow compliance-check         # Run compliance checks
atmos workflow destroy-environment      # Teardown environment

# Validation and testing
atmos workflow validate                 # Validate all configurations
atmos workflow lint                     # Lint Terraform code
atmos workflow enhanced-validation      # Deep validation

# Operations
atmos workflow rotate-certificate       # Rotate SSL certificates
atmos workflow bootstrap-backend        # Initialize Terraform backend
atmos workflow state-operations         # State management
```

### Python CLI (Gaia)

Simplified command-line interface for common tasks:

```bash
# Install Gaia
pip install -e ./gaia

# List stacks
gaia list stacks

# Validate infrastructure
gaia workflow validate \
  --tenant mycompany \
  --account dev \
  --environment use1

# Run workflows
gaia workflow apply-environment \
  --tenant mycompany \
  --account dev \
  --environment use1
```

See [gaia/README.md](./gaia/README.md) for complete Gaia documentation.

---

## Cost Estimation

### Monthly Cost by Environment

| Environment | Monthly Cost | Notes |
|------------|--------------|-------|
| **Development** | $495 | Single NAT, Spot instances, minimal resources |
| **Staging** | $1,195 | Single NAT, mixed instances, moderate resources |
| **Production** | $6,135 | Multi-AZ, Reserved Instances, full redundancy |
| **Total** | **$7,825** | For 3 environments |

**With Optimizations: $2,479/month** (68% savings)

See [docs/COST_ESTIMATION.md](./docs/COST_ESTIMATION.md) for detailed breakdown and optimization strategies.

### Cost Optimization Features

- Spot instances for development/staging (70% savings)
- Auto-scaling with Karpenter
- Aurora Serverless for non-production databases
- S3 Intelligent Tiering
- VPC Endpoints to reduce data transfer
- Single NAT Gateway for non-production
- Auto-shutdown schedules for development

---

## Security

### Security Features

- **Encryption at Rest**: KMS encryption for all data stores
- **Encryption in Transit**: TLS 1.3 for all connections
- **Network Isolation**: Private subnets for workloads
- **IAM Least Privilege**: Minimal necessary permissions
- **Security Groups**: Stateful firewall rules
- **Network ACLs**: Subnet-level network filtering
- **VPC Flow Logs**: Network traffic monitoring
- **GuardDuty**: Threat detection
- **AWS Config**: Compliance monitoring
- **Secrets Management**: Centralized secret storage

### Security Compliance

- AWS Well-Architected Framework
- CIS AWS Foundations Benchmark
- PCI-DSS ready
- HIPAA eligible
- SOC 2 compliant infrastructure

See [docs/architecture/security-best-practices-guide.md](./docs/architecture/security-best-practices-guide.md) for details.

---

## Working Stack Reference

### Validated Working Stacks

- **Main Development**: `fnx-dev-testenv-01` (validated and working)
- **Test Commands**:
  ```bash
  atmos terraform plan vpc -s fnx-dev-testenv-01
  atmos terraform output vpc -s fnx-dev-testenv-01
  gaia list stacks
  ./scripts/list_stacks.sh
  ```

---

## Getting Help

### Documentation

1. **[Deployment Guide](./docs/DEPLOYMENT_GUIDE.md)** - Start here for setup
2. **[Operations Guide](./docs/OPERATIONS_GUIDE.md)** - Daily operations
3. **[FAQ](./docs/FAQ.md)** - Common questions
4. **[Troubleshooting](./docs/operations/TROUBLESHOOTING.md)** - Common issues

### Support Channels

- File an issue in the repository
- Check FAQ for common problems
- Review component-specific READMEs
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
- Add examples in component documentation

See [docs/reference/terraform-development-standards.md](./docs/reference/terraform-development-standards.md) for complete standards.

---

## Recent Improvements

- ✅ **Documentation Overhaul**: Complete documentation suite with deployment, operations, and architecture guides
- ✅ **Cost Optimization**: Detailed cost analysis and optimization strategies
- ✅ **Stack Resolution**: Fixed component discovery issues
- ✅ **Performance**: Intelligent caching and optimized dependencies
- ✅ **Security**: Resolved critical vulnerabilities
- ✅ **Developer Experience**: Comprehensive onboarding documentation
- ✅ **Monitoring**: Built-in dashboards and alerting

---

## Roadmap

### Q1 2025
- [ ] GitOps integration (ArgoCD/Flux)
- [ ] Multi-cloud support (Azure, GCP)
- [ ] Enhanced cost optimization automation
- [ ] Improved disaster recovery automation

### Q2 2025
- [ ] Service mesh integration (Istio)
- [ ] Advanced observability (Prometheus, Grafana)
- [ ] Policy as code (OPA)
- [ ] Automated security scanning

---

## License

MIT License - see [LICENSE](./LICENSE) file for details.

---

## Acknowledgments

- Built with [Terraform](https://www.terraform.io/)
- Orchestrated with [Atmos](https://atmos.tools/)
- Managed on [AWS](https://aws.amazon.com/)
- Inspired by AWS Well-Architected Framework

---

**Version**: 2.0.0
**Last Updated**: 2025-12-02
**Maintained By**: Platform Team
**Status**: Production Ready

---

## Quick Reference Commands

```bash
# Validation
atmos workflow validate                              # Validate all
atmos workflow lint                                  # Lint code
atmos workflow drift-detection                       # Check drift

# Environment Management
atmos workflow onboard-environment                   # Create new
atmos workflow apply-environment                     # Deploy all
atmos workflow destroy-environment                   # Teardown

# Component Operations
atmos terraform plan <component> -s <stack>         # Plan component
atmos terraform apply <component> -s <stack>        # Apply component
atmos terraform output <component> -s <stack>       # View outputs

# Utilities
./scripts/list_stacks.sh                            # List stacks
gaia list stacks                                    # List (Python)
atmos describe component <component> -s <stack>     # Component details
```

**Need help?** Start with the [Deployment Guide](./docs/DEPLOYMENT_GUIDE.md) or [FAQ](./docs/FAQ.md)
