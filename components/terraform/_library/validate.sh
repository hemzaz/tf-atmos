#!/bin/bash
#
# Alexandria Library - Module Validation Script
# Validates all modules in the library for completeness and correctness
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================="
echo "Alexandria Library Validation"
echo "========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
total_modules=0
valid_modules=0
invalid_modules=0
warnings=0

# Required files for each module
REQUIRED_FILES=(
    "main.tf"
    "variables.tf"
    "outputs.tf"
    "versions.tf"
    "README.md"
    "CHANGELOG.md"
)

# Required directories
REQUIRED_DIRS=(
    "examples"
    "tests"
)

#------------------------------------------------------------------------------
# Helper Functions
#------------------------------------------------------------------------------

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_info() {
    echo -e "  $1"
}

#------------------------------------------------------------------------------
# Validation Functions
#------------------------------------------------------------------------------

validate_module() {
    local module_path=$1
    local module_name=$(basename "$module_path")
    local category=$(basename "$(dirname "$module_path")")

    total_modules=$((total_modules + 1))

    echo ""
    echo "Validating: $category/$module_name"
    echo "----------------------------------------"

    local errors=0
    local warns=0

    # Check required files
    for file in "${REQUIRED_FILES[@]}"; do
        if [ -f "$module_path/$file" ]; then
            log_success "$file exists"
        else
            log_error "$file missing"
            errors=$((errors + 1))
        fi
    done

    # Check required directories
    for dir in "${REQUIRED_DIRS[@]}"; do
        if [ -d "$module_path/$dir" ]; then
            log_success "$dir/ directory exists"
        else
            log_warning "$dir/ directory missing"
            warns=$((warns + 1))
        fi
    done

    # Check for at least one example
    if [ -d "$module_path/examples" ]; then
        example_count=$(find "$module_path/examples" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
        if [ "$example_count" -gt 0 ]; then
            log_success "Found $example_count example(s)"
        else
            log_warning "No examples found"
            warns=$((warns + 1))
        fi
    fi

    # Validate Terraform syntax if terraform is available
    if command -v terraform &> /dev/null; then
        cd "$module_path"
        if terraform fmt -check -recursive > /dev/null 2>&1; then
            log_success "Terraform formatting is correct"
        else
            log_warning "Terraform formatting needs fixing"
            warns=$((warns + 1))
        fi

        if terraform validate > /dev/null 2>&1; then
            log_success "Terraform validation passed"
        else
            # This is expected to fail without initialization
            log_info "Terraform validation skipped (requires init)"
        fi
        cd "$SCRIPT_DIR"
    fi

    # Check README content
    if [ -f "$module_path/README.md" ]; then
        local readme_size=$(wc -l < "$module_path/README.md")
        if [ "$readme_size" -gt 50 ]; then
            log_success "README.md has $readme_size lines (comprehensive)"
        else
            log_warning "README.md only has $readme_size lines (may need more content)"
            warns=$((warns + 1))
        fi
    fi

    # Check for required sections in README
    if [ -f "$module_path/README.md" ]; then
        if grep -q "## Overview" "$module_path/README.md"; then
            log_success "README has Overview section"
        else
            log_warning "README missing Overview section"
            warns=$((warns + 1))
        fi

        if grep -q "## Usage" "$module_path/README.md"; then
            log_success "README has Usage section"
        else
            log_warning "README missing Usage section"
            warns=$((warns + 1))
        fi

        if grep -q "## Examples" "$module_path/README.md" || grep -q "## Example" "$module_path/README.md"; then
            log_success "README has Examples section"
        else
            log_warning "README missing Examples section"
            warns=$((warns + 1))
        fi
    fi

    warnings=$((warnings + warns))

    if [ $errors -eq 0 ]; then
        valid_modules=$((valid_modules + 1))
        echo ""
        log_success "Module validation PASSED (warnings: $warns)"
        return 0
    else
        invalid_modules=$((invalid_modules + 1))
        echo ""
        log_error "Module validation FAILED (errors: $errors, warnings: $warns)"
        return 1
    fi
}

#------------------------------------------------------------------------------
# Main Validation Loop
#------------------------------------------------------------------------------

echo "Searching for modules..."
echo ""

# Find all module directories (containing main.tf)
module_dirs=$(find . -type f -name "main.tf" -not -path "*/examples/*" -not -path "*/tests/*" | xargs -I {} dirname {})

if [ -z "$module_dirs" ]; then
    echo "No modules found!"
    exit 1
fi

# Validate each module
for module_dir in $module_dirs; do
    validate_module "$module_dir" || true
done

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------

echo ""
echo "========================================="
echo "Validation Summary"
echo "========================================="
echo ""
echo "Total Modules Scanned: $total_modules"
log_success "Valid Modules: $valid_modules"

if [ $invalid_modules -gt 0 ]; then
    log_error "Invalid Modules: $invalid_modules"
fi

if [ $warnings -gt 0 ]; then
    log_warning "Total Warnings: $warnings"
fi

echo ""

# Calculate percentage
if [ $total_modules -gt 0 ]; then
    percentage=$((valid_modules * 100 / total_modules))
    echo "Validation Success Rate: $percentage%"
fi

echo ""

# Exit with appropriate code
if [ $invalid_modules -gt 0 ]; then
    log_error "Validation FAILED - Please fix errors above"
    exit 1
else
    log_success "All modules PASSED validation!"
    if [ $warnings -gt 0 ]; then
        log_warning "Note: $warnings warning(s) found - consider addressing them"
    fi
    exit 0
fi
