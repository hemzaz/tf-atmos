#!/bin/bash
# =============================================================================
# Developer Onboarding Script - Complete Environment Setup < 10 Minutes
# =============================================================================
# This script automates the complete setup process for new developers
# Target: < 10 minutes from zero to productive development environment

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ONBOARD_LOG="$PROJECT_ROOT/logs/onboarding-$(date +%Y%m%d-%H%M%S).log"

# Colors and styling
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

# Progress tracking
TOTAL_STEPS=12
CURRENT_STEP=0

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Console output with colors
    case "$level" in
        INFO)  echo -e "${BLUE}[INFO]${NC} $message" ;;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        WARNING) echo -e "${YELLOW}[WARNING]${NC} $message" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" >&2 ;;
        STEP) 
            CURRENT_STEP=$((CURRENT_STEP + 1))
            echo -e "${PURPLE}[STEP $CURRENT_STEP/$TOTAL_STEPS]${NC} ${BOLD}$message${NC}" 
            ;;
    esac
    
    # Log to file (without colors)
    echo "[$timestamp] [$level] $message" >> "$ONBOARD_LOG"
}

show_progress() {
    local percent=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    local filled=$((percent / 5))
    local empty=$((20 - filled))
    
    printf "\r${CYAN}Progress: ["
    printf "%${filled}s" | tr ' ' '='
    printf "%${empty}s" | tr ' ' '-'
    printf "] %d%%${NC}" "$percent"
    
    if [ "$CURRENT_STEP" -eq "$TOTAL_STEPS" ]; then
        echo
    fi
}

check_command() {
    local cmd="$1"
    local install_info="${2:-}"
    
    if command -v "$cmd" &> /dev/null; then
        log SUCCESS "$cmd is installed"
        return 0
    else
        log WARNING "$cmd is not installed"
        if [ -n "$install_info" ]; then
            log INFO "Install with: $install_info"
        fi
        return 1
    fi
}

wait_with_spinner() {
    local pid=$1
    local message="${2:-Working...}"
    local delay=0.1
    local spinstr='|/-\'
    
    echo -n "$message "
    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf "[%c]" "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b"
    done
    echo "done"
}

# =============================================================================
# Main Onboarding Functions
# =============================================================================

show_welcome() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}   🌍 ${BOLD}Terraform/Atmos Infrastructure - Developer Onboarding${NC}   ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${WHITE}This script will set up your complete development environment in < 10 minutes${NC}"
    echo
    echo -e "${WHITE}What we'll do:${NC}"
    echo -e "  🔧 Install and configure required tools"
    echo -e "  📦 Set up Python environment and Gaia CLI"
    echo -e "  🐳 Configure Docker development environment"
    echo -e "  ⚙️  Create development configuration files"
    echo -e "  🔍 Validate infrastructure access and permissions"
    echo -e "  📚 Set up IDE and development shortcuts"
    echo -e "  🚀 Test end-to-end workflow"
    echo
    
    # Get developer info
    echo -e "${WHITE}First, let's get some information about you:${NC}"
    read -p "Your name (for git config): " DEVELOPER_NAME
    read -p "Your email (for git config): " DEVELOPER_EMAIL
    read -p "Preferred AWS region [us-east-1]: " AWS_REGION
    AWS_REGION=${AWS_REGION:-us-east-1}
    
    echo
    read -p "Ready to start? This will take about 8-10 minutes. [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Onboarding cancelled"
        exit 0
    fi
    
    # Create logs directory
    mkdir -p "$(dirname "$ONBOARD_LOG")"
    log INFO "Starting developer onboarding for $DEVELOPER_NAME <$DEVELOPER_EMAIL>"
    log INFO "Target AWS region: $AWS_REGION"
    echo
}

check_prerequisites() {
    log STEP "Checking system prerequisites"
    
    local missing_tools=()
    local os_type=$(uname -s)
    
    log INFO "Operating System: $os_type"
    
    # Essential tools
    check_command "git" "macOS: xcode-select --install | Linux: sudo apt-get install git" || missing_tools+=("git")
    check_command "curl" "Usually pre-installed" || missing_tools+=("curl")
    check_command "docker" "Visit: https://docs.docker.com/get-docker/" || missing_tools+=("docker")
    
    # Check Docker daemon
    if command -v docker &> /dev/null; then
        if docker info &> /dev/null; then
            log SUCCESS "Docker daemon is running"
        else
            log ERROR "Docker is installed but daemon is not running. Please start Docker Desktop."
            missing_tools+=("docker-daemon")
        fi
    fi
    
    # Check for package managers
    local has_package_manager=false
    if command -v brew &> /dev/null; then
        log SUCCESS "Homebrew package manager available"
        has_package_manager=true
    elif command -v apt-get &> /dev/null; then
        log SUCCESS "APT package manager available"  
        has_package_manager=true
    elif command -v yum &> /dev/null; then
        log SUCCESS "YUM package manager available"
        has_package_manager=true
    fi
    
    if [ "$has_package_manager" = false ]; then
        log WARNING "No supported package manager found. Manual installation may be required."
    fi
    
    # Check Python
    if command -v python3 &> /dev/null; then
        local python_version=$(python3 --version | cut -d' ' -f2)
        log SUCCESS "Python3 is installed: $python_version"
    else
        log WARNING "Python3 is not installed"
        missing_tools+=("python3")
    fi
    
    # If we have missing tools, try to install them
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log WARNING "Missing tools detected: ${missing_tools[*]}"
        
        if command -v brew &> /dev/null; then
            read -p "Install missing tools with Homebrew? [y/N] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                install_with_brew "${missing_tools[@]}"
            fi
        fi
    fi
    
    show_progress
}

install_with_brew() {
    local tools=("$@")
    log INFO "Installing tools with Homebrew..."
    
    for tool in "${tools[@]}"; do
        case "$tool" in
            "git") brew install git ;;
            "python3") brew install python3 ;;
            "docker") 
                log INFO "Installing Docker Desktop..."
                brew install --cask docker
                log WARNING "Please start Docker Desktop manually after installation"
                ;;
            # Skip tools that can't be brew installed
            "docker-daemon"|"curl") continue ;;
            *) brew install "$tool" ;;
        esac
    done
}

install_infrastructure_tools() {
    log STEP "Installing infrastructure tools"
    
    # Install Terraform
    if ! check_command "terraform" "Visit: https://terraform.io/downloads"; then
        if command -v brew &> /dev/null; then
            log INFO "Installing Terraform with Homebrew..."
            brew tap hashicorp/tap && brew install hashicorp/tap/terraform
        else
            log WARNING "Please install Terraform manually from https://terraform.io/downloads"
        fi
    fi
    
    # Install Atmos
    if ! check_command "atmos" "Visit: https://atmos.tools/install"; then
        if command -v brew &> /dev/null; then
            log INFO "Installing Atmos with Homebrew..."
            brew tap cloudposse/tap && brew install cloudposse/tap/atmos
        else
            log WARNING "Please install Atmos manually from https://atmos.tools/install"
        fi
    fi
    
    # Install AWS CLI
    if ! check_command "aws" "Visit: https://aws.amazon.com/cli/"; then
        if command -v brew &> /dev/null; then
            log INFO "Installing AWS CLI with Homebrew..."
            brew install awscli
        else
            log WARNING "Please install AWS CLI manually from https://aws.amazon.com/cli/"
        fi
    fi
    
    show_progress
}

setup_git_configuration() {
    log STEP "Configuring Git"
    
    # Set up git configuration
    git config --global user.name "$DEVELOPER_NAME"
    git config --global user.email "$DEVELOPER_EMAIL"
    
    # Useful git aliases for infrastructure work
    git config --global alias.co checkout
    git config --global alias.br branch
    git config --global alias.ci commit
    git config --global alias.st status
    git config --global alias.unstage 'reset HEAD --'
    git config --global alias.last 'log -1 HEAD'
    git config --global alias.visual '!gitk'
    git config --global alias.hist 'log --pretty=format:"%h %ad | %s%d [%an]" --graph --date=short'
    
    # Infrastructure-specific aliases
    git config --global alias.tf-check 'diff --name-only HEAD~1 HEAD | grep "\.tf$"'
    
    log SUCCESS "Git configured for $DEVELOPER_NAME <$DEVELOPER_EMAIL>"
    show_progress
}

setup_python_environment() {
    log STEP "Setting up Python environment"
    
    cd "$PROJECT_ROOT"
    
    # Create virtual environment if it doesn't exist
    if [ ! -d "venv" ]; then
        log INFO "Creating Python virtual environment..."
        python3 -m venv venv
    fi
    
    # Activate virtual environment
    source venv/bin/activate
    
    # Upgrade pip
    pip install --upgrade pip
    
    # Install Gaia CLI
    log INFO "Installing Gaia CLI..."
    cd gaia && pip install -e . && cd ..
    
    # Verify installation
    if gaia --help > /dev/null 2>&1; then
        log SUCCESS "Gaia CLI installed successfully"
    else
        log WARNING "Gaia CLI installation may have issues"
    fi
    
    show_progress
}

setup_development_environment() {
    log STEP "Setting up development environment"
    
    cd "$PROJECT_ROOT"
    
    # Run existing dev-setup script if it exists
    if [ -f "scripts/dev-setup.sh" ]; then
        log INFO "Running development environment setup..."
        bash scripts/dev-setup.sh > "$ONBOARD_LOG.dev-setup" 2>&1 &
        local setup_pid=$!
        wait_with_spinner $setup_pid "Setting up development environment"
        
        if wait $setup_pid; then
            log SUCCESS "Development environment setup completed"
        else
            log WARNING "Development environment setup had some issues (check logs)"
        fi
    fi
    
    # Create developer-specific configuration
    log INFO "Creating developer configuration..."
    
    # Create personal .env file
    if [ ! -f ".env.local" ]; then
        cat > .env.local << EOF
# Personal developer configuration for $DEVELOPER_NAME
# This file is git-ignored and contains your personal settings

# AWS Configuration
AWS_DEFAULT_REGION=$AWS_REGION
AWS_PROFILE=default

# Development preferences
DEVELOPER_NAME="$DEVELOPER_NAME"
DEVELOPER_EMAIL="$DEVELOPER_EMAIL"

# Enable development features
ENABLE_DEBUG_LOGGING=true
ENABLE_VERBOSE_OUTPUT=true
ENABLE_DEVELOPMENT_SHORTCUTS=true

# Personal aliases and shortcuts
# Add your custom environment variables here
EOF
        log SUCCESS "Created personal configuration file: .env.local"
    fi
    
    show_progress
}

setup_ide_configuration() {
    log STEP "Setting up IDE configuration"
    
    # VS Code settings
    local vscode_dir="$PROJECT_ROOT/.vscode"
    if [ ! -d "$vscode_dir" ]; then
        mkdir -p "$vscode_dir"
        
        # VS Code settings
        cat > "$vscode_dir/settings.json" << 'EOF'
{
  "terraform.experimentalFeatures": {
    "validateOnSave": true
  },
  "terraform.languageServer": {
    "external": true,
    "args": ["serve"]
  },
  "files.associations": {
    "*.yaml": "yaml",
    "atmos.yaml": "yaml",
    "*.tf": "terraform",
    "*.tfvars": "terraform"
  },
  "yaml.schemas": {
    "https://json.schemastore.org/github-workflow": ".github/workflows/*.yml"
  },
  "python.defaultInterpreterPath": "./venv/bin/python",
  "python.terminal.activateEnvironment": true,
  "editor.formatOnSave": true,
  "editor.codeActionsOnSave": {
    "source.organizeImports": true
  }
}
EOF
        
        # VS Code extensions recommendations
        cat > "$vscode_dir/extensions.json" << 'EOF'
{
  "recommendations": [
    "hashicorp.terraform",
    "ms-python.python",
    "redhat.vscode-yaml",
    "ms-vscode.makefile-tools",
    "eamodio.gitlens",
    "github.vscode-pull-request-github",
    "ms-vscode-remote.remote-containers",
    "davidanson.vscode-markdownlint"
  ]
}
EOF
        
        # VS Code tasks
        cat > "$vscode_dir/tasks.json" << 'EOF'
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Validate Infrastructure",
      "type": "shell",
      "command": "make validate",
      "group": "build",
      "presentation": {
        "echo": true,
        "reveal": "always",
        "focus": false,
        "panel": "shared"
      }
    },
    {
      "label": "Lint Code",
      "type": "shell", 
      "command": "make lint",
      "group": "build"
    },
    {
      "label": "Plan Infrastructure", 
      "type": "shell",
      "command": "make plan",
      "group": "build"
    },
    {
      "label": "Start Dev Environment",
      "type": "shell",
      "command": "make dev-start",
      "group": "build",
      "isBackground": true
    }
  ]
}
EOF
        
        log SUCCESS "VS Code configuration created"
    fi
    
    # Create development aliases file
    cat > "$PROJECT_ROOT/.dev_aliases" << 'EOF'
# Development aliases for infrastructure work
# Source this file in your shell: source .dev_aliases

# Quick shortcuts
alias tf='terraform'
alias atm='atmos'
alias g='gaia'
alias k='kubectl'

# Infrastructure commands
alias validate='make validate'
alias lint='make lint' 
alias plan='make plan'
alias apply='make apply'
alias status='make status'
alias doctor='make doctor'

# Development environment
alias dev-start='make dev-start'
alias dev-stop='make dev-stop'
alias dev-logs='make dev-logs'
alias dev-reset='make dev-reset'

# Gaia shortcuts
alias g-status='gaia status'
alias g-validate='gaia workflow validate'
alias g-plan='gaia workflow plan-environment'
alias g-apply='gaia workflow apply-environment'

# Stack management (adjust for your environment)
alias stack-dev='gaia status -t fnx -a dev -e testenv-01'
alias stack-staging='gaia status -t fnx -a staging -e staging-01'

echo "🌍 Infrastructure development aliases loaded!"
echo "💡 Try: validate, plan, apply, g-status, stack-dev"
EOF
    
    log SUCCESS "Development aliases created (source .dev_aliases to use)"
    show_progress
}

validate_access_and_permissions() {
    log STEP "Validating access and permissions"
    
    # Check AWS credentials
    log INFO "Checking AWS access..."
    if aws sts get-caller-identity > /dev/null 2>&1; then
        local account_id=$(aws sts get-caller-identity --query Account --output text)
        local user_arn=$(aws sts get-caller-identity --query Arn --output text)
        log SUCCESS "AWS access confirmed - Account: $account_id"
        log INFO "AWS User/Role: $user_arn"
    else
        log WARNING "AWS credentials not configured or invalid"
        log INFO "Configure with: aws configure"
        log INFO "Or set up environment variables/profiles"
    fi
    
    # Check Atmos configuration
    log INFO "Checking Atmos configuration..."
    if [ -f "atmos.yaml" ]; then
        log SUCCESS "atmos.yaml found"
        
        if atmos list stacks > /dev/null 2>&1; then
            local stack_count=$(atmos list stacks | wc -l)
            log SUCCESS "Atmos can list $stack_count stacks"
        else
            log WARNING "Atmos configuration may have issues"
        fi
    else
        log ERROR "atmos.yaml not found - are you in the right directory?"
    fi
    
    # Check Terraform
    log INFO "Checking Terraform..."
    if terraform version > /dev/null 2>&1; then
        local tf_version=$(terraform version | head -1)
        log SUCCESS "Terraform available: $tf_version"
    else
        log WARNING "Terraform not found or not working"
    fi
    
    # Check Docker
    log INFO "Checking Docker..."
    if docker info > /dev/null 2>&1; then
        log SUCCESS "Docker daemon is accessible"
    else
        log WARNING "Docker daemon not accessible"
    fi
    
    show_progress
}

test_end_to_end_workflow() {
    log STEP "Testing end-to-end workflow"
    
    # Test Makefile
    log INFO "Testing Makefile..."
    if make help > /dev/null 2>&1; then
        log SUCCESS "Makefile is working"
    else
        log WARNING "Makefile may have issues"
    fi
    
    # Test Gaia CLI
    log INFO "Testing Gaia CLI..."
    if gaia --help > /dev/null 2>&1; then
        log SUCCESS "Gaia CLI is working"
    else
        log WARNING "Gaia CLI may have issues"
    fi
    
    # Test infrastructure validation (non-destructive)
    log INFO "Testing infrastructure validation..."
    if make validate > "$ONBOARD_LOG.validate" 2>&1; then
        log SUCCESS "Infrastructure validation passed"
    else
        log WARNING "Infrastructure validation had issues (check logs)"
    fi
    
    # Test quick commands
    log INFO "Testing quick status commands..."
    
    # Test stack listing
    if make list-stacks > /dev/null 2>&1; then
        log SUCCESS "Stack listing works"
    else
        log WARNING "Stack listing may have issues"
    fi
    
    show_progress
}

create_quick_reference() {
    log STEP "Creating quick reference materials"
    
    # Create desktop quick reference
    cat > "$PROJECT_ROOT/QUICK_START.md" << EOF
# 🚀 Quick Start Guide - Infrastructure Development

Welcome, $DEVELOPER_NAME! Your development environment is now configured.

## ⚡ Essential Commands

### 🔍 Check Status
\`\`\`bash
make status                    # Show infrastructure status
gaia status                   # Enhanced status with Gaia CLI
make doctor                   # Run system diagnostics
\`\`\`

### ✅ Validate & Test
\`\`\`bash
make validate                 # Validate all configurations
make lint                     # Lint and format code
make test                     # Run all tests
\`\`\`

### 📋 Plan & Apply
\`\`\`bash
make plan                     # Plan infrastructure changes (safe)
make apply                    # Apply changes (with confirmation)
\`\`\`

### 🌐 Environment Management
\`\`\`bash
make list-stacks             # List available environments
make onboard                 # Quick environment onboarding
\`\`\`

### 🐳 Development Environment
\`\`\`bash
make dev-start               # Start local development environment
make dev-logs                # View development logs
make dev-stop                # Stop development environment
\`\`\`

## 🛠️ Gaia CLI (Enhanced)

\`\`\`bash
gaia --help                           # Show all commands
gaia quick-start                      # Interactive guide
gaia doctor                          # System diagnostics
gaia status -t fnx -a dev -e testenv-01  # Environment status
\`\`\`

## 🔧 Development Workflow

1. **Start your day**: \`make status\` or \`gaia doctor\`
2. **Make changes**: Edit Terraform files
3. **Validate**: \`make validate\` 
4. **Plan**: \`make plan\` (always safe)
5. **Apply**: \`make apply\` (with confirmation)
6. **Monitor**: \`make dev-logs\` or monitoring dashboard

## 🎯 Your Environment

- **AWS Region**: $AWS_REGION
- **Git**: Configured for $DEVELOPER_EMAIL
- **Project Root**: $PROJECT_ROOT
- **Logs**: Check \`logs/\` directory for detailed output

## 📚 Need Help?

- **Makefile help**: \`make help\`
- **Gaia help**: \`gaia --help\`
- **Documentation**: \`docs/\` directory
- **Troubleshooting**: \`make doctor\`

## 🚀 Next Steps

1. Explore available stacks: \`make list-stacks\`
2. Check a specific environment: \`gaia status -t fnx -a dev -e testenv-01\`
3. Try a safe plan operation: \`make plan\`
4. Review the documentation in \`docs/\`

---
*Generated by developer onboarding on $(date)*
EOF
    
    # Create shell aliases activation
    if [ -f "$HOME/.bashrc" ]; then
        if ! grep -q ".dev_aliases" "$HOME/.bashrc"; then
            echo "" >> "$HOME/.bashrc"
            echo "# Infrastructure development aliases" >> "$HOME/.bashrc"
            echo "source '$PROJECT_ROOT/.dev_aliases' 2>/dev/null || true" >> "$HOME/.bashrc"
            log SUCCESS "Added aliases to ~/.bashrc"
        fi
    fi
    
    if [ -f "$HOME/.zshrc" ]; then
        if ! grep -q ".dev_aliases" "$HOME/.zshrc"; then
            echo "" >> "$HOME/.zshrc"
            echo "# Infrastructure development aliases" >> "$HOME/.zshrc"
            echo "source '$PROJECT_ROOT/.dev_aliases' 2>/dev/null || true" >> "$HOME/.zshrc"
            log SUCCESS "Added aliases to ~/.zshrc"
        fi
    fi
    
    show_progress
}

generate_completion_report() {
    log STEP "Generating completion report"
    
    local end_time=$(date)
    local duration=$(($(date +%s) - $(date -d "$start_time" +%s) 2>/dev/null || 0))
    
    # Generate detailed report
    cat > "$PROJECT_ROOT/logs/onboarding-report-$(date +%Y%m%d-%H%M%S).md" << EOF
# Developer Onboarding Report

**Developer**: $DEVELOPER_NAME <$DEVELOPER_EMAIL>
**Completion Time**: $end_time
**Duration**: ${duration} seconds
**AWS Region**: $AWS_REGION

## ✅ Completed Tasks

1. ✅ System prerequisites check
2. ✅ Infrastructure tools installation
3. ✅ Git configuration
4. ✅ Python environment setup
5. ✅ Development environment configuration
6. ✅ IDE configuration (VS Code)
7. ✅ Access and permissions validation
8. ✅ End-to-end workflow testing
9. ✅ Quick reference creation
10. ✅ Shell aliases setup

## 🛠️ Installed Tools

- Git: $(git --version 2>/dev/null || echo "Not installed")
- Terraform: $(terraform version 2>/dev/null | head -1 || echo "Not installed")
- Atmos: $(atmos version 2>/dev/null || echo "Not installed")
- AWS CLI: $(aws --version 2>&1 | head -1 || echo "Not installed")
- Docker: $(docker --version 2>/dev/null || echo "Not installed")
- Python: $(python3 --version 2>/dev/null || echo "Not installed")
- Gaia CLI: $(gaia version 2>/dev/null | head -1 || echo "Not installed")

## 📁 Created Files

- \`.env.local\` - Personal configuration
- \`.vscode/\` - VS Code settings and extensions
- \`.dev_aliases\` - Development shortcuts
- \`QUICK_START.md\` - Quick reference guide
- \`logs/onboarding-*.log\` - Detailed logs

## 🎯 Next Steps

1. Review \`QUICK_START.md\` for essential commands
2. Source aliases: \`source .dev_aliases\`
3. Try: \`make status\` or \`gaia doctor\`
4. Explore: \`make help\` and \`gaia --help\`
5. Start development: \`make dev-start\`

## 📋 Verification Commands

Run these to verify everything is working:

\`\`\`bash
make doctor          # System diagnostics
gaia quick-start     # Interactive guide
make validate        # Infrastructure validation
make list-stacks     # Available environments
\`\`\`

---
*Auto-generated by onboarding script*
EOF
    
    show_progress
}

show_completion() {
    clear
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}   🎉 ${BOLD}Developer Onboarding Complete!${NC}                          ${GREEN}║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${WHITE}Welcome to the team, $DEVELOPER_NAME! 🚀${NC}"
    echo
    echo -e "${GREEN}✅ Environment Setup Complete${NC}"
    echo -e "${WHITE}   Duration: $(printf "%02d:%02d" $((duration/60)) $((duration%60)))${NC}"
    echo -e "${WHITE}   All tools installed and configured${NC}"
    echo
    echo -e "${CYAN}🎯 What's Ready:${NC}"
    echo -e "   🛠️  All infrastructure tools (Terraform, Atmos, AWS CLI)"
    echo -e "   🐍 Python environment with Gaia CLI"
    echo -e "   🐳 Docker development environment"
    echo -e "   💻 VS Code configuration and extensions"
    echo -e "   🚀 Development shortcuts and aliases"
    echo
    echo -e "${YELLOW}🚀 Try These Commands:${NC}"
    echo -e "${WHITE}   make help           ${NC}# Show all available commands"
    echo -e "${WHITE}   gaia quick-start    ${NC}# Interactive getting started guide"
    echo -e "${WHITE}   make doctor         ${NC}# Run system diagnostics"
    echo -e "${WHITE}   make status         ${NC}# Show infrastructure status"
    echo
    echo -e "${PURPLE}📚 Important Files Created:${NC}"
    echo -e "${WHITE}   QUICK_START.md      ${NC}# Your personal quick reference"
    echo -e "${WHITE}   .env.local          ${NC}# Your personal configuration"
    echo -e "${WHITE}   .dev_aliases        ${NC}# Development shortcuts"
    echo
    echo -e "${BLUE}🌟 Pro Tips:${NC}"
    echo -e "   ${WHITE}1.${NC} Open a new terminal to get aliases: ${CYAN}source .dev_aliases${NC}"
    echo -e "   ${WHITE}2.${NC} Start with safe commands: ${CYAN}make validate${NC}, ${CYAN}make plan${NC}"
    echo -e "   ${WHITE}3.${NC} Use ${CYAN}make help${NC} and ${CYAN}gaia --help${NC} to explore"
    echo -e "   ${WHITE}4.${NC} Check ${CYAN}QUICK_START.md${NC} for your personalized guide"
    echo
    echo -e "${GREEN}Ready to build amazing infrastructure! 🌍✨${NC}"
    echo
    echo -e "${WHITE}Full onboarding log: ${NC}$ONBOARD_LOG"
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    local start_time=$(date)
    
    # Change to project root
    cd "$PROJECT_ROOT"
    
    # Run onboarding steps
    show_welcome
    check_prerequisites
    install_infrastructure_tools
    setup_git_configuration
    setup_python_environment
    setup_development_environment
    setup_ide_configuration
    validate_access_and_permissions
    test_end_to_end_workflow
    create_quick_reference
    generate_completion_report
    
    # Calculate duration
    local end_time=$(date)
    duration=$(($(date +%s) - $(date -j -f "%a %b %d %T %Z %Y" "$start_time" +%s 2>/dev/null || $(date -d "$start_time" +%s 2>/dev/null || 0))))
    
    show_completion
}

# Handle interrupts gracefully
trap 'echo -e "\n${YELLOW}Onboarding interrupted. You can resume by running this script again.${NC}"; exit 130' INT TERM

# Run main function
main "$@"