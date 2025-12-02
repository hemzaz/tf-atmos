#!/bin/bash
#
# Stack Generator
# Generates a stack configuration from a blueprint template
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

BLUEPRINT=$1
TENANT=$2
ENVIRONMENT=$3

if [ -z "$BLUEPRINT" ] || [ -z "$TENANT" ] || [ -z "$ENVIRONMENT" ]; then
    echo "Usage: $0 <blueprint> <tenant> <environment>"
    echo ""
    echo "Example: $0 web-app-stack fnx dev"
    exit 1
fi

TEMPLATE_FILE="${PROJECT_ROOT}/stacks/catalog/_library/templates/${BLUEPRINT}.yaml"

if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Error: Blueprint '$BLUEPRINT' not found"
    echo ""
    echo "Available blueprints:"
    ls -1 "${PROJECT_ROOT}/stacks/catalog/_library/templates/" | sed 's/\.yaml$//'
    exit 1
fi

# Create output directory
OUTPUT_DIR="${PROJECT_ROOT}/stacks/orgs/${TENANT}/${ENVIRONMENT}/generated"
mkdir -p "$OUTPUT_DIR"

# Generate stack file
OUTPUT_FILE="${OUTPUT_DIR}/${BLUEPRINT}-generated.yaml"

echo "Generating stack from blueprint: $BLUEPRINT"
echo "  Tenant: $TENANT"
echo "  Environment: $ENVIRONMENT"
echo "  Output: $OUTPUT_FILE"
echo ""

# Use yq to substitute variables
cat "$TEMPLATE_FILE" | \
    sed "s/\${tenant}/${TENANT}/g" | \
    sed "s/\${environment}/${ENVIRONMENT}/g" | \
    sed "s/\${region}/\${region}/g" > "$OUTPUT_FILE"

echo "Stack generated successfully!"
echo ""
echo "Next steps:"
echo "  1. Review the generated stack: $OUTPUT_FILE"
echo "  2. Customize variables as needed"
echo "  3. Deploy using: atmos terraform apply <component> -s ${TENANT}-${ENVIRONMENT}"
