#!/usr/bin/env bash
# =============================================================================
# CI/CD Setup Verification Script
# =============================================================================
# Verifies that all CI/CD components are properly configured

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Helper functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; ((PASSED++)); }
log_error() { echo -e "${RED}[✗]${NC} $1"; ((FAILED++)); }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; ((WARNINGS++)); }

echo "========================================="
echo "  CI/CD Setup Verification"
echo "========================================="
echo

# Check GitHub Actions workflows
log_info "Checking GitHub Actions workflows..."
REQUIRED_WORKFLOWS=(
    ".github/workflows/terraform-ci.yml"
    ".github/workflows/terraform-cd.yml"
    ".github/workflows/security-scan.yml"
    ".github/workflows/drift-detection.yml"
)

for workflow in "${REQUIRED_WORKFLOWS[@]}"; do
    if [ -f "$workflow" ]; then
        log_success "Workflow exists: $workflow"
    else
        log_error "Workflow missing: $workflow"
    fi
done
echo

# Check pre-commit configuration
log_info "Checking pre-commit configuration..."
if [ -f ".pre-commit-config.yaml" ]; then
    log_success "Pre-commit config exists"

    if command -v pre-commit &>/dev/null; then
        log_success "Pre-commit installed"

        if pre-commit run --all-files --dry-run &>/dev/null; then
            log_success "Pre-commit configuration valid"
        else
            log_warning "Pre-commit configuration may have issues"
        fi
    else
        log_warning "Pre-commit not installed (pip install pre-commit)"
    fi
else
    log_error "Pre-commit config missing"
fi
echo

# Check TFLint configuration
log_info "Checking TFLint configuration..."
if [ -f ".tflint.hcl" ]; then
    log_success "TFLint config exists"
else
    log_warning "TFLint config missing"
fi
echo

# Check test directories
log_info "Checking test framework..."
TEST_DIRS=(
    "tests/integration"
    "tests/smoke"
    "tests/security"
)

for dir in "${TEST_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        log_success "Test directory exists: $dir"

        # Count test files
        test_count=$(find "$dir" -name "test_*.py" -o -name "test_*.sh" 2>/dev/null | wc -l)
        if [ "$test_count" -gt 0 ]; then
            log_success "  Found $test_count test file(s)"
        fi
    else
        log_warning "Test directory missing: $dir"
    fi
done

if [ -f "pytest.ini" ]; then
    log_success "Pytest configuration exists"
else
    log_warning "Pytest configuration missing"
fi

if [ -f "requirements-test.txt" ]; then
    log_success "Test requirements file exists"
else
    log_warning "Test requirements file missing"
fi
echo

# Check deployment scripts
log_info "Checking deployment scripts..."
REQUIRED_SCRIPTS=(
    "scripts/bootstrap.sh"
    "scripts/deploy.sh"
    "scripts/utils.sh"
)

for script in "${REQUIRED_SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        log_success "Script exists: $script"

        if [ -x "$script" ]; then
            log_success "  Script is executable"
        else
            log_warning "  Script not executable (chmod +x $script)"
        fi
    else
        log_error "Script missing: $script"
    fi
done
echo

# Check Docker files
log_info "Checking Docker development environment..."
if [ -f "Dockerfile.devops" ]; then
    log_success "Dockerfile exists"
else
    log_warning "Dockerfile missing"
fi

if [ -f "docker-compose.devops.yml" ]; then
    log_success "Docker Compose file exists"
else
    log_warning "Docker Compose file missing"
fi

if [ -f ".dockerignore" ]; then
    log_success "Docker ignore file exists"
else
    log_warning "Docker ignore file missing"
fi
echo

# Check documentation
log_info "Checking documentation..."
REQUIRED_DOCS=(
    "CI-CD-README.md"
    "DEVOPS-IMPLEMENTATION-SUMMARY.md"
    "QUICK-START-CICD.md"
)

for doc in "${REQUIRED_DOCS[@]}"; do
    if [ -f "$doc" ]; then
        log_success "Documentation exists: $doc"
    else
        log_warning "Documentation missing: $doc"
    fi
done
echo

# Check tool installations
log_info "Checking required tools..."
REQUIRED_TOOLS=(
    "terraform"
    "atmos"
    "aws"
    "docker"
    "git"
    "jq"
)

for tool in "${REQUIRED_TOOLS[@]}"; do
    if command -v "$tool" &>/dev/null; then
        version=$($tool --version 2>&1 | head -1 || echo "unknown")
        log_success "Tool installed: $tool ($version)"
    else
        log_warning "Tool not installed: $tool"
    fi
done
echo

# Check AWS credentials
log_info "Checking AWS credentials..."
if command -v aws &>/dev/null; then
    if aws sts get-caller-identity &>/dev/null; then
        account=$(aws sts get-caller-identity --query 'Account' --output text)
        log_success "AWS credentials valid (Account: $account)"
    else
        log_warning "AWS credentials not configured or invalid"
    fi
else
    log_warning "AWS CLI not installed"
fi
echo

# Check GitHub CLI (optional)
log_info "Checking GitHub CLI (optional)..."
if command -v gh &>/dev/null; then
    if gh auth status &>/dev/null; then
        log_success "GitHub CLI authenticated"
    else
        log_warning "GitHub CLI not authenticated (gh auth login)"
    fi
else
    log_warning "GitHub CLI not installed (optional)"
fi
echo

# Check project structure
log_info "Checking project structure..."
REQUIRED_DIRS=(
    "components/terraform"
    "stacks"
    "workflows"
    "scripts"
    "tests"
)

for dir in "${REQUIRED_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        log_success "Directory exists: $dir"
    else
        log_error "Directory missing: $dir"
    fi
done

if [ -f "atmos.yaml" ]; then
    log_success "Atmos configuration exists"
else
    log_error "Atmos configuration missing"
fi

if [ -f "Makefile" ]; then
    log_success "Makefile exists"
else
    log_warning "Makefile missing"
fi
echo

# Summary
echo "========================================="
echo "  Verification Summary"
echo "========================================="
echo -e "${GREEN}Passed:${NC}   $PASSED"
echo -e "${RED}Failed:${NC}   $FAILED"
echo -e "${YELLOW}Warnings:${NC} $WARNINGS"
echo "========================================="
echo

# Recommendations
if [ "$FAILED" -gt 0 ]; then
    echo -e "${RED}CRITICAL ISSUES FOUND${NC}"
    echo "Please fix failed checks before proceeding."
    echo
elif [ "$WARNINGS" -gt 0 ]; then
    echo -e "${YELLOW}WARNINGS FOUND${NC}"
    echo "Some optional components are missing or not configured."
    echo "CI/CD should work, but consider addressing warnings."
    echo
else
    echo -e "${GREEN}ALL CHECKS PASSED!${NC}"
    echo "CI/CD setup is complete and ready to use."
    echo
fi

# Next steps
echo "Next Steps:"
echo "1. Configure GitHub repository secrets"
echo "2. Set up environment protection rules"
echo "3. Enable branch protection on main"
echo "4. Test CI pipeline with a PR"
echo "5. Bootstrap infrastructure: ./scripts/bootstrap.sh"
echo
echo "Quick Start Guide: QUICK-START-CICD.md"
echo "Full Documentation: CI-CD-README.md"
echo

# Exit code
if [ "$FAILED" -gt 0 ]; then
    exit 1
else
    exit 0
fi
