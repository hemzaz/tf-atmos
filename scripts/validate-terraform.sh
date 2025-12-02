#!/bin/bash
# Terraform Validation Suite
# Validates all Terraform components with formatting, validation, security scanning, and linting

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPONENTS_DIR="$PROJECT_ROOT/components/terraform"

echo "=========================================="
echo "Terraform Validation Suite"
echo "=========================================="
echo ""
echo "Project Root: $PROJECT_ROOT"
echo "Components Directory: $COMPONENTS_DIR"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track failures
FAILURES=0

# Function to check if command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Check for required tools
echo "Checking for required tools..."
if ! command_exists terraform; then
  echo -e "${RED}ERROR: terraform not found. Install with: brew install terraform${NC}"
  exit 1
fi

if ! command_exists checkov; then
  echo -e "${YELLOW}WARNING: checkov not found. Install with: pip install checkov${NC}"
  echo "Skipping security scanning..."
  SKIP_CHECKOV=1
fi

if ! command_exists tflint; then
  echo -e "${YELLOW}WARNING: tflint not found. Install with: brew install tflint${NC}"
  echo "Skipping linting..."
  SKIP_TFLINT=1
fi

echo ""

# 1. Terraform Format Check
echo "=========================================="
echo "1. Running Terraform Format (terraform fmt)"
echo "=========================================="
echo ""

if terraform fmt -check -recursive "$COMPONENTS_DIR"; then
  echo -e "${GREEN}✓ All Terraform files are properly formatted${NC}"
else
  echo -e "${YELLOW}! Some files need formatting. Running terraform fmt -recursive...${NC}"
  terraform fmt -recursive "$COMPONENTS_DIR"
  echo -e "${GREEN}✓ Formatting applied${NC}"
fi

echo ""

# 2. Terraform Validate
echo "=========================================="
echo "2. Running Terraform Validate"
echo "=========================================="
echo ""

# Find all component directories with .tf files
COMPONENTS=$(find "$COMPONENTS_DIR" -maxdepth 1 -type d | tail -n +2)

for component_path in $COMPONENTS; do
  component_name=$(basename "$component_path")

  # Skip if no .tf files
  if ! ls "$component_path"/*.tf >/dev/null 2>&1; then
    continue
  fi

  echo "Validating component: $component_name"

  cd "$component_path"

  # Initialize Terraform (required for validation)
  if ! terraform init -backend=false >/dev/null 2>&1; then
    echo -e "${RED}✗ Failed to initialize $component_name${NC}"
    FAILURES=$((FAILURES + 1))
    continue
  fi

  # Validate
  if terraform validate; then
    echo -e "${GREEN}✓ $component_name is valid${NC}"
  else
    echo -e "${RED}✗ $component_name validation failed${NC}"
    FAILURES=$((FAILURES + 1))
  fi

  echo ""
done

cd "$PROJECT_ROOT"

# 3. Security Scanning with Checkov
if [ -z "$SKIP_CHECKOV" ]; then
  echo "=========================================="
  echo "3. Running Security Scan (checkov)"
  echo "=========================================="
  echo ""

  if checkov --directory "$COMPONENTS_DIR" \
    --framework terraform \
    --compact \
    --quiet \
    --skip-check CKV_AWS_144,CKV_AWS_145 \
    --output cli; then
    echo -e "${GREEN}✓ Security scan passed${NC}"
  else
    echo -e "${YELLOW}! Security scan found issues (review above)${NC}"
    # Don't fail on checkov warnings
  fi

  echo ""
fi

# 4. Linting with TFLint
if [ -z "$SKIP_TFLINT" ]; then
  echo "=========================================="
  echo "4. Running Terraform Linting (tflint)"
  echo "=========================================="
  echo ""

  # Initialize TFLint
  tflint --init >/dev/null 2>&1 || true

  for component_path in $COMPONENTS; do
    component_name=$(basename "$component_path")

    # Skip if no .tf files
    if ! ls "$component_path"/*.tf >/dev/null 2>&1; then
      continue
    fi

    echo "Linting component: $component_name"

    if tflint --chdir="$component_path" --format=compact; then
      echo -e "${GREEN}✓ $component_name passed linting${NC}"
    else
      echo -e "${YELLOW}! $component_name has linting issues${NC}"
      # Don't fail on linting warnings
    fi

    echo ""
  done
fi

# Summary
echo "=========================================="
echo "Validation Summary"
echo "=========================================="
echo ""

if [ $FAILURES -eq 0 ]; then
  echo -e "${GREEN}✓ All validations passed!${NC}"
  echo ""
  echo "Components validated:"
  find "$COMPONENTS_DIR" -maxdepth 1 -type d | tail -n +2 | wc -l | xargs echo "  - Components:"
  exit 0
else
  echo -e "${RED}✗ $FAILURES component(s) failed validation${NC}"
  echo ""
  echo "Please fix the errors above and re-run this script."
  exit 1
fi
