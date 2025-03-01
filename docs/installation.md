# Installation Guide

This guide provides detailed instructions for installing all prerequisites and setting up the Atmos-managed AWS infrastructure framework.

## Prerequisites

### AWS Account Access

You need AWS accounts with administrative access for:
- Management account (for centralized resources)
- At least one workload account (dev, staging, prod, etc.)

### Required Tools

| Tool | Version | Purpose |
|------|---------|---------|
| AWS CLI | 2.x | Interact with AWS services |
| Terraform | ≥ 1.5.7 | Infrastructure provisioning |
| Atmos CLI | ≥ 1.38.0 | Workflow orchestration |
| Kubectl | ≥ 1.28.3 | Kubernetes CLI |
| Helm | ≥ 3.13.1 | Kubernetes package manager |
| Git | Any recent | Version control |

> Note: Version numbers are defined in the `.env` file at the project root and can be customized as needed.

## Automated Installation

We provide a cross-platform installation script that automatically detects your operating system and installs the required dependencies:

```bash
#!/usr/bin/env bash
# Run the automated installation script
./scripts/install-dependencies.sh
```

The script uses version information from the `.env` file in the project root. You can override specific versions by setting environment variables:

```bash
TERRAFORM_VERSION="1.6.0" ./scripts/install-dependencies.sh
```

## Manual Installation Instructions

### Linux (Debian/Ubuntu)

1. **Install AWS CLI**
   ```bash
   curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
   unzip awscliv2.zip
   sudo ./aws/install
   aws --version
   ```

2. **Install Terraform**
   ```bash
   wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
   echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
   sudo apt update && sudo apt install terraform
   terraform -version
   ```

3. **Install Atmos CLI**
   ```bash
   curl -s https://raw.githubusercontent.com/cloudposse/atmos/master/scripts/install.sh | bash
   atmos --version
   ```

### Linux (RHEL/CentOS/Fedora)

1. **Install AWS CLI**
   ```bash
   curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
   unzip awscliv2.zip
   sudo ./aws/install
   aws --version
   ```

2. **Install Terraform**
   ```bash
   sudo yum install -y yum-utils
   sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
   sudo yum install terraform
   terraform -version
   ```

3. **Install Atmos CLI**
   ```bash
   curl -s https://raw.githubusercontent.com/cloudposse/atmos/master/scripts/install.sh | bash
   atmos --version
   ```

### macOS

1. **Install AWS CLI**
   ```bash
   curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
   sudo installer -pkg AWSCLIV2.pkg -target /
   aws --version
   ```

2. **Install Terraform**
   ```bash
   brew tap hashicorp/tap
   brew install hashicorp/tap/terraform
   terraform -version
   ```

3. **Install Atmos CLI**
   ```bash
   brew tap cloudposse/tap
   brew install atmos
   atmos --version
   ```

### Windows

> Note: The automated installation script also works on Windows when using Git Bash or Windows Subsystem for Linux (WSL).

1. **Install AWS CLI**
   - Download the [AWS CLI MSI installer](https://awscli.amazonaws.com/AWSCLIV2.msi)
   - Run the installer
   - Verify installation: `aws --version`

2. **Install Terraform**
   - Download the [Terraform ZIP file](https://www.terraform.io/downloads.html) for the version specified in `.env`
   - Extract to a directory (e.g., `C:\terraform`)
   - Add to PATH: `setx PATH "%PATH%;C:\terraform"`
   - Verify installation: `terraform -version`

3. **Install Atmos CLI**
   - Download the [Atmos release](https://github.com/cloudposse/atmos/releases) for the version specified in `.env`
   - Extract to a directory (e.g., `C:\atmos`)
   - Add to PATH: `setx PATH "%PATH%;C:\atmos"`
   - Verify installation: `atmos --version`

## AWS Configuration

1. **Configure AWS CLI**
   ```bash
   aws configure
   # Enter your AWS Access Key ID, Secret Access Key, default region, and output format
   ```

2. **For multi-account setup, create named profiles**
   ```bash
   # Management account
   aws configure --profile management
   
   # Dev account
   aws configure --profile dev
   
   # Other accounts as needed
   aws configure --profile staging
   aws configure --profile prod
   ```

## Repository Setup

1. **Clone the repository**
   ```bash
   git clone https://github.com/your-org/tf-atmos.git
   cd tf-atmos
   ```

2. **Review and configure the .env file**
   ```bash
   # The .env file contains version configurations for all tools
   cat .env
   
   # Edit if needed to match your requirements
   # TERRAFORM_VERSION="1.5.7"
   # ATMOS_VERSION="1.38.0"
   # KUBECTL_VERSION="1.28.3"
   # HELM_VERSION="3.13.1"
   ```

3. **Initialize Git hooks (optional)**
   ```bash
   # If using pre-commit
   pre-commit install
   ```

## Next Steps

After completing the installation:

1. Follow the [deployment guide](deployment.md) to set up your infrastructure
2. See the [environment onboarding guide](environment-onboarding.md) to add new environments
3. Review the [workflow reference](workflows.md) to understand available operations

## Troubleshooting

### Common Installation Issues

- **AWS CLI Authentication Issues**
  
  Verify your credentials are correct:
  ```bash
  aws sts get-caller-identity
  ```

- **Terraform Provider Installation Failures**
  
  Clear the provider cache:
  ```bash
  rm -rf ~/.terraform.d/plugins
  rm -rf .terraform
  terraform init
  ```

- **Atmos Command Not Found**
  
  Ensure it's in your PATH:
  ```bash
  echo $PATH
  # Add to PATH if needed
  export PATH=$PATH:/path/to/atmos/bin
  ```

For additional assistance, see our [troubleshooting guide](troubleshooting-guide.md).