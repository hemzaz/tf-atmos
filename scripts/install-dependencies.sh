#!/usr/bin/env bash
set -e

# Script to install all dependencies for the Atmos IaC platform
# This script handles installation for Linux (Ubuntu/Debian/RHEL/CentOS/Amazon Linux)
# and macOS systems.

# Text formatting
BOLD="\033[1m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
RESET="\033[0m"

# Load environment variables from .env file if it exists
if [[ -f "$(dirname "$0")/../.env" ]]; then
  echo -e "${BLUE}Loading tool versions from .env file...${RESET}"
  source "$(dirname "$0")/../.env"
else
  echo -e "${YELLOW}No .env file found. Using default versions.${RESET}"
fi

# Default configuration
INSTALL_TERRAFORM=true
INSTALL_ATMOS=true
INSTALL_AWS_CLI=true
INSTALL_JQ=true
INSTALL_YQ=true
INSTALL_OPENSSL=true
INSTALL_GIT=true
INSTALL_SESSION_MANAGER=true
INSTALL_HELM=true
INSTALL_KUBECTL=true
INSTALL_YAMLLINT=true
INSTALL_TFSEC=true
INSTALL_TFLINT=true
INSTALL_CHECKOV=false
INSTALL_REDIS=true
# Cookiecutter was removed in favor of Copier
INSTALL_COPIER=true
TERRAFORM_VERSION="${TERRAFORM_VERSION:-1.5.7}"
ATMOS_VERSION="${ATMOS_VERSION:-1.38.0}"
KUBECTL_VERSION="${KUBECTL_VERSION:-1.28.3}"
HELM_VERSION="${HELM_VERSION:-3.13.1}"
TFSEC_VERSION="${TFSEC_VERSION:-1.28.13}"
TFLINT_VERSION="${TFLINT_VERSION:-0.55.1}"
CHECKOV_VERSION="${CHECKOV_VERSION:-3.2.382}"
COPIER_VERSION="${COPIER_VERSION:-9.5.0}"
INSTALL_DIR="/usr/local/bin"
USER_INSTALL_DIR="$HOME/.local/bin"
SYSTEM_INSTALL=false
FORCE_REINSTALL=false
CI_MODE=false

# Help message
show_help() {
  echo -e "${BOLD}Atmos IaC Platform Dependencies Installer${RESET}"
  echo -e "This script installs all dependencies required for working with the Atmos IaC platform."
  echo
  echo -e "${BOLD}Usage:${RESET}"
  echo "  $0 [options]"
  echo
  echo -e "${BOLD}Version Management:${RESET}"
  echo "  Tool versions are managed in the .env file at the root of the repository."
  echo "  You can override versions using the command line options below."
  echo
  echo -e "${BOLD}Options:${RESET}"
  echo "  --skip-terraform        Skip Terraform installation"
  echo "  --skip-atmos            Skip Atmos installation"
  echo "  --skip-aws-cli          Skip AWS CLI installation"
  echo "  --skip-jq               Skip jq installation"
  echo "  --skip-yq               Skip yq installation"
  echo "  --skip-openssl          Skip OpenSSL installation"
  echo "  --skip-git              Skip Git installation"
  echo "  --skip-ssm-plugin       Skip AWS Session Manager plugin installation"
  echo "  --skip-helm             Skip Helm installation"
  echo "  --skip-kubectl          Skip kubectl installation"
  echo "  --skip-yamllint         Skip yamllint installation"
  echo "  --skip-tfsec            Skip tfsec installation"
  echo "  --skip-tflint           Skip tflint installation"
  echo "  --skip-redis            Skip Redis installation"
  echo "  --install-checkov       Install checkov (not installed by default)"
  # Cookiecutter option removed
  echo "  --skip-copier           Skip copier installation"
  echo "  --terraform-version VER Set Terraform version (default: $TERRAFORM_VERSION)"
  echo "  --atmos-version VER     Set Atmos version (default: $ATMOS_VERSION)"
  echo "  --kubectl-version VER   Set kubectl version (default: $KUBECTL_VERSION)"
  echo "  --helm-version VER      Set Helm version (default: $HELM_VERSION)"
  echo "  --tfsec-version VER     Set TFSec version (default: $TFSEC_VERSION)"
  echo "  --tflint-version VER    Set TFLint version (default: $TFLINT_VERSION)"
  echo "  --checkov-version VER   Set Checkov version (default: $CHECKOV_VERSION)"
  echo "  --copier-version VER    Set Copier version (default: $COPIER_VERSION)"
  echo "  --system                Install tools system-wide (requires sudo)"
  echo "  --user                  Install tools in user's home directory"
  echo "  --ci                    Install in CI mode (non-interactive, minimal deps)"
  echo "  --force                 Force reinstallation of all components"
  echo "  -h, --help              Show this help message"
  echo
  echo -e "${BOLD}Examples:${RESET}"
  echo "  $0 --skip-aws-cli --terraform-version 1.6.0"
  echo "  $0 --system --ci"
  echo "  $0 --install-checkov --tfsec-version 1.28.13 --checkov-version 3.2.382"
  echo
}

# Detect the operating system
detect_os() {
  echo -e "${BLUE}Detecting operating system...${RESET}"
  
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
    
    # Determine Linux distribution
    if [[ -f /etc/os-release ]]; then
      . /etc/os-release
      DISTRO=$ID
      
      if [[ "$DISTRO" == "ubuntu" || "$DISTRO" == "debian" ]]; then
        PKG_MANAGER="apt-get"
        PKG_UPDATE="apt-get update"
        PKG_INSTALL="apt-get install -y"
      elif [[ "$DISTRO" == "fedora" ]]; then
        PKG_MANAGER="dnf"
        PKG_UPDATE="dnf check-update"
        PKG_INSTALL="dnf install -y"
      elif [[ "$DISTRO" == "centos" || "$DISTRO" == "rhel" || "$DISTRO" == "amzn" ]]; then
        if command -v dnf &>/dev/null; then
          PKG_MANAGER="dnf"
          PKG_UPDATE="dnf check-update"
          PKG_INSTALL="dnf install -y"
        else
          PKG_MANAGER="yum"
          PKG_UPDATE="yum check-update"
          PKG_INSTALL="yum install -y"
        fi
      else
        echo -e "${YELLOW}Unknown Linux distribution: $DISTRO${RESET}"
        echo -e "${YELLOW}Will try to detect package manager...${RESET}"
        
        if command -v apt-get &>/dev/null; then
          PKG_MANAGER="apt-get"
          PKG_UPDATE="apt-get update"
          PKG_INSTALL="apt-get install -y"
        elif command -v dnf &>/dev/null; then
          PKG_MANAGER="dnf"
          PKG_UPDATE="dnf check-update"
          PKG_INSTALL="dnf install -y"
        elif command -v yum &>/dev/null; then
          PKG_MANAGER="yum"
          PKG_UPDATE="yum check-update"
          PKG_INSTALL="yum install -y"
        else
          echo -e "${RED}Could not determine package manager. Please install dependencies manually.${RESET}"
          exit 1
        fi
      fi
    else
      echo -e "${RED}Could not determine Linux distribution. Please install dependencies manually.${RESET}"
      exit 1
    fi
    
    echo -e "${GREEN}Linux detected: $DISTRO${RESET}"
    echo -e "${GREEN}Package manager: $PKG_MANAGER${RESET}"
    
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="darwin"
    
    # Check if Homebrew is installed
    if ! command -v brew &>/dev/null; then
      echo -e "${YELLOW}Homebrew not installed. Installing Homebrew...${RESET}"
      
      # First download the script to verify it
      BREW_INSTALL_SCRIPT="/tmp/homebrew_install.sh"
      BREW_SCRIPT_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
      BREW_EXPECTED_SHA256="72bc41560c34e4518dbb822a280400cbba02c0c3d3340ad831ca8eda77c9bfb7"  # Replace with current hash
      
      echo -e "${BLUE}Downloading Homebrew install script...${RESET}"
      curl -fsSL --proto '=https' --tlsv1.2 "$BREW_SCRIPT_URL" -o "$BREW_INSTALL_SCRIPT"
      
      # Verify the checksum
      if command -v shasum &>/dev/null; then
        ACTUAL_SHA256=$(shasum -a 256 "$BREW_INSTALL_SCRIPT" | cut -d' ' -f1)
      elif command -v sha256sum &>/dev/null; then
        ACTUAL_SHA256=$(sha256sum "$BREW_INSTALL_SCRIPT" | cut -d' ' -f1)
      else
        echo -e "${RED}Unable to verify Homebrew installer integrity - missing shasum/sha256sum utility${RESET}"
        echo -e "${YELLOW}Skipping Homebrew installation for security${RESET}"
        return 1
      fi
      
      if [[ "$ACTUAL_SHA256" != "$BREW_EXPECTED_SHA256" ]]; then
        echo -e "${RED}Homebrew installer checksum verification failed!${RESET}"
        echo -e "${RED}Expected: $BREW_EXPECTED_SHA256${RESET}"
        echo -e "${RED}Actual: $ACTUAL_SHA256${RESET}"
        echo -e "${RED}Aborting installation for security${RESET}"
        rm -f "$BREW_INSTALL_SCRIPT"
        return 1
      fi
      
      echo -e "${GREEN}Homebrew installer verified successfully.${RESET}"
      chmod +x "$BREW_INSTALL_SCRIPT"
      /bin/bash "$BREW_INSTALL_SCRIPT"
      rm -f "$BREW_INSTALL_SCRIPT"
      
      # Add Homebrew to PATH if needed
      if [[ -f /opt/homebrew/bin/brew ]]; then
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
        eval "$(/opt/homebrew/bin/brew shellenv)"
      elif [[ -f /usr/local/bin/brew ]]; then
        echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zprofile
        eval "$(/usr/local/bin/brew shellenv)"
      fi
    else
      echo -e "${GREEN}Homebrew is already installed.${RESET}"
    fi
    
    PKG_MANAGER="brew"
    PKG_UPDATE="brew update"
    PKG_INSTALL="brew install"
    
    echo -e "${GREEN}macOS detected${RESET}"
    
  else
    echo -e "${RED}Unsupported operating system: $OSTYPE${RESET}"
    exit 1
  fi
  
  # Determine architecture
  ARCH=$(uname -m)
  if [[ "$ARCH" == "x86_64" ]]; then
    if [[ "$OS" == "linux" ]]; then
      TERRAFORM_ARCH="amd64"
      ATMOS_ARCH="amd64"
      KUBECTL_ARCH="amd64"
      HELM_ARCH="amd64"
    else
      TERRAFORM_ARCH="amd64"
      ATMOS_ARCH="amd64"
      KUBECTL_ARCH="amd64"
      HELM_ARCH="amd64"
    fi
  elif [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
    TERRAFORM_ARCH="arm64"
    ATMOS_ARCH="arm64"
    KUBECTL_ARCH="arm64"
    HELM_ARCH="arm64"
  else
    echo -e "${RED}Unsupported architecture: $ARCH${RESET}"
    exit 1
  fi
  
  echo -e "${GREEN}Architecture: $ARCH${RESET}"
}

# Check and create the installation directory
setup_install_dir() {
  if [[ "$SYSTEM_INSTALL" == "true" ]]; then
    INSTALL_TARGET_DIR="$INSTALL_DIR"
    
    echo -e "${BLUE}Setting up system-wide installation in $INSTALL_TARGET_DIR...${RESET}"
    
    # Check if we have sudo access
    if ! sudo -n true 2>/dev/null; then
      echo -e "${YELLOW}System-wide installation requires sudo access.${RESET}"
      
      if [[ "$CI_MODE" == "true" ]]; then
        echo -e "${RED}CI mode enabled but no sudo access. Switching to user installation.${RESET}"
        SYSTEM_INSTALL="false"
        INSTALL_TARGET_DIR="$USER_INSTALL_DIR"
      else
        echo -e "${YELLOW}Please enter your password when prompted.${RESET}"
        if ! sudo -v; then
          echo -e "${RED}Could not get sudo access. Switching to user installation.${RESET}"
          SYSTEM_INSTALL="false"
          INSTALL_TARGET_DIR="$USER_INSTALL_DIR"
        fi
      fi
    fi
    
    # Create installation directory if it doesn't exist
    if [[ "$SYSTEM_INSTALL" == "true" ]]; then
      if [[ ! -d "$INSTALL_TARGET_DIR" ]]; then
        sudo mkdir -p "$INSTALL_TARGET_DIR"
      fi
    fi
  else
    INSTALL_TARGET_DIR="$USER_INSTALL_DIR"
    
    echo -e "${BLUE}Setting up user installation in $INSTALL_TARGET_DIR...${RESET}"
    
    # Create user installation directory if it doesn't exist
    if [[ ! -d "$INSTALL_TARGET_DIR" ]]; then
      mkdir -p "$INSTALL_TARGET_DIR"
    fi
    
    # Add the user bin directory to PATH if not already there
    if [[ ":$PATH:" != *":$INSTALL_TARGET_DIR:"* ]]; then
      echo -e "${YELLOW}Adding $INSTALL_TARGET_DIR to PATH...${RESET}"
      
      # Determine shell configuration file
      local SHELL_CONFIG=""
      if [[ -f "$HOME/.zshrc" ]]; then
        SHELL_CONFIG="$HOME/.zshrc"
      elif [[ -f "$HOME/.bashrc" ]]; then
        SHELL_CONFIG="$HOME/.bashrc"
      elif [[ -f "$HOME/.bash_profile" ]]; then
        SHELL_CONFIG="$HOME/.bash_profile"
      else
        # Create a default shell configuration file
        SHELL_CONFIG="$HOME/.bashrc"
        touch "$SHELL_CONFIG"
      fi
      
      # Add directory to PATH
      echo "export PATH=\"$INSTALL_TARGET_DIR:\$PATH\"" >> "$SHELL_CONFIG"
      echo -e "${YELLOW}Added $INSTALL_TARGET_DIR to PATH in $SHELL_CONFIG${RESET}"
      echo -e "${YELLOW}Please restart your shell or run 'source $SHELL_CONFIG' after installation${RESET}"
      
      # Also add to current session
      export PATH="$INSTALL_TARGET_DIR:$PATH"
    fi
  fi
}

# Install or update system packages
install_system_packages() {
  local PACKAGES=()
  
  echo -e "${BLUE}Installing required system packages...${RESET}"
  
  # Determine required packages based on the OS
  if [[ "$OS" == "linux" ]]; then
    if [[ "$PKG_MANAGER" == "apt-get" ]]; then
      if [[ "$INSTALL_GIT" == "true" ]]; then PACKAGES+=(git); fi
      if [[ "$INSTALL_OPENSSL" == "true" ]]; then PACKAGES+=(openssl); fi
      if [[ "$INSTALL_JQ" == "true" ]]; then PACKAGES+=(jq); fi
      if [[ "$INSTALL_YAMLLINT" == "true" ]]; then PACKAGES+=(yamllint); fi
      PACKAGES+=(curl unzip python3 python3-pip)
    elif [[ "$PKG_MANAGER" == "dnf" || "$PKG_MANAGER" == "yum" ]]; then
      if [[ "$INSTALL_GIT" == "true" ]]; then PACKAGES+=(git); fi
      if [[ "$INSTALL_OPENSSL" == "true" ]]; then PACKAGES+=(openssl); fi
      if [[ "$INSTALL_JQ" == "true" ]]; then PACKAGES+=(jq); fi
      PACKAGES+=(curl unzip python3 python3-pip)
    fi
    
    # Update package lists
    echo -e "${BLUE}Updating package lists...${RESET}"
    if [[ "$SYSTEM_INSTALL" == "true" ]]; then
      sudo $PKG_UPDATE
    else
      $PKG_UPDATE
    fi
    
    # Install packages
    if [[ ${#PACKAGES[@]} -gt 0 ]]; then
      echo -e "${BLUE}Installing packages: ${PACKAGES[*]}${RESET}"
      if [[ "$SYSTEM_INSTALL" == "true" ]]; then
        sudo $PKG_INSTALL "${PACKAGES[@]}"
      else
        $PKG_INSTALL "${PACKAGES[@]}"
      fi
    fi
    
    # Install YQ
    if [[ "$INSTALL_YQ" == "true" ]]; then
      install_yq
    fi
    
    # Install yamllint via pip if not available via package manager
    if [[ "$INSTALL_YAMLLINT" == "true" && "$PKG_MANAGER" != "apt-get" ]]; then
      echo -e "${BLUE}Installing yamllint via pip...${RESET}"
      if [[ "$SYSTEM_INSTALL" == "true" ]]; then
        sudo pip3 install yamllint
      else
        pip3 install --user yamllint
      fi
    fi
    
  elif [[ "$OS" == "darwin" ]]; then
    # Update Homebrew
    echo -e "${BLUE}Updating Homebrew...${RESET}"
    brew update
    
    # Install packages with Homebrew
    local BREW_PACKAGES=()
    if [[ "$INSTALL_GIT" == "true" ]]; then BREW_PACKAGES+=(git); fi
    if [[ "$INSTALL_OPENSSL" == "true" ]]; then BREW_PACKAGES+=(openssl); fi
    if [[ "$INSTALL_JQ" == "true" ]]; then BREW_PACKAGES+=(jq); fi
    if [[ "$INSTALL_YQ" == "true" ]]; then BREW_PACKAGES+=(yq); fi
    if [[ "$INSTALL_YAMLLINT" == "true" ]]; then BREW_PACKAGES+=(yamllint); fi
    
    if [[ ${#BREW_PACKAGES[@]} -gt 0 ]]; then
      echo -e "${BLUE}Installing Homebrew packages: ${BREW_PACKAGES[*]}${RESET}"
      brew install "${BREW_PACKAGES[@]}"
    fi
  fi
}

# Install YQ
install_yq() {
  if [[ "$INSTALL_YQ" != "true" ]]; then
    return
  fi
  
  if command -v yq &>/dev/null && [[ "$FORCE_REINSTALL" != "true" ]]; then
    echo -e "${GREEN}YQ is already installed: $(yq --version)${RESET}"
    return
  fi
  
  echo -e "${BLUE}Installing YQ...${RESET}"
  
  # Download and install YQ
  local YQ_URL="https://github.com/mikefarah/yq/releases/latest/download/yq_${OS}_${ARCH}"
  local YQ_BIN="$INSTALL_TARGET_DIR/yq"
  
  if curl -sSL "$YQ_URL" -o "$YQ_BIN"; then
    if [[ "$SYSTEM_INSTALL" == "true" ]]; then
      sudo chmod +x "$YQ_BIN"
    else
      chmod +x "$YQ_BIN"
    fi
    echo -e "${GREEN}YQ installed: $(yq --version)${RESET}"
  else
    echo -e "${RED}Failed to install YQ${RESET}"
  fi
}

# Install Terraform
install_terraform() {
  if [[ "$INSTALL_TERRAFORM" != "true" ]]; then
    return
  fi
  
  if command -v terraform &>/dev/null && [[ "$FORCE_REINSTALL" != "true" ]]; then
    local TF_INSTALLED_VERSION=$(terraform version -json | jq -r '.terraform_version')
    if [[ "$TF_INSTALLED_VERSION" == "$TERRAFORM_VERSION" ]]; then
      echo -e "${GREEN}Terraform $TERRAFORM_VERSION is already installed${RESET}"
      return
    else
      echo -e "${YELLOW}Updating Terraform from $TF_INSTALLED_VERSION to $TERRAFORM_VERSION${RESET}"
    fi
  else
    echo -e "${BLUE}Installing Terraform $TERRAFORM_VERSION...${RESET}"
  fi
  
  # Download and install Terraform
  local TF_URL="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_${OS}_${TERRAFORM_ARCH}.zip"
  local TF_ZIP="/tmp/terraform.zip"
  
  if curl -sSL "$TF_URL" -o "$TF_ZIP"; then
    unzip -o "$TF_ZIP" -d /tmp
    
    if [[ "$SYSTEM_INSTALL" == "true" ]]; then
      sudo mv /tmp/terraform "$INSTALL_TARGET_DIR/terraform"
      sudo chmod +x "$INSTALL_TARGET_DIR/terraform"
    else
      mv /tmp/terraform "$INSTALL_TARGET_DIR/terraform"
      chmod +x "$INSTALL_TARGET_DIR/terraform"
    fi
    
    rm "$TF_ZIP"
    echo -e "${GREEN}Terraform $TERRAFORM_VERSION installed${RESET}"
  else
    echo -e "${RED}Failed to install Terraform${RESET}"
  fi
}

# Install Atmos
install_atmos() {
  if [[ "$INSTALL_ATMOS" != "true" ]]; then
    return
  fi
  
  if command -v atmos &>/dev/null && [[ "$FORCE_REINSTALL" != "true" ]]; then
    local ATMOS_INSTALLED_VERSION=$(atmos version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    if [[ "$ATMOS_INSTALLED_VERSION" == "$ATMOS_VERSION" ]]; then
      echo -e "${GREEN}Atmos $ATMOS_VERSION is already installed${RESET}"
      return
    else
      echo -e "${YELLOW}Updating Atmos from $ATMOS_INSTALLED_VERSION to $ATMOS_VERSION${RESET}"
    fi
  else
    echo -e "${BLUE}Installing Atmos $ATMOS_VERSION...${RESET}"
  fi
  
  # Download and install Atmos
  # Use array to properly handle command construction and prevent injection
  local ATMOS_URL="https://github.com/cloudposse/atmos/releases/download/v${ATMOS_VERSION}/atmos_${OS}_${ATMOS_ARCH}"
  local ATMOS_BIN="$INSTALL_TARGET_DIR/atmos"
  
  # Validate URL format before using it 
  if [[ ! "$ATMOS_URL" =~ ^https://github\.com/cloudposse/atmos/releases/download/v[0-9]+\.[0-9]+\.[0-9]+/atmos_(linux|darwin)_(amd64|arm64)$ ]]; then
    echo -e "${RED}Invalid Atmos URL format. Aborting for security.${RESET}"
    return 1
  fi
  
  # Use command arrays instead of string interpolation
  if curl -sSL --proto '=https' --tlsv1.2 "$ATMOS_URL" -o "$ATMOS_BIN"; then
    if [[ "$SYSTEM_INSTALL" == "true" ]]; then
      sudo chmod 755 "$ATMOS_BIN"
    else
      chmod 755 "$ATMOS_BIN"
    fi
    echo -e "${GREEN}Atmos $ATMOS_VERSION installed${RESET}"
  else
    echo -e "${RED}Failed to install Atmos${RESET}"
  fi
}

# Install AWS CLI
install_aws_cli() {
  if [[ "$INSTALL_AWS_CLI" != "true" ]]; then
    return
  fi
  
  if command -v aws &>/dev/null && [[ "$FORCE_REINSTALL" != "true" ]]; then
    echo -e "${GREEN}AWS CLI is already installed: $(aws --version)${RESET}"
    return
  fi
  
  echo -e "${BLUE}Installing AWS CLI...${RESET}"
  
  if [[ "$OS" == "darwin" ]]; then
    # macOS installation
    local AWS_CLI_PKG="/tmp/AWSCLIV2.pkg"
    
    if curl -sSL "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "$AWS_CLI_PKG"; then
      sudo installer -pkg "$AWS_CLI_PKG" -target /
      rm "$AWS_CLI_PKG"
      echo -e "${GREEN}AWS CLI installed: $(aws --version)${RESET}"
    else
      echo -e "${RED}Failed to install AWS CLI${RESET}"
    fi
  elif [[ "$OS" == "linux" ]]; then
    # Linux installation
    local AWS_CLI_ZIP="/tmp/awscliv2.zip"
    
    if curl -sSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o "$AWS_CLI_ZIP"; then
      unzip -o "$AWS_CLI_ZIP" -d /tmp
      
      if [[ "$SYSTEM_INSTALL" == "true" ]]; then
        sudo /tmp/aws/install --update
      else
        /tmp/aws/install --update --bin-dir "$INSTALL_TARGET_DIR" --install-dir "$HOME/.aws-cli"
      fi
      
      rm -rf /tmp/aws /tmp/awscliv2.zip
      echo -e "${GREEN}AWS CLI installed: $(aws --version)${RESET}"
    else
      echo -e "${RED}Failed to install AWS CLI${RESET}"
    fi
  fi
}

# Install Session Manager Plugin
install_session_manager_plugin() {
  if [[ "$INSTALL_SESSION_MANAGER" != "true" ]]; then
    return
  fi
  
  if command -v session-manager-plugin &>/dev/null && [[ "$FORCE_REINSTALL" != "true" ]]; then
    echo -e "${GREEN}Session Manager Plugin is already installed: $(session-manager-plugin --version)${RESET}"
    return
  fi
  
  echo -e "${BLUE}Installing AWS Session Manager Plugin...${RESET}"
  
  if [[ "$OS" == "darwin" ]]; then
    # macOS installation
    local SSM_PKG="/tmp/sessionmanager-bundle.pkg"
    
    if [[ "$ARCH" == "arm64" ]]; then
      if curl -sSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac_arm64/sessionmanager-bundle.pkg" -o "$SSM_PKG"; then
        sudo installer -pkg "$SSM_PKG" -target /
        rm "$SSM_PKG"
        echo -e "${GREEN}Session Manager Plugin installed${RESET}"
      else
        echo -e "${RED}Failed to install Session Manager Plugin${RESET}"
      fi
    else
      if curl -sSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac/sessionmanager-bundle.pkg" -o "$SSM_PKG"; then
        sudo installer -pkg "$SSM_PKG" -target /
        rm "$SSM_PKG"
        echo -e "${GREEN}Session Manager Plugin installed${RESET}"
      else
        echo -e "${RED}Failed to install Session Manager Plugin${RESET}"
      fi
    fi
  elif [[ "$OS" == "linux" ]]; then
    # Linux installation
    local SSM_ZIP="/tmp/session-manager-plugin.zip"
    
    if [[ "$ARCH" == "x86_64" ]]; then
      if curl -sSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.zip" -o "$SSM_ZIP"; then
        unzip -o "$SSM_ZIP" -d /tmp
        
        if [[ "$SYSTEM_INSTALL" == "true" ]]; then
          sudo /tmp/sessionmanager-bundle/install -i /usr/local/sessionmanagerplugin -b /usr/local/bin/session-manager-plugin
        else
          mkdir -p "$HOME/.sessionmanagerplugin"
          /tmp/sessionmanager-bundle/install -i "$HOME/.sessionmanagerplugin" -b "$INSTALL_TARGET_DIR/session-manager-plugin"
        fi
        
        rm -rf /tmp/sessionmanager-bundle /tmp/session-manager-plugin.zip
        echo -e "${GREEN}Session Manager Plugin installed${RESET}"
      else
        echo -e "${RED}Failed to install Session Manager Plugin${RESET}"
      fi
    elif [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
      if curl -sSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_arm64/session-manager-plugin.zip" -o "$SSM_ZIP"; then
        unzip -o "$SSM_ZIP" -d /tmp
        
        if [[ "$SYSTEM_INSTALL" == "true" ]]; then
          sudo /tmp/sessionmanager-bundle/install -i /usr/local/sessionmanagerplugin -b /usr/local/bin/session-manager-plugin
        else
          mkdir -p "$HOME/.sessionmanagerplugin"
          /tmp/sessionmanager-bundle/install -i "$HOME/.sessionmanagerplugin" -b "$INSTALL_TARGET_DIR/session-manager-plugin"
        fi
        
        rm -rf /tmp/sessionmanager-bundle /tmp/session-manager-plugin.zip
        echo -e "${GREEN}Session Manager Plugin installed${RESET}"
      else
        echo -e "${RED}Failed to install Session Manager Plugin${RESET}"
      fi
    else
      echo -e "${RED}Unsupported architecture for Session Manager Plugin: $ARCH${RESET}"
    fi
  fi
}

# Install kubectl
install_kubectl() {
  if [[ "$INSTALL_KUBECTL" != "true" ]]; then
    return
  fi
  
  if command -v kubectl &>/dev/null && [[ "$FORCE_REINSTALL" != "true" ]]; then
    local KUBECTL_INSTALLED_VERSION=$(kubectl version --client -o json | jq -r '.clientVersion.gitVersion' | sed 's/^v//')
    if [[ "$KUBECTL_INSTALLED_VERSION" == "$KUBECTL_VERSION" ]]; then
      echo -e "${GREEN}kubectl $KUBECTL_VERSION is already installed${RESET}"
      return
    else
      echo -e "${YELLOW}Updating kubectl from $KUBECTL_INSTALLED_VERSION to $KUBECTL_VERSION${RESET}"
    fi
  else
    echo -e "${BLUE}Installing kubectl $KUBECTL_VERSION...${RESET}"
  fi
  
  # Download and install kubectl
  local KUBECTL_URL="https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/${OS}/${KUBECTL_ARCH}/kubectl"
  local KUBECTL_BIN="$INSTALL_TARGET_DIR/kubectl"
  
  if curl -sSL "$KUBECTL_URL" -o "$KUBECTL_BIN"; then
    if [[ "$SYSTEM_INSTALL" == "true" ]]; then
      sudo chmod +x "$KUBECTL_BIN"
    else
      chmod +x "$KUBECTL_BIN"
    fi
    echo -e "${GREEN}kubectl $KUBECTL_VERSION installed${RESET}"
  else
    echo -e "${RED}Failed to install kubectl${RESET}"
  fi
}

# Install Helm
install_helm() {
  if [[ "$INSTALL_HELM" != "true" ]]; then
    return
  fi
  
  if command -v helm &>/dev/null && [[ "$FORCE_REINSTALL" != "true" ]]; then
    local HELM_INSTALLED_VERSION=$(helm version --short | sed 's/^v//')
    if [[ "$HELM_INSTALLED_VERSION" == "$HELM_VERSION" ]]; then
      echo -e "${GREEN}Helm $HELM_VERSION is already installed${RESET}"
      return
    else
      echo -e "${YELLOW}Updating Helm from $HELM_INSTALLED_VERSION to $HELM_VERSION${RESET}"
    fi
  else
    echo -e "${BLUE}Installing Helm $HELM_VERSION...${RESET}"
  fi
  
  # Download and install Helm
  local HELM_BASENAME="helm-v${HELM_VERSION}-${OS}-${HELM_ARCH}"
  local HELM_URL="https://get.helm.sh/${HELM_BASENAME}.tar.gz"
  local HELM_TAR="/tmp/${HELM_BASENAME}.tar.gz"
  
  if curl -sSL "$HELM_URL" -o "$HELM_TAR"; then
    tar -zxf "$HELM_TAR" -C /tmp
    
    if [[ "$SYSTEM_INSTALL" == "true" ]]; then
      sudo mv "/tmp/${OS}-${HELM_ARCH}/helm" "$INSTALL_TARGET_DIR/helm"
      sudo chmod +x "$INSTALL_TARGET_DIR/helm"
    else
      mv "/tmp/${OS}-${HELM_ARCH}/helm" "$INSTALL_TARGET_DIR/helm"
      chmod +x "$INSTALL_TARGET_DIR/helm"
    fi
    
    rm -rf "/tmp/${OS}-${HELM_ARCH}" "$HELM_TAR"
    echo -e "${GREEN}Helm $HELM_VERSION installed${RESET}"
  else
    echo -e "${RED}Failed to install Helm${RESET}"
  fi
}

# Install tfsec
install_tfsec() {
  if [[ "$INSTALL_TFSEC" != "true" ]]; then
    return
  fi
  
  if command -v tfsec &>/dev/null && [[ "$FORCE_REINSTALL" != "true" ]]; then
    local TFSEC_INSTALLED_VERSION=$(tfsec --version 2>&1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | sed 's/^v//')
    if [[ "$TFSEC_INSTALLED_VERSION" == "$TFSEC_VERSION" ]]; then
      echo -e "${GREEN}tfsec $TFSEC_VERSION is already installed${RESET}"
      return
    else
      echo -e "${YELLOW}Updating tfsec from $TFSEC_INSTALLED_VERSION to $TFSEC_VERSION${RESET}"
    fi
  else
    echo -e "${BLUE}Installing tfsec $TFSEC_VERSION...${RESET}"
  fi
  
  # Install tfsec
  if [[ "$OS" == "darwin" ]]; then
    if command -v brew &>/dev/null; then
      brew install tfsec
    else
      # Download specific version if Homebrew is not available
      install_tfsec_binary
    fi
  else
    # Download and install tfsec
    install_tfsec_binary
  fi
}

# Helper function to install tfsec binary
install_tfsec_binary() {
  local TFSEC_URL="https://github.com/aquasecurity/tfsec/releases/download/v${TFSEC_VERSION}/tfsec-${OS}-${ARCH}"
  local TFSEC_BIN="$INSTALL_TARGET_DIR/tfsec"
  
  if curl -sSL "$TFSEC_URL" -o "$TFSEC_BIN"; then
    if [[ "$SYSTEM_INSTALL" == "true" ]]; then
      sudo chmod +x "$TFSEC_BIN"
    else
      chmod +x "$TFSEC_BIN"
    fi
    echo -e "${GREEN}tfsec $TFSEC_VERSION installed: $(tfsec --version)${RESET}"
  else
    echo -e "${RED}Failed to install tfsec $TFSEC_VERSION${RESET}"
  fi
}

# Install tflint
install_tflint() {
  if [[ "$INSTALL_TFLINT" != "true" ]]; then
    return
  fi
  
  if command -v tflint &>/dev/null && [[ "$FORCE_REINSTALL" != "true" ]]; then
    local TFLINT_INSTALLED_VERSION=$(tflint --version 2>&1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | sed 's/^v//')
    if [[ "$TFLINT_INSTALLED_VERSION" == "$TFLINT_VERSION" ]]; then
      echo -e "${GREEN}tflint $TFLINT_VERSION is already installed${RESET}"
      return
    else
      echo -e "${YELLOW}Updating tflint from $TFLINT_INSTALLED_VERSION to $TFLINT_VERSION${RESET}"
    fi
  else
    echo -e "${BLUE}Installing tflint $TFLINT_VERSION...${RESET}"
  fi
  
  # Install tflint
  if [[ "$OS" == "darwin" ]]; then
    if command -v brew &>/dev/null; then
      brew install tflint
    else
      # Download specific version if Homebrew is not available
      install_tflint_binary
    fi
  else
    # Download and install tflint
    install_tflint_binary
  fi
}

# Helper function to install tflint binary
install_tflint_binary() {
  local TFLINT_URL="https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_${OS}_${ARCH}.zip"
  local TFLINT_ZIP="/tmp/tflint.zip"
  
  if curl -sSL "$TFLINT_URL" -o "$TFLINT_ZIP"; then
    unzip -o "$TFLINT_ZIP" -d /tmp
    
    if [[ "$SYSTEM_INSTALL" == "true" ]]; then
      sudo mv /tmp/tflint "$INSTALL_TARGET_DIR/tflint"
      sudo chmod +x "$INSTALL_TARGET_DIR/tflint"
    else
      mv /tmp/tflint "$INSTALL_TARGET_DIR/tflint"
      chmod +x "$INSTALL_TARGET_DIR/tflint"
    fi
    
    rm "$TFLINT_ZIP"
    echo -e "${GREEN}tflint $TFLINT_VERSION installed: $(tflint --version)${RESET}"
  else
    echo -e "${RED}Failed to install tflint $TFLINT_VERSION${RESET}"
  fi
}

# Install checkov
install_checkov() {
  if [[ "$INSTALL_CHECKOV" != "true" ]]; then
    return
  fi
  
  if command -v checkov &>/dev/null && [[ "$FORCE_REINSTALL" != "true" ]]; then
    local CHECKOV_INSTALLED_VERSION=$(checkov --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    if [[ "$CHECKOV_INSTALLED_VERSION" == "$CHECKOV_VERSION" ]]; then
      echo -e "${GREEN}checkov $CHECKOV_VERSION is already installed${RESET}"
      return
    else
      echo -e "${YELLOW}Updating checkov from $CHECKOV_INSTALLED_VERSION to $CHECKOV_VERSION${RESET}"
    fi
  else
    echo -e "${BLUE}Installing checkov $CHECKOV_VERSION...${RESET}"
  fi
  
  # Install checkov via pip
  if command -v pip3 &>/dev/null; then
    if [[ "$SYSTEM_INSTALL" == "true" ]]; then
      sudo pip3 install checkov==$CHECKOV_VERSION
    else
      pip3 install --user checkov==$CHECKOV_VERSION
    fi
    echo -e "${GREEN}checkov $CHECKOV_VERSION installed: $(checkov --version)${RESET}"
  else
    echo -e "${YELLOW}pip3 not found. Installing pip3...${RESET}"
    if [[ "$OS" == "darwin" ]]; then
      brew install python3
    elif [[ "$SYSTEM_INSTALL" == "true" ]]; then
      sudo $PKG_INSTALL python3-pip
    else
      $PKG_INSTALL python3-pip
    fi
    
    if command -v pip3 &>/dev/null; then
      if [[ "$SYSTEM_INSTALL" == "true" ]]; then
        sudo pip3 install checkov==$CHECKOV_VERSION
      else
        pip3 install --user checkov==$CHECKOV_VERSION
      fi
      echo -e "${GREEN}checkov $CHECKOV_VERSION installed: $(checkov --version)${RESET}"
    else
      echo -e "${RED}Failed to install pip3, which is required for checkov${RESET}"
    fi
  fi
}

# Cookiecutter installation function was removed in favor of using Copier exclusively

# Install copier
install_copier() {
  if [[ "$INSTALL_COPIER" != "true" ]]; then
    return
  fi
  
  if command -v copier &>/dev/null && [[ "$FORCE_REINSTALL" != "true" ]]; then
    local COPIER_INSTALLED_VERSION=$(pip3 show copier 2>/dev/null | grep -E '^Version:' | cut -d' ' -f2)
    if [[ "$COPIER_INSTALLED_VERSION" == "$COPIER_VERSION" ]]; then
      echo -e "${GREEN}copier $COPIER_VERSION is already installed${RESET}"
      return
    else
      echo -e "${YELLOW}Updating copier from $COPIER_INSTALLED_VERSION to $COPIER_VERSION${RESET}"
    fi
  else
    echo -e "${BLUE}Installing copier $COPIER_VERSION...${RESET}"
  fi
  
  # Install copier via pip
  if command -v pip3 &>/dev/null; then
    if [[ "$SYSTEM_INSTALL" == "true" ]]; then
      sudo pip3 install copier==$COPIER_VERSION
    else
      pip3 install --user copier==$COPIER_VERSION
    fi
    echo -e "${GREEN}copier $COPIER_VERSION installed: $(pip3 show copier | grep -E '^Version:')${RESET}"
  else
    echo -e "${YELLOW}pip3 not found. Installing pip3...${RESET}"
    if [[ "$OS" == "darwin" ]]; then
      brew install python3
    elif [[ "$SYSTEM_INSTALL" == "true" ]]; then
      sudo $PKG_INSTALL python3-pip
    else
      $PKG_INSTALL python3-pip
    fi
    
    if command -v pip3 &>/dev/null; then
      if [[ "$SYSTEM_INSTALL" == "true" ]]; then
        sudo pip3 install copier==$COPIER_VERSION
      else
        pip3 install --user copier==$COPIER_VERSION
      fi
      echo -e "${GREEN}copier $COPIER_VERSION installed: $(pip3 show copier | grep -E '^Version:')${RESET}"
    else
      echo -e "${RED}Failed to install pip3, which is required for copier${RESET}"
    fi
  fi
}

# Install Redis
install_redis() {
  if [[ "$INSTALL_REDIS" != "true" ]]; then
    return
  fi
  
  if command -v redis-server &>/dev/null && [[ "$FORCE_REINSTALL" != "true" ]]; then
    echo -e "${GREEN}Redis is already installed: $(redis-server --version)${RESET}"
    return
  fi
  
  echo -e "${BLUE}Installing Redis...${RESET}"
  
  if [[ "$OS" == "darwin" ]]; then
    if command -v brew &>/dev/null; then
      brew install redis
      
      echo -e "${GREEN}Redis installed: $(redis-server --version)${RESET}"
      echo -e "${YELLOW}To start Redis server:${RESET}"
      echo -e "${YELLOW}  - Use our helper script: scripts/start_redis.sh${RESET}"
      echo -e "${YELLOW}  - Or manually: brew services start redis${RESET}"
    else
      echo -e "${RED}Homebrew not found. Unable to install Redis.${RESET}"
    fi
  elif [[ "$OS" == "linux" ]]; then
    if [[ "$PKG_MANAGER" == "apt-get" ]]; then
      if [[ "$SYSTEM_INSTALL" == "true" ]]; then
        sudo apt-get install -y redis-server
      else
        apt-get install -y redis-server
      fi
    elif [[ "$PKG_MANAGER" == "dnf" ]]; then
      if [[ "$SYSTEM_INSTALL" == "true" ]]; then
        sudo dnf install -y redis
      else
        dnf install -y redis
      fi
    elif [[ "$PKG_MANAGER" == "yum" ]]; then
      if [[ "$SYSTEM_INSTALL" == "true" ]]; then
        sudo yum install -y redis
      else
        yum install -y redis
      fi
    fi
    
    if command -v redis-server &>/dev/null; then
      echo -e "${GREEN}Redis installed: $(redis-server --version)${RESET}"
      echo -e "${YELLOW}To start Redis server:${RESET}"
      echo -e "${YELLOW}  - Use our helper script: scripts/start_redis.sh${RESET}"
      echo -e "${YELLOW}  - Or manually: sudo systemctl start redis${RESET}"
    else
      echo -e "${RED}Failed to install Redis${RESET}"
    fi
  fi
  
  # Add Redis configuration to .env file if it exists
  local ENV_FILE="$(dirname "$0")/../.env"
  if [[ -f "$ENV_FILE" ]] && ! grep -q "REDIS_URL=" "$ENV_FILE"; then
    echo -e "\n# Redis configuration for async operations" >> "$ENV_FILE"
    echo "REDIS_URL=redis://localhost:6379/0" >> "$ENV_FILE"
    echo "CELERY_WORKERS=4" >> "$ENV_FILE" 
    echo "ASYNC_MODE=true" >> "$ENV_FILE"
    
    echo -e "${GREEN}Added Redis configuration to $ENV_FILE${RESET}"
  fi
}

# Parse command line options
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-terraform)
      INSTALL_TERRAFORM=false
      shift
      ;;
    --skip-atmos)
      INSTALL_ATMOS=false
      shift
      ;;
    --skip-aws-cli)
      INSTALL_AWS_CLI=false
      shift
      ;;
    --skip-jq)
      INSTALL_JQ=false
      shift
      ;;
    --skip-yq)
      INSTALL_YQ=false
      shift
      ;;
    --skip-openssl)
      INSTALL_OPENSSL=false
      shift
      ;;
    --skip-git)
      INSTALL_GIT=false
      shift
      ;;
    --skip-ssm-plugin)
      INSTALL_SESSION_MANAGER=false
      shift
      ;;
    --skip-helm)
      INSTALL_HELM=false
      shift
      ;;
    --skip-kubectl)
      INSTALL_KUBECTL=false
      shift
      ;;
    --skip-yamllint)
      INSTALL_YAMLLINT=false
      shift
      ;;
    --skip-tfsec)
      INSTALL_TFSEC=false
      shift
      ;;
    --skip-tflint)
      INSTALL_TFLINT=false
      shift
      ;;
    --skip-redis)
      INSTALL_REDIS=false
      shift
      ;;
    --install-checkov)
      INSTALL_CHECKOV=true
      shift
      ;;
    # --install-cookiecutter option removed
    --skip-copier)
      INSTALL_COPIER=false
      shift
      ;;
    --terraform-version)
      TERRAFORM_VERSION="$2"
      shift 2
      ;;
    --atmos-version)
      ATMOS_VERSION="$2"
      shift 2
      ;;
    --kubectl-version)
      KUBECTL_VERSION="$2"
      shift 2
      ;;
    --helm-version)
      HELM_VERSION="$2"
      shift 2
      ;;
    --tfsec-version)
      TFSEC_VERSION="$2"
      shift 2
      ;;
    --tflint-version)
      TFLINT_VERSION="$2"
      shift 2
      ;;
    --checkov-version)
      CHECKOV_VERSION="$2"
      shift 2
      ;;
    --copier-version)
      COPIER_VERSION="$2"
      shift 2
      ;;
    --system)
      SYSTEM_INSTALL=true
      shift
      ;;
    --user)
      SYSTEM_INSTALL=false
      shift
      ;;
    --ci)
      CI_MODE=true
      shift
      ;;
    --force)
      FORCE_REINSTALL=true
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${RESET}"
      show_help
      exit 1
      ;;
  esac
done

# Configure CI mode
if [[ "$CI_MODE" == "true" ]]; then
  echo -e "${BLUE}CI mode enabled - setting up minimal dependencies${RESET}"
  INSTALL_SESSION_MANAGER=false
  INSTALL_HELM=false
  INSTALL_KUBECTL=false
  FORCE_REINSTALL=true
fi

# Execute installation
echo -e "${BOLD}${BLUE}Atmos IaC Platform Dependencies Installer${RESET}"
echo

detect_os
setup_install_dir
install_system_packages
install_terraform
install_atmos
install_aws_cli
install_session_manager_plugin
install_kubectl
install_helm
install_tfsec
install_tflint
install_checkov
install_copier
install_redis

# Print summary
echo
echo -e "${BOLD}${GREEN}Installation complete!${RESET}"
echo
echo -e "${BOLD}Installed components:${RESET}"
echo -e "  • ${GREEN}$(terraform version | head -n 1)${RESET}" 2>/dev/null || echo -e "  • ${RED}Terraform not installed${RESET}"
echo -e "  • ${GREEN}$(atmos version)${RESET}" 2>/dev/null || echo -e "  • ${RED}Atmos not installed${RESET}"

if [[ "$INSTALL_AWS_CLI" == "true" ]]; then
  echo -e "  • ${GREEN}$(aws --version)${RESET}" 2>/dev/null || echo -e "  • ${RED}AWS CLI not installed${RESET}"
fi

if [[ "$INSTALL_JQ" == "true" ]]; then
  echo -e "  • ${GREEN}jq version $(jq --version)${RESET}" 2>/dev/null || echo -e "  • ${RED}jq not installed${RESET}"
fi

if [[ "$INSTALL_YQ" == "true" ]]; then
  echo -e "  • ${GREEN}$(yq --version)${RESET}" 2>/dev/null || echo -e "  • ${RED}yq not installed${RESET}"
fi

if [[ "$INSTALL_KUBECTL" == "true" ]]; then
  echo -e "  • ${GREEN}$(kubectl version --client 2>/dev/null | grep Client || kubectl version --client)${RESET}" 2>/dev/null || echo -e "  • ${RED}kubectl not installed${RESET}"
fi

if [[ "$INSTALL_HELM" == "true" ]]; then
  echo -e "  • ${GREEN}$(helm version --short)${RESET}" 2>/dev/null || echo -e "  • ${RED}Helm not installed${RESET}"
fi

if [[ "$INSTALL_SESSION_MANAGER" == "true" ]]; then
  echo -e "  • ${GREEN}Session Manager Plugin $(session-manager-plugin --version)${RESET}" 2>/dev/null || echo -e "  • ${RED}Session Manager Plugin not installed${RESET}"
fi

if [[ "$INSTALL_TFSEC" == "true" ]]; then
  echo -e "  • ${GREEN}$(tfsec --version)${RESET}" 2>/dev/null || echo -e "  • ${RED}tfsec not installed${RESET}"
fi

if [[ "$INSTALL_TFLINT" == "true" ]]; then
  echo -e "  • ${GREEN}$(tflint --version)${RESET}" 2>/dev/null || echo -e "  • ${RED}tflint not installed${RESET}"
fi

if [[ "$INSTALL_CHECKOV" == "true" ]]; then
  echo -e "  • ${GREEN}checkov $(checkov --version)${RESET}" 2>/dev/null || echo -e "  • ${RED}checkov not installed${RESET}"
fi


if [[ "$INSTALL_COPIER" == "true" ]]; then
  COPIER_VERSION_OUTPUT=$(pip3 show copier 2>/dev/null | grep -E '^Version:' | cut -d' ' -f2)
  echo -e "  • ${GREEN}copier $COPIER_VERSION_OUTPUT${RESET}" 2>/dev/null || echo -e "  • ${RED}copier not installed${RESET}"
fi

if [[ "$INSTALL_REDIS" == "true" ]]; then
  echo -e "  • ${GREEN}$(redis-server --version)${RESET}" 2>/dev/null || echo -e "  • ${RED}Redis not installed${RESET}"
  # Check if Redis is running
  if redis-cli ping &>/dev/null; then
    echo -e "    ${GREEN}Redis server is running${RESET}"
  else
    echo -e "    ${YELLOW}Redis server is not running. Use scripts/start_redis.sh to start it.${RESET}"
  fi
fi

echo
echo -e "${BOLD}Installation Directory:${RESET} $INSTALL_TARGET_DIR"

if [[ "$SYSTEM_INSTALL" != "true" && ":$PATH:" != *":$INSTALL_TARGET_DIR:"* ]]; then
  echo -e "${YELLOW}"
  echo -e "NOTE: To use the installed tools, you need to add $INSTALL_TARGET_DIR to your PATH."
  echo -e "To do this, run: source ~/.bashrc or source ~/.zshrc (depending on your shell)"
  echo -e "${RESET}"
fi

echo
echo -e "${BOLD}${GREEN}You're all set! Start using Atmos with:${RESET}"
echo -e "  $ atmos --help"
echo -e "  $ atmos terraform plan <component> -s <stack-name>"
echo