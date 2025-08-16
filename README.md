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

**⏱️ Setup Time: < 30 minutes** | **📚 Full Setup Guide: [docs/SETUP.md](./docs/SETUP.md)**

## Project Architecture

This platform provides:

- **🏗️ 17 Production-Ready Components**: VPC, EKS, RDS, Lambda, Monitoring, Security, and more
- **🔄 16 Automated Workflows**: Environment onboarding, drift detection, compliance checks
- **🐍 Python CLI (Gaia)**: Simplified interface for common operations
- **🏢 Multi-Tenant Design**: Support for multiple organizations and environments
- **🔒 Security-First**: Encryption, IAM policies, certificate management
- **📊 Built-in Monitoring**: CloudWatch dashboards, alerting, cost optimization

## Core Components

| Component | Purpose | Status |
|-----------|---------|--------|
| **vpc** | Virtual Private Cloud and networking | ✅ Production |
| **eks** | Kubernetes clusters with best practices | ✅ Production |
| **eks-addons** | Ingress, monitoring, autoscaling | ✅ Production |
| **rds** | PostgreSQL databases with backups | ✅ Production |
| **monitoring** | CloudWatch dashboards and alarms | ✅ Production |
| **secretsmanager** | Secure configuration management | ✅ Production |
| **iam** | Cross-account roles and policies | ✅ Production |
| **lambda** | Serverless functions | ✅ Production |

[View all 17 components →](./components/terraform/)

## Prerequisites

| Tool | Version | Purpose |
|------|---------|----------|
| **Terraform** | 1.11.0+ | Infrastructure provisioning |
| **Atmos CLI** | 1.163.0+ | Stack management |
| **Python** | 3.11+ | Automation tooling |
| **AWS CLI** | 2.0+ | Cloud authentication |

**📖 Detailed installation instructions: [docs/SETUP.md](./docs/SETUP.md)**

## Usage

Use the Atmos workflows to manage your infrastructure. For detailed documentation on Gaia (the Python implementation), see [gaia/README.md](./gaia/README.md).

```bash
# Apply an environment
atmos workflow apply-environment tenant=acme account=prod environment=use1

# Plan an environment with drift detection
atmos workflow plan-environment tenant=acme account=prod environment=use1 detect_drift=true

# Validate components
atmos workflow validate tenant=acme account=prod environment=use1
```

## Project Structure

```
tf-atmos/
├── 📁 components/terraform/     # 17 Infrastructure Components
│   ├── vpc/                    # Virtual Private Cloud + Networking
│   ├── eks/                    # Kubernetes Clusters  
│   ├── eks-addons/             # K8s Add-ons (Ingress, Monitoring)
│   ├── rds/                    # PostgreSQL Databases
│   ├── monitoring/             # CloudWatch Dashboards
│   ├── secretsmanager/         # Configuration Management
│   └── ...                     # + 11 more components
├── 📁 stacks/                  # Environment Configurations
│   ├── catalog/                # Component Catalogs & Defaults
│   ├── mixins/                 # Reusable Configuration Patterns
│   └── orgs/                   # Tenant-Specific Stacks
├── 📁 workflows/               # 16 Automated Workflows  
│   ├── apply-environment.yaml  # Deploy Complete Environments
│   ├── drift-detection.yaml   # Infrastructure Drift Detection
│   └── onboard-environment.yaml # New Environment Setup
├── 📁 gaia/                    # Python CLI Automation Tool
├── 📁 scripts/                 # Developer Utilities
├── 📁 docs/                    # Documentation & Guides
└── 📁 examples/                # Usage Examples & Templates
```

## Key Features

### Atmos Workflows

The toolchain provides pre-defined Atmos workflows for common operations:

```bash
# Apply a complete environment
atmos workflow apply-environment tenant=acme account=prod environment=use1

# Plan changes with drift detection
atmos workflow plan-environment tenant=acme account=prod environment=use1 detect_drift=true

# Validate components
atmos workflow validate tenant=acme account=prod environment=use1

# Onboard a new environment
atmos workflow onboard-environment tenant=acme account=prod environment=use1 vpc_cidr=10.0.0.0/16

# Detect infrastructure drift
atmos workflow drift-detection tenant=acme account=prod environment=use1
```

### Environment Management

Create and manage environments using standard workflows:

```bash
# Onboard a new environment
atmos workflow onboard-environment tenant=acme account=prod environment=use1 vpc_cidr=10.0.0.0/16

# Update an existing environment configuration
atmos workflow update-environment-template tenant=acme account=prod environment=use1
```

### Configuration

The toolchain can be configured through environment variables or configuration files:
- `.atmos.env` in project root
- `.env` in project root
- `~/.atmos/config`

## 📚 Documentation

**📖 [Complete Documentation Portal](./docs/) - All documentation consolidated and organized**

| Guide | Description |
|-------|-------------|
| **[Setup Guide](./docs/operations/SETUP.md)** | Complete installation and first-time setup |
| **[Architecture Overview](./docs/architecture/ARCHITECTURE_DIAGRAM.md)** | System design and patterns |
| **[Component Guides](./docs/components/)** | Detailed component documentation |
| **[Developer Guide](./docs/guides/DEVELOPER_GUIDE.md)** | Development workflows and standards |
| **[Operations Guide](./docs/operations/)** | Troubleshooting and operational procedures |
| **[Templates & Examples](./docs/templates/)** | Infrastructure patterns and examples |

## 🆘 Getting Help

- **🐛 Issues**: Common problems → [docs/operations/TROUBLESHOOTING.md](./docs/operations/TROUBLESHOOTING.md)  
- **📖 Examples**: Real-world usage → [examples/](./examples/)
- **💬 Stack Resolution**: Use `./scripts/list_stacks.sh` to see available environments
- **🔍 Component Validation**: Run `atmos workflow validate` for comprehensive checks

## Working Stack Reference

- **Main Development**: `fnx-dev-testenv-01` (validated and working)
- **Test Commands**:
  ```bash
  atmos terraform plan vpc -s fnx-dev-testenv-01
  gaia list stacks
  ./scripts/list_stacks.sh
  ```

## Recent Improvements

- **✅ Stack Resolution**: Fixed component discovery issues
- **🚀 Performance**: Intelligent caching and optimized dependencies  
- **🔒 Security**: Resolved critical vulnerabilities
- **🛠️ Developer Experience**: Comprehensive onboarding documentation
- **📊 Monitoring**: Built-in dashboards and alerting

## License

MIT