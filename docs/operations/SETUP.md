# Developer Setup Guide

Get up and running with the Terraform/Atmos infrastructure project in under 30 minutes.

## Quick Start

```bash
# 1. Clone and navigate to project
git clone https://github.com/example/tf-atmos.git
cd tf-atmos

# 2. Copy environment template
cp .env.example .env

# 3. Install dependencies
./scripts/install-dependencies.sh

# 4. Validate installation
atmos workflow validate

# 5. Test with example stack
atmos terraform plan vpc -s fnx-dev-testenv-01
```

## Prerequisites

### Required Tools

| Tool | Minimum Version | Installation | Purpose |
|------|----------------|--------------|----------|
| **Terraform** | 1.11.0 | [terraform.io](https://terraform.io/downloads) | Infrastructure provisioning |
| **Atmos CLI** | 1.163.0+ | [atmos.tools](https://atmos.tools/install) | Stack management |
| **Python** | 3.11+ | [python.org](https://python.org/downloads) | Gaia CLI tooling |
| **AWS CLI** | 2.0+ | [aws.amazon.com](https://aws.amazon.com/cli/) | AWS authentication |
| **Git** | 2.0+ | [git-scm.com](https://git-scm.com/downloads) | Version control |

### Optional Tools (Recommended)

| Tool | Purpose | Installation |
|------|----------|--------------|
| **Docker** | Local development environment | [docker.com](https://docker.com/get-started) |
| **jq** | JSON processing | `brew install jq` / `apt install jq` |
| **yq** | YAML processing | `brew install yq` / `pip install yq` |

## Installation Instructions

### macOS (Homebrew)

```bash
# Core tools
brew install terraform atmos python@3.11 awscli git

# Optional tools
brew install docker jq yq

# Verify versions
terraform version  # Should be 1.11.0+
atmos version     # Should be 1.163.0+
python3 --version # Should be 3.11+
```

### Linux (Ubuntu/Debian)

```bash
# Update package list
sudo apt update

# Install dependencies
sudo apt install -y curl unzip git python3.11 python3.11-pip

# Install Terraform
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt update && sudo apt install terraform=1.11.0-1

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install

# Install Atmos CLI
curl -sSL https://get.atmos.tools/install.sh | bash

# Verify installations
terraform version
atmos version
python3.11 --version
aws --version
```

### Windows (PowerShell)

```powershell
# Install Chocolatey (if not already installed)
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Install tools
choco install terraform --version=1.11.0
choco install python --version=3.11.0
choco install awscli
choco install git

# Install Atmos CLI manually
# Download from: https://github.com/cloudposse/atmos/releases
# Add to PATH
```

## Environment Setup

### 1. AWS Configuration

Configure your AWS credentials for the development environment:

```bash
# Configure AWS CLI (interactive)
aws configure

# Or set environment variables
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-west-2"
export AWS_ACCOUNT_ID="123456789012"
```

### 2. Environment Variables

Copy the environment template and customize for your setup:

```bash
# Copy template
cp .env.example .env

# Edit with your values
vim .env  # or use your preferred editor
```

**Required variables in `.env`:**

```bash
# AWS Configuration
AWS_ACCOUNT_ID=123456789012
AWS_REGION=us-west-2
AWS_DEFAULT_REGION=us-west-2

# Optional: AWS Management Account (for cross-account access)
AWS_MANAGEMENT_ACCOUNT_ID=999999999999

# Project Configuration
PROJECT_NAME=tf-atmos
TENANT=fnx
ENVIRONMENT=dev
```

### 3. Python Environment Setup

Set up the Gaia CLI tool:

```bash
# Navigate to project directory
cd tf-atmos

# Install Python dependencies
pip install -e ./gaia

# Or use virtual environment (recommended)
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -e ./gaia

# Verify installation
gaia --help
```

## First-Time Project Setup

### 1. Validate Installation

```bash
# Validate Atmos configuration
atmos validate component vpc -s fnx-dev-testenv-01

# Run linting
atmos workflow lint

# Validate all components
atmos workflow validate
```

### 2. Test Component Operations

```bash
# Plan a simple component
atmos terraform plan vpc -s fnx-dev-testenv-01

# List available stacks
./scripts/list_stacks.sh

# Test Gaia CLI
gaia list stacks
gaia workflow validate
```

### 3. Initialize Development Environment (Optional)

For full development environment with monitoring and services:

```bash
# Run development setup script
./scripts/dev-setup.sh

# Start development services
./scripts/start-dev.sh

# Access services:
# - Backstage UI: http://localhost:3000
# - Grafana: http://localhost:3001
# - Prometheus: http://localhost:9090
```

## Project Structure Overview

```
tf-atmos/
├── components/terraform/     # Terraform components (17 total)
│   ├── vpc/                 # Virtual Private Cloud
│   ├── eks/                 # Kubernetes clusters
│   ├── rds/                 # Databases
│   └── ...                  # Other infrastructure components
├── stacks/                  # Environment configurations
│   ├── catalog/             # Component catalogs
│   ├── mixins/              # Reusable configurations
│   └── orgs/                # Organization-specific stacks
├── workflows/               # Atmos workflows (16 total)
├── gaia/                    # Python CLI tool
├── scripts/                 # Utility scripts
├── docs/                    # Documentation
└── examples/                # Usage examples
```

## Common Commands

### Atmos Workflows

```bash
# Validate all configurations
atmos workflow validate

# Lint code (terraform fmt + yamllint)
atmos workflow lint

# Plan an environment
atmos workflow plan-environment tenant=fnx account=dev environment=testenv-01

# Apply changes to an environment
atmos workflow apply-environment tenant=fnx account=dev environment=testenv-01

# Detect configuration drift
atmos workflow drift-detection
```

### Gaia CLI Commands

```bash
# Quick validation
gaia workflow validate

# Component operations
gaia terraform plan vpc --stack fnx-dev-testenv-01
gaia terraform apply eks --stack fnx-dev-testenv-01

# Stack management
gaia list stacks
gaia describe stack --stack fnx-dev-testenv-01
```

### Direct Terraform Commands

```bash
# Plan a specific component
atmos terraform plan vpc -s fnx-dev-testenv-01

# Apply with auto-approve
atmos terraform apply vpc -s fnx-dev-testenv-01 --auto-approve

# Show terraform output
atmos terraform output vpc -s fnx-dev-testenv-01
```

## Development Workflow

### 1. Daily Development

```bash
# Start your day
atmos workflow validate        # Ensure everything is valid
git pull origin master       # Get latest changes

# Make changes to components
vim components/terraform/vpc/main.tf

# Test changes
atmos terraform plan vpc -s fnx-dev-testenv-01

# Validate and lint
atmos workflow lint
atmos workflow validate

# Commit changes
git add .
git commit -m "Update VPC configuration"
```

### 2. Adding New Components

```bash
# Create component from template
cp -r templates/terraform-component components/terraform/new-component

# Add to stack configuration
vim stacks/catalog/new-component/defaults.yaml

# Test the component
atmos terraform plan new-component -s fnx-dev-testenv-01
```

### 3. Environment Management

```bash
# Create new environment
atmos workflow onboard-environment tenant=fnx account=dev environment=new-env vpc_cidr=10.1.0.0/16

# Plan all components in environment
atmos workflow plan-environment tenant=fnx account=dev environment=new-env

# Apply environment
atmos workflow apply-environment tenant=fnx account=dev environment=new-env
```

## IDE Setup

### VS Code Configuration

Create `.vscode/settings.json`:

```json
{
  "terraform.languageServer.enable": true,
  "terraform.codelens.referenceCount": true,
  "yaml.schemas": {
    "file:///path/to/atmos-schema.json": [
      "stacks/**/*.yaml"
    ]
  },
  "files.associations": {
    "*.tfvars": "terraform",
    "*.tf": "terraform"
  },
  "editor.formatOnSave": true,
  "[terraform]": {
    "editor.defaultFormatter": "hashicorp.terraform"
  },
  "[yaml]": {
    "editor.defaultFormatter": "redhat.vscode-yaml"
  }
}
```

**Recommended Extensions:**
- HashiCorp Terraform
- YAML
- GitLens
- Python
- Docker

## Verification Checklist

Before you start development, verify everything is working:

- [ ] `terraform version` shows 1.11.0+
- [ ] `atmos version` shows 1.163.0+
- [ ] `python3 --version` shows 3.11+
- [ ] `aws configure list` shows your credentials
- [ ] `atmos workflow validate` passes
- [ ] `atmos terraform plan vpc -s fnx-dev-testenv-01` works
- [ ] `gaia --help` displays CLI options
- [ ] `./scripts/list_stacks.sh` shows available stacks

## Next Steps

1. **Read Documentation**: Browse `/docs` for detailed guides
2. **Explore Examples**: Check `/examples` for common patterns
3. **Join Development**: See `CONTRIBUTING.md` for contribution guidelines
4. **Get Support**: Use `docs/TROUBLESHOOTING.md` for common issues

## Quick Reference

### Stack Names
- `fnx-dev-testenv-01` - Main development environment
- `fnx-staging-use1` - Staging environment (US East)
- `fnx-prod-uw2` - Production environment (US West)

### Key Components
- `vpc` - Virtual Private Cloud and networking
- `eks` - Kubernetes clusters
- `eks-addons` - Kubernetes add-ons (ingress, monitoring, etc.)
- `rds` - PostgreSQL databases
- `monitoring` - CloudWatch dashboards and alarms
- `secretsmanager` - Secrets and configuration management

### Important Files
- `atmos.yaml` - Main Atmos configuration
- `.env` - Environment variables
- `stacks/orgs/fnx/dev/eu-west-2/testenv-01.yaml` - Main dev stack
- `CLAUDE.md` - Development guidelines and standards