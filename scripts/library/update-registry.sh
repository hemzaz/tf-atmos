#!/bin/bash
#
# Registry Update Script
# Updates the module registry from component directories
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
COMPONENTS_DIR="${PROJECT_ROOT}/components/terraform"
REGISTRY_FILE="${PROJECT_ROOT}/stacks/catalog/_library/module-registry.yaml"

echo "=== Updating Module Registry ==="
echo ""
echo "Scanning components directory: $COMPONENTS_DIR"
echo ""

# Count components
total=0
updated=0

for dir in "${COMPONENTS_DIR}"/*/; do
    if [ -d "$dir" ]; then
        module=$(basename "$dir")
        total=$((total + 1))

        # Check if module exists in registry
        exists=$(yq eval ".modules.${module}" "$REGISTRY_FILE" 2>/dev/null)

        if [ "$exists" != "null" ] && [ -n "$exists" ]; then
            echo "  [EXISTS] $module"
        else
            echo "  [MISSING] $module - Not in registry"
            updated=$((updated + 1))
        fi
    fi
done

echo ""
echo "Summary:"
echo "  Total components: $total"
echo "  Missing from registry: $updated"
echo ""

if [ $updated -gt 0 ]; then
    echo "To add missing modules, update:"
    echo "  $REGISTRY_FILE"
fi
