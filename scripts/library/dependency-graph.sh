#!/bin/bash
#
# Dependency Graph Generator
# Shows module dependencies in a tree format
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REGISTRY_FILE="${PROJECT_ROOT}/stacks/catalog/_library/module-registry.yaml"

echo "=== Module Dependency Graph ==="
echo ""

# Check if yq is available
if ! command -v yq &> /dev/null; then
    echo "Error: yq is required"
    exit 1
fi

# Get all modules
modules=$(yq eval '.modules | keys | .[]' "$REGISTRY_FILE")

# Print modules without dependencies first (root modules)
echo "Root Modules (no dependencies):"
echo "-------------------------------"
for module in $modules; do
    deps=$(yq eval ".modules.${module}.dependencies | length" "$REGISTRY_FILE" 2>/dev/null || echo "0")
    if [ "$deps" -eq 0 ]; then
        echo "  [ROOT] $module"
    fi
done

echo ""
echo "Module Dependencies:"
echo "-------------------"

# Print dependency tree
for module in $modules; do
    deps=$(yq eval ".modules.${module}.dependencies | length" "$REGISTRY_FILE" 2>/dev/null || echo "0")
    if [ "$deps" -gt 0 ]; then
        echo "$module"
        yq eval ".modules.${module}.dependencies[]" "$REGISTRY_FILE" 2>/dev/null | while read dep; do
            echo "  -> $dep"
        done
        echo ""
    fi
done

echo ""
echo "Reverse Dependencies (what depends on what):"
echo "--------------------------------------------"

for module in $modules; do
    dependents=$(yq eval ".modules.${module}.dependents | length" "$REGISTRY_FILE" 2>/dev/null || echo "0")
    if [ "$dependents" -gt 0 ] && [ "$dependents" != "null" ]; then
        echo "$module is required by:"
        yq eval ".modules.${module}.dependents[]" "$REGISTRY_FILE" 2>/dev/null | while read dep; do
            echo "  <- $dep"
        done
        echo ""
    fi
done
