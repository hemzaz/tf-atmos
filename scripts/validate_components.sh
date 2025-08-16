#!/usr/bin/env bash
# Script to validate Atmos components and stacks

# Set to the repository root directory
REPO_ROOT="/Users/elad/IdeaProjects/tf-atmos"
cd "$REPO_ROOT" || exit 1

echo "===================== VALIDATING CATALOG TENANT VALUES ====================="
echo "Checking if all catalog components have tenant defined..."
if [ -f "./scripts/validate_catalog_tenant.py" ]; then
  ./scripts/validate_catalog_tenant.py
else
  echo "Validation script not found. Run this first:"
  echo "chmod +x ./scripts/validate_catalog_tenant.py"
fi
echo ""

echo "===================== ADDING TENANT TO CATALOG COMPONENTS =================="
echo "Would you like to add tenant to catalog components? (y/n)"
read -r add_tenant
if [[ "$add_tenant" == "y" ]]; then
  if [ -f "./scripts/add_tenant_to_catalog.py" ]; then
    ./scripts/add_tenant_to_catalog.py
  else
    echo "Tenant addition script not found. Run this first:"
    echo "chmod +x ./scripts/add_tenant_to_catalog.py"
  fi
fi
echo ""

echo "===================== ATMOS STACKS LISTING ================================"
echo "Listing all stacks with the current configuration:"
atmos list stacks
echo ""

echo "===================== STACKS DETAILS ======================================"
echo "Showing stack details:"
atmos describe stacks
echo ""

echo "===================== CATALOG COMPONENTS ==================================="
echo "Listing catalog components:"
ls -la ./stacks/catalog/
echo ""

echo "===================== ENVIRONMENT COMPONENTS ==============================="
echo "Listing environment components:"
ls -la ./stacks/account/dev/testenv-01/
echo ""

echo "===================== VALIDATION COMPLETE ================================="