#\!/bin/bash
# DEPRECATED: This script has been renamed to 'gaia-ops'.
# This compatibility script will be removed in a future version.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "⚠️  Warning: 'atmos-ops' is deprecated and will be removed in a future version."
echo "Please use 'gaia-ops' instead."
echo ""

# Execute the new script
exec "${SCRIPT_DIR}/gaia-ops" "$@"
