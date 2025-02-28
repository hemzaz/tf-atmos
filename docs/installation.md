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
| Terraform | ≥ 1.0.0 | Infrastructure provisioning |
| Atmos CLI | ≥ 1.5.0 | Workflow orchestration |
| Git | Any recent | Version control |

## Installation Instructions

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

1. **Install AWS CLI**
   - Download the [AWS CLI MSI installer](https://awscli.amazonaws.com/AWSCLIV2.msi)
   - Run the installer
   - Verify installation: `aws --version`

2. **Install Terraform**
   - Download the [Terraform ZIP file](https://www.terraform.io/downloads.html)
   - Extract to a directory (e.g., `C:\terraform`)
   - Add to PATH: `setx PATH "%PATH%;C:\terraform"`
   - Verify installation: `terraform -version`

3. **Install Atmos CLI**
   - Download the [Atmos release](https://github.com/cloudposse/atmos/releases)
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

2. **Initialize Git hooks (optional)**
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